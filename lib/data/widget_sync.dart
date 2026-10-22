import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:home_widget/home_widget.dart';

import '../models/item.dart';
import '../models/kr_calendar.dart';
import '../models/lunar.dart' show dayNumber;

const _wdKo = ['월', '화', '수', '목', '금', '토', '일']; // DateTime.weekday: 1=월 ... 7=일
String _two(int v) => v.toString().padLeft(2, '0');

/// "10월 4일 (일)" (intl 로케일 데이터 없이 만든다: 백그라운드 격리 작업에서도 같은 글자가 나오게)
String _koDay(DateTime d) => '${d.month}월 ${d.day}일 (${_wdKo[d.weekday - 1]})';

/// 안드로이드 홈화면 위젯에 일정/할 일을 밀어 넣는다.
/// 네이티브 쪽은 android/.../OurDayWidget.kt 가 SharedPreferences에서 읽는다.
///  - body: 목록형 위젯에 보일 앞으로 며칠치 일정/할 일 (글자)
///  - eventDays: 달력형 위젯에 표시할 "일정이 있는 날" (yyyyMMdd를 쉼표로)
class WidgetSync {
  static const _provider = 'OurDayWidget';
  static const _agendaDays = 7;
  static const _pastDays = 366; // 지난 1년
  static const _jsonMaxPast = 500; // 지난 날 항목 상한 (앞으로 쪽 상한과 따로 센다)
  static const _maxLines = 10;
  static const _jsonDays = 366;
  static const _jsonMaxItems = 600;

  static String _line(Item i, DateTime day) {
    final t = timeLabel(i);
    final title = t == null ? i.title : '$t ${i.title}';
    if (i.type == ItemType.todo) return '${isDoneOn(i, day) ? '☑' : '☐'} $title';
    return '• $title';
  }

  /// 기간 [from]~[to] 의 날짜별 항목 (일정 먼저, 그다음 시작 시각순). 키는 lunar.dart 의 dayNumber.
  /// 항목마다 자기가 나타날 수 있는 날만 훑어서(반복은 종료일/횟수/제외 날짜까지 반영) 날마다 모든 항목을 검사하던 것보다 훨씬 빠르다.
  /// 결과는 [occursOn] 으로 날마다 거른 것과 같다 (test/widget_sync_test.dart 에서 비교).
  static Map<int, List<Item>> dayIndex(List<Item> visible, DateTime from, DateTime to) {
    final f = dayNumber(from), t = dayNumber(to);
    final out = <int, List<Item>>{};
    for (final i in visible) {
      final s = dayNumber(i.start);
      final rule = i.effectiveRule;
      if (rule == null) {
        final e = i.end == null ? s : dayNumber(i.end!);
        for (var d = math.max(s, f); d <= math.min(e, t); d++) {
          (out[d] ??= []).add(i);
        }
        continue;
      }
      var last = t;
      if (i.repeatUntil != null) last = math.min(last, dayNumber(i.repeatUntil!));
      if (rule.until != null) last = math.min(last, dayNumber(rule.until!));
      if (rule.count != null) {
        final lo = rule.lastOccurrenceDn(s);
        if (lo == null) continue; // 횟수 규칙인데 끝을 못 찾으면 나타나는 날이 없다 (occursOn 과 같음)
        last = math.min(last, lo);
      }
      // 제외한 날(yyyy-MM-dd)도 일수로 바꿔 두고 비교한다
      final skip = i.exceptions.isEmpty ? null : {for (final k in i.exceptions) ?_keyToDn(k)};
      for (var d = math.max(s, f); d <= last; d++) {
        if (skip != null && skip.contains(d)) continue;
        if (rule.matchesDn(s, d)) (out[d] ??= []).add(i);
      }
    }
    for (final list in out.values) {
      list.sort((a, b) {
        if (a.type != b.type) return a.type == ItemType.event ? -1 : 1;
        final c = a.start.compareTo(b.start);
        return c != 0 ? c : a.id.compareTo(b.id);
      });
    }
    return out;
  }

  static int? _keyToDn(String k) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(k);
    return m == null ? null : dayNumber(DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!)));
  }

  static List<Item> _on(Map<int, List<Item>> idx, DateTime day) => idx[dayNumber(day)] ?? const [];

  /// 위젯 데이터가 훑는 전체 기간 (목록형: 지난 1년~앞으로 1년, 달력형: 24개월 전~13개월 뒤)
  static (DateTime, DateTime) rangeFor(DateTime today) {
    final calStart = DateTime(today.year, today.month - 24, 1);
    final calEnd = DateTime(today.year, today.month + 13, 0);
    final listStart = DateTime(today.year, today.month, today.day - _pastDays);
    final listEnd = DateTime(today.year, today.month, today.day + _jsonDays);
    return (calStart.isBefore(listStart) ? calStart : listStart, calEnd.isAfter(listEnd) ? calEnd : listEnd);
  }

  /// 목록형 위젯 글자: 오늘 + 앞으로 며칠 (날짜 머리글 포함, 최대 [_maxLines]줄)
  static String agendaText(List<Item> visible, DateTime today, {Map<int, List<Item>>? index}) {
    final lines = <String>[];
    final idx = index ?? dayIndex(visible, today, DateTime(today.year, today.month, today.day + _agendaDays));
    final todays = _on(idx, today);
    if (todays.isEmpty) {
      lines.add('오늘은 일정이 없어');
    } else {
      for (final i in todays) {
        lines.add(_line(i, today));
      }
    }
    for (var d = 1; d <= _agendaDays && lines.length < _maxLines; d++) {
      final day = DateTime(today.year, today.month, today.day + d);
      final items = _on(idx, day);
      if (items.isEmpty) continue;
      lines.add('${day.month}/${day.day} (${_wdKo[day.weekday - 1]})');
      for (final i in items) {
        lines.add(_line(i, day));
      }
    }
    return lines.take(_maxLines).join('\n');
  }

  /// 목록형 위젯용 JSON: 오늘부터 1년치([_jsonDays]일), 일정/할 일이 있거나 공휴일인 날만. 위젯에서 아래로 계속 스크롤한다.
  /// [{date, label, kind(today|holiday|sun|sat|day), note, items:[{t, todo, done, time, place, cat, color, rep, priv}]}]
  static String agendaJson(
    List<Item> visible,
    DateTime today, {
    int Function(Item)? colorOf,
    String Function(Item)? categoryName,
    List<String> Function(DateTime)? holidaysOn,
    String spaceId = '',
    Map<int, List<Item>>? index,
  }) {
    final idx = index ??
        dayIndex(visible, DateTime(today.year, today.month, today.day - _pastDays), DateTime(today.year, today.month, today.day + _jsonDays));
    final days = <Map<String, dynamic>>[];
    var count = 0;
    var pastCount = 0;
    // 지난 [_pastDays]일부터 담는다 (위젯은 오늘 위치에서 시작하고, 위로 올리면 지난 날을 볼 수 있다)
    for (var d = -_pastDays; d < _jsonDays && count < _jsonMaxItems; d++) {
      final day = DateTime(today.year, today.month, today.day + d);
      final items = _on(idx, day);
      final holidays = holidaysOn?.call(day) ?? const <String>[];
      if (items.isEmpty && holidays.isEmpty && d != 0) continue;
      final kind = d == 0
          ? 'today'
          : (holidays.isNotEmpty || day.weekday == DateTime.sunday)
              ? 'holiday'
              : day.weekday == DateTime.saturday
                  ? 'sat'
                  : 'day';
      final label = d == 0 ? '오늘 · ${_koDay(day)}' : _koDay(day);
      final list = <Map<String, dynamic>>[];
      for (final i in items) {
        if (d < 0) {
          if (pastCount >= _jsonMaxPast) break;
          pastCount++;
        } else {
          if (count >= _jsonMaxItems) break;
          count++;
        }
        list.add({
          'id': i.id,
          'sp': spaceId,
          'dk': dateKey(day),
          // 위젯에서 바로 완료 체크할 수 있나: 할 일이고, 남은 체크리스트가 없어야 함 (있으면 앱에서 확인)
          'can': i.type == ItemType.todo && i.id.isNotEmpty && spaceId.isNotEmpty && i.checksLeftOn(day) == 0,
          't': i.title,
          'todo': i.type == ItemType.todo,
          'roll': i.isRolling, // 이동형은 완료하면 다음 날짜로 넘어가서 위젯에서 되돌릴 수 없다
          'done': isDoneOn(i, day),
          'time': timeLabel(i) ?? '',
          'place': i.location,
          'cat': categoryName?.call(i) ?? '',
          'color': colorOf?.call(i) ?? 0xFF4A7BD9,
          'rep': i.isRecurring ? (i.effectiveRule?.describe(i.start) ?? '') : '',
          'priv': i.visibility == Visibility.private,
        });
      }
      // date: 위젯이 자정 뒤에 지난 날을 빼는 데 쓴다
      days.add({'date': dateKey(day), 'label': label, 'kind': kind, 'note': holidays.take(2).join(' '), 'items': list});
    }
    return jsonEncode(days);
  }

  /// 달력형 위젯용: 24개월 전부터 1년 뒤까지(위젯에서 달을 넘겨 볼 수 있게) 일정/할 일이 있는 날
  static String eventDays(List<Item> visible, DateTime today, {Map<int, List<Item>>? index}) {
    final start = DateTime(today.year, today.month - 24, 1);
    final end = DateTime(today.year, today.month + 13, 0);
    final idx = index ?? dayIndex(visible, start, end);
    final out = <String>[];
    for (var d = start; !d.isAfter(end); d = DateTime(d.year, d.month, d.day + 1)) {
      if (_on(idx, d).isNotEmpty) out.add('${d.year}${_two(d.month)}${_two(d.day)}');
    }
    return out.join(',');
  }

  /// 달력형 위젯의 칸 내용: {yyyyMMdd: {n: 그날 항목 수, e: [{t: 제목, c: 색}] (앞의 2개)}}. 항목이 있는 날만.
  /// 일정이 있는 날 표시(점)도 이 키로 만든다.
  static Map<String, dynamic> calendarCells(List<Item> visible, DateTime today,
      {int Function(Item)? colorOf, List<String> Function(DateTime)? holidaysOn, Map<int, List<Item>>? index}) {
    final start = DateTime(today.year, today.month - 24, 1);
    final end = DateTime(today.year, today.month + 13, 0);
    final idx = index ?? dayIndex(visible, start, end);
    final out = <String, dynamic>{};
    String two(int v) => v.toString().padLeft(2, '0');
    for (var d = start; !d.isAfter(end); d = DateTime(d.year, d.month, d.day + 1)) {
      final items = _on(idx, d);
      final hol = holidaysOn?.call(d) ?? const <String>[];
      if (items.isEmpty && hol.isEmpty) continue;
      out['${d.year}${two(d.month)}${two(d.day)}'] = {
        'n': items.length,
        if (hol.isNotEmpty) 'h': hol.first, // 공휴일/명절 이름 (칸에 빨간 숫자 + 첫 칩)
        'e': [
          for (final i in items.take(2))
            {'t': i.title.length > 10 ? i.title.substring(0, 10) : i.title, 'c': colorOf?.call(i) ?? 0xFF4A7BD9},
        ],
      };
    }
    return out;
  }

  /// 목록형 위젯 데이터에서 항목 하나의 완료 표시만 바로 고쳐서 위젯을 다시 그리게 한다 (앱/위젯에서 체크한 직후 즉시 반영).
  /// 전체 계산은 뒤따라 오는 일반 갱신이 맞춰 준다. 이동형 할 일은 완료하면 다음 날짜로 넘어가므로 누른 결과([done])를 그대로 쓴다.
  static Future<void> patchDone(String id, String dateKey, bool done) async {
    if (kIsWeb || id.isEmpty) return;
    try {
      final raw = await HomeWidget.getWidgetData<String>('agendaJson');
      if (raw == null) return;
      final days = jsonDecode(raw) as List;
      var hit = false;
      for (final d in days) {
        for (final it in (d['items'] as List)) {
          if (it['id'] == id && it['dk'] == dateKey) {
            it['done'] = done;
            hit = true;
          }
        }
      }
      if (!hit) return;
      await HomeWidget.saveWidgetData<String>('agendaJson', jsonEncode(days));
      await HomeWidget.updateWidget(androidName: _provider);
    } catch (_) {}
  }

  static String _lastSig = '';

  // 계산은 시간이 걸리므로 겹쳐 돌리지 않는다: 도는 중에 새 요청이 오면 끝난 뒤 최신 것으로 한 번만 다시 한다
  static bool _busy = false;
  static Future<void> Function()? _queued;
  static bool _queuedForce = false;

  static Future<void> push(
    List<Item> visible,
    String myUid, {
    int Function(Item)? colorOf,
    String Function(Item)? categoryName,
    List<String> Function(DateTime)? holidaysOn,
    List<CustomDay>? customDays, // 주면 계산을 별도 격리(isolate)에서 한다: 화면이 멈추지 않는다 (holidaysOn 대신 쓴다)
    String spaceId = '',
    bool force = false, // true면 내용이 그대로여도 위젯을 다시 그리게 한다 (앱을 켜고 끌 때)
  }) async {
    if (kIsWeb) return;
    if (_busy) {
      // 최신 요청만 남기되, 앞선 요청이 force 였다면 그 의미는 이어 간다
      final f = force || _queuedForce;
      _queuedForce = f;
      _queued = () => _push(visible, colorOf, categoryName, holidaysOn, customDays, spaceId, f);
      return;
    }
    _busy = true;
    try {
      await _push(visible, colorOf, categoryName, holidaysOn, customDays, spaceId, force);
      while (_queued != null) {
        final next = _queued!;
        _queued = null;
        _queuedForce = false;
        await next();
      }
    } finally {
      _busy = false;
    }
  }

  static Future<void> _push(
    List<Item> visible,
    int Function(Item)? colorOf,
    String Function(Item)? categoryName,
    List<String> Function(DateTime)? holidaysOn,
    List<CustomDay>? customDays,
    String spaceId,
    bool force,
  ) async {
    final today = dateOnly(DateTime.now());
    try {
      final WidgetPayload p;
      if (customDays != null) {
        final input = WidgetPayloadInput(
          visible: visible,
          today: today,
          spaceId: spaceId,
          colors: {for (final i in visible) i.id: colorOf?.call(i) ?? 0xFF4A7BD9},
          categories: {for (final i in visible) i.id: categoryName?.call(i) ?? ''},
          customDays: customDays,
        );
        p = await compute(buildWidgetPayload, input);
      } else {
        p = buildWidgetPayload(WidgetPayloadInput(
          visible: visible,
          today: today,
          spaceId: spaceId,
          colors: {for (final i in visible) i.id: colorOf?.call(i) ?? 0xFF4A7BD9},
          categories: {for (final i in visible) i.id: categoryName?.call(i) ?? ''},
          customDays: const [],
          holidaysOn: holidaysOn,
        ));
      }
      // 내용이 그대로면 위젯을 다시 그리게 하지 않는다
      final sig = '${p.agenda.hashCode}/${p.cellsJson.hashCode}/${today.day}';
      if (!force && sig == _lastSig) return;
      _lastSig = sig;
      await HomeWidget.saveWidgetData<String>('title', _koDay(today));
      await HomeWidget.saveWidgetData<String>('body', p.body);
      await HomeWidget.saveWidgetData<String>('agendaJson', p.agenda);
      // 앞으로 24시간 안에 출발 알림 일정이 있으면 안드로이드가 15분마다 위치를 서버에 남긴다 (없으면 아무것도 안 함)
      final now = DateTime.now();
      final watch = visible.any((i) {
        final f = i.departFrom;
        return f != null && f.isAfter(now) && f.difference(now) <= const Duration(hours: 24);
      });
      await HomeWidget.saveWidgetData<bool>('departWatch', watch);
      await HomeWidget.saveWidgetData<String>('eventDays', p.days);
      await HomeWidget.saveWidgetData<String>('calCells', p.cellsJson);
      await HomeWidget.updateWidget(androidName: _provider);
    } catch (_) {
      // 위젯 갱신 실패는 앱 동작에 영향 없음
    }
  }
}

/// 위젯 데이터 계산 입력 (격리로 보낼 수 있게 함수/클로저 없이 값만 담는다)
class WidgetPayloadInput {
  final List<Item> visible;
  final DateTime today;
  final String spaceId;
  final Map<String, int> colors; // 항목 id -> 색
  final Map<String, String> categories; // 항목 id -> 대표 카테고리 이름
  final List<CustomDay> customDays;
  final List<String> Function(DateTime)? holidaysOn; // 격리 없이 계산할 때만 (테스트/미리보기)
  const WidgetPayloadInput({
    required this.visible,
    required this.today,
    required this.spaceId,
    required this.colors,
    required this.categories,
    required this.customDays,
    this.holidaysOn,
  });
}

class WidgetPayload {
  final String agenda; // 목록형 JSON
  final String body; // 목록형 글자
  final String cellsJson; // 달력형 칸 내용 JSON
  final String days; // 일정 있는 날(yyyyMMdd, 쉼표)
  const WidgetPayload(this.agenda, this.body, this.cellsJson, this.days);
}

/// 위젯에 보낼 데이터를 한꺼번에 계산한다. 날짜별 항목 표를 한 번만 만들어 세 가지가 같이 쓴다. (격리에서 돌 수 있는 최상위 함수)
WidgetPayload buildWidgetPayload(WidgetPayloadInput p) {
  final cal = p.holidaysOn == null ? KrCalendar(custom: p.customDays) : null;
  List<String> holidays(DateTime d) =>
      p.holidaysOn != null ? p.holidaysOn!(d) : [for (final m in cal!.marksOn(d)) if (m.isHoliday) m.name];
  int colorOf(Item i) => p.colors[i.id] ?? 0xFF4A7BD9;
  final (from, to) = WidgetSync.rangeFor(p.today);
  final idx = WidgetSync.dayIndex(p.visible, from, to);
  final agenda = WidgetSync.agendaJson(p.visible, p.today,
      index: idx, colorOf: colorOf, categoryName: (i) => p.categories[i.id] ?? '', holidaysOn: holidays, spaceId: p.spaceId);
  final cells = WidgetSync.calendarCells(p.visible, p.today, index: idx, colorOf: colorOf, holidaysOn: holidays);
  // 일정 있는 날 표시(점)는 공휴일만 있는 날을 뺀다
  final days = [for (final e in cells.entries) if (((e.value as Map)['n'] as int) > 0) e.key].join(',');
  return WidgetPayload(agenda, WidgetSync.agendaText(p.visible, p.today, index: idx), jsonEncode(cells), days);
}

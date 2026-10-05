import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

import '../models/item.dart';

/// 안드로이드 홈화면 위젯에 일정/할 일을 밀어 넣는다.
/// 네이티브 쪽은 android/.../OurDayWidget.kt 가 SharedPreferences에서 읽는다.
///  - body: 목록형 위젯에 보일 앞으로 며칠치 일정/할 일 (글자)
///  - eventDays: 달력형 위젯에 표시할 "일정이 있는 날" (yyyyMMdd를 쉼표로)
class WidgetSync {
  static const _provider = 'OurDayWidget';
  static const _agendaDays = 7;
  static const _pastDays = 14;
  static const _maxLines = 10;
  static const _jsonDays = 366;
  static const _jsonMaxItems = 600;

  static String _line(Item i, DateTime day) {
    final t = timeLabel(i);
    final title = t == null ? i.title : '$t ${i.title}';
    if (i.type == ItemType.todo) return '${isDoneOn(i, day) ? '☑' : '☐'} $title';
    return '• $title';
  }

  static List<Item> _on(List<Item> visible, DateTime day) => visible.where((i) => occursOn(i, day)).toList()
    ..sort((a, b) {
      if (a.type != b.type) return a.type == ItemType.event ? -1 : 1;
      return a.start.compareTo(b.start);
    });

  /// 목록형 위젯 글자: 오늘 + 앞으로 며칠 (날짜 머리글 포함, 최대 [_maxLines]줄)
  static String agendaText(List<Item> visible, DateTime today) {
    final lines = <String>[];
    final df = DateFormat('M/d (E)', 'ko');
    final todays = _on(visible, today);
    if (todays.isEmpty) {
      lines.add('오늘은 일정이 없어');
    } else {
      for (final i in todays) {
        lines.add(_line(i, today));
      }
    }
    for (var d = 1; d <= _agendaDays && lines.length < _maxLines; d++) {
      final day = DateTime(today.year, today.month, today.day + d);
      final items = _on(visible, day);
      if (items.isEmpty) continue;
      lines.add(df.format(day));
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
  }) {
    final df = DateFormat('M월 d일 (E)', 'ko');
    final days = <Map<String, dynamic>>[];
    var count = 0;
    // 지난 [_pastDays]일부터 담는다 (위젯은 오늘 위치에서 시작하고, 위로 올리면 지난 날을 볼 수 있다)
    for (var d = -_pastDays; d < _jsonDays && count < _jsonMaxItems; d++) {
      final day = DateTime(today.year, today.month, today.day + d);
      final items = _on(visible, day);
      final holidays = holidaysOn?.call(day) ?? const <String>[];
      if (items.isEmpty && holidays.isEmpty && d != 0) continue;
      final kind = d == 0
          ? 'today'
          : (holidays.isNotEmpty || day.weekday == DateTime.sunday)
              ? 'holiday'
              : day.weekday == DateTime.saturday
                  ? 'sat'
                  : 'day';
      final label = d == 0 ? '오늘 · ${df.format(day)}' : df.format(day);
      final list = <Map<String, dynamic>>[];
      for (final i in items) {
        if (count >= _jsonMaxItems) break;
        count++;
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

  /// 달력형 위젯용: 6개월 전부터 1년 뒤까지(위젯에서 달을 넘겨 볼 수 있게) 일정/할 일이 있는 날
  static String eventDays(List<Item> visible, DateTime today) {
    final start = DateTime(today.year, today.month - 6, 1);
    final end = DateTime(today.year, today.month + 13, 0);
    final f = DateFormat('yyyyMMdd');
    final out = <String>[];
    for (var d = start; !d.isAfter(end); d = DateTime(d.year, d.month, d.day + 1)) {
      if (visible.any((i) => occursOn(i, d))) out.add(f.format(d));
    }
    return out.join(',');
  }

  static String _lastSig = '';

  static Future<void> push(
    List<Item> visible,
    String myUid, {
    int Function(Item)? colorOf,
    String Function(Item)? categoryName,
    List<String> Function(DateTime)? holidaysOn,
    String spaceId = '',
  }) async {
    if (kIsWeb) return;
    final today = dateOnly(DateTime.now());
    try {
      final agenda = agendaJson(visible, today,
          colorOf: colorOf, categoryName: categoryName, holidaysOn: holidaysOn, spaceId: spaceId);
      await Future<void>.delayed(const Duration(milliseconds: 20)); // 무거운 계산 사이에 화면이 한 프레임 그릴 틈을 준다
      final days = eventDays(visible, today);
      // 내용이 그대로면 위젯을 다시 그리게 하지 않는다
      final sig = '${agenda.hashCode}/${days.hashCode}/${today.day}';
      if (sig == _lastSig) return;
      _lastSig = sig;
      await HomeWidget.saveWidgetData<String>('title', DateFormat('M월 d일 (E)', 'ko').format(today));
      await HomeWidget.saveWidgetData<String>('body', agendaText(visible, today));
      await HomeWidget.saveWidgetData<String>('agendaJson', agenda);
      // 앞으로 24시간 안에 출발 알림 일정이 있으면 안드로이드가 15분마다 위치를 서버에 남긴다 (없으면 아무것도 안 함)
      final now = DateTime.now();
      final watch = visible.any((i) {
        final f = i.departFrom;
        return f != null && f.isAfter(now) && f.difference(now) <= const Duration(hours: 24);
      });
      await HomeWidget.saveWidgetData<bool>('departWatch', watch);
      await HomeWidget.saveWidgetData<String>('eventDays', days);
      await HomeWidget.updateWidget(androidName: _provider);
    } catch (_) {
      // 위젯 갱신 실패는 앱 동작에 영향 없음
    }
  }
}

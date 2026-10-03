import 'item.dart';
import 'recurrence.dart';

/// iCalendar(.ics) 가져오기: 구글 캘린더 내보내기 파일을 읽어 일정으로 바꾼다.

class IcsEvent {
  final String uid;
  final String title;
  final String note;
  final String location;
  final DateTime start;
  final DateTime? end; // 종일이면 마지막 날(포함), 시각 일정이면 종료 시각
  final bool allDay;
  final String? rrule;
  final List<DateTime> exdates;
  final DateTime? recurrenceId;
  final bool cancelled;
  const IcsEvent({
    required this.uid,
    required this.title,
    required this.start,
    this.note = '',
    this.location = '',
    this.end,
    this.allDay = true,
    this.rrule,
    this.exdates = const [],
    this.recurrenceId,
    this.cancelled = false,
  });
}

class IcsCalendar {
  final String name;
  final List<IcsEvent> events;
  const IcsCalendar(this.name, this.events);
}

/// 줄 이어붙이기(접힌 줄 펼치기)
List<String> _unfold(String text) {
  final out = <String>[];
  for (final raw in text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n')) {
    if ((raw.startsWith(' ') || raw.startsWith('\t')) && out.isNotEmpty) {
      out[out.length - 1] += raw.substring(1);
    } else {
      out.add(raw);
    }
  }
  return out;
}

String _unescape(String v) => v
    .replaceAll(r'\n', '\n')
    .replaceAll(r'\N', '\n')
    .replaceAll(r'\,', ',')
    .replaceAll(r'\;', ';')
    .replaceAll(r'\\', r'\');

class _Prop {
  final String name;
  final Map<String, String> params;
  final String value;
  _Prop(this.name, this.params, this.value);
}

_Prop? _parseLine(String line) {
  final colon = line.indexOf(':');
  if (colon <= 0) return null;
  final head = line.substring(0, colon).split(';');
  final params = <String, String>{};
  for (final p in head.skip(1)) {
    final eq = p.indexOf('=');
    if (eq > 0) params[p.substring(0, eq).toUpperCase()] = p.substring(eq + 1);
  }
  return _Prop(head.first.toUpperCase(), params, line.substring(colon + 1));
}

/// DATE(YYYYMMDD) 또는 DATE-TIME(YYYYMMDDTHHMMSS[Z]). Z는 UTC로 보고 기기 시간대로 바꾼다.
({DateTime value, bool dateOnly})? parseIcsDate(String v) {
  final s = v.trim();
  final m = RegExp(r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})?(Z)?)?$').firstMatch(s);
  if (m == null) return null;
  final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
  if (m[4] == null) return (value: DateTime(y, mo, d), dateOnly: true);
  final h = int.parse(m[4]!), mi = int.parse(m[5]!), se = int.parse(m[6] ?? '0');
  if (m[7] == 'Z') return (value: DateTime.utc(y, mo, d, h, mi, se).toLocal(), dateOnly: false);
  return (value: DateTime(y, mo, d, h, mi, se), dateOnly: false);
}

/// .ics 텍스트 하나를 읽는다. 일정(VEVENT)만 가져오고 할 일 등은 무시.
IcsCalendar parseIcs(String text, {String fallbackName = '캘린더'}) {
  var name = fallbackName;
  final events = <IcsEvent>[];
  Map<String, List<_Prop>>? cur;
  for (final line in _unfold(text)) {
    final p = _parseLine(line);
    if (line.trim() == 'BEGIN:VEVENT') {
      cur = {};
      continue;
    }
    if (line.trim() == 'END:VEVENT') {
      final e = cur == null ? null : _toEvent(cur);
      if (e != null) events.add(e);
      cur = null;
      continue;
    }
    if (p == null) continue;
    if (cur != null) {
      (cur[p.name] ??= []).add(p);
    } else if (p.name == 'X-WR-CALNAME' && p.value.trim().isNotEmpty) {
      name = _unescape(p.value.trim());
    }
  }
  return IcsCalendar(name, events);
}

IcsEvent? _toEvent(Map<String, List<_Prop>> m) {
  String? one(String k) => m[k]?.first.value;
  final ds = m['DTSTART']?.first;
  if (ds == null) return null;
  final start = parseIcsDate(ds.value);
  if (start == null) return null;
  final allDay = start.dateOnly;
  DateTime? end;
  final de = m['DTEND']?.first;
  if (de != null) {
    final e = parseIcsDate(de.value);
    if (e != null) {
      // 종일 일정의 DTEND는 마지막 날의 다음 날(미포함)
      end = allDay ? DateTime(e.value.year, e.value.month, e.value.day - 1) : e.value;
    }
  } else if (m['DURATION'] != null && !allDay) {
    final d = RegExp(r'^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?)?$').firstMatch(one('DURATION')!);
    if (d != null) {
      end = start.value.add(Duration(
          days: int.tryParse(d[1] ?? '') ?? 0, hours: int.tryParse(d[2] ?? '') ?? 0, minutes: int.tryParse(d[3] ?? '') ?? 0));
    }
  }
  if (allDay && end != null && !end.isAfter(start.value)) end = null;
  final ex = <DateTime>[];
  for (final p in m['EXDATE'] ?? const <_Prop>[]) {
    for (final v in p.value.split(',')) {
      final d = parseIcsDate(v);
      if (d != null) ex.add(d.value);
    }
  }
  final rid = m['RECURRENCE-ID']?.first;
  return IcsEvent(
    uid: one('UID') ?? '',
    title: _unescape(one('SUMMARY') ?? '').trim().isEmpty ? '(제목 없음)' : _unescape(one('SUMMARY')!).trim(),
    note: _unescape(one('DESCRIPTION') ?? '').trim(),
    location: _unescape(one('LOCATION') ?? '').trim(),
    start: start.value,
    end: end,
    allDay: allDay,
    rrule: one('RRULE'),
    exdates: ex,
    recurrenceId: rid == null ? null : parseIcsDate(rid.value)?.value,
    cancelled: (one('STATUS') ?? '').toUpperCase() == 'CANCELLED',
  );
}

const _wd = {'MO': 1, 'TU': 2, 'WE': 3, 'TH': 4, 'FR': 5, 'SA': 6, 'SU': 7};

/// RRULE → 우리 반복 규칙. 표현할 수 없는 조합이면 [simplified]가 true이고 가장 가까운 단순 규칙(또는 null=반복 없음)을 돌려준다.
({Recurrence? rule, bool simplified}) rruleToRecurrence(String rrule, DateTime start) {
  final p = <String, String>{};
  for (final kv in rrule.split(';')) {
    final eq = kv.indexOf('=');
    if (eq > 0) p[kv.substring(0, eq).toUpperCase()] = kv.substring(eq + 1);
  }
  final freq = switch (p['FREQ']) {
    'DAILY' => Freq.daily,
    'WEEKLY' => Freq.weekly,
    'MONTHLY' => Freq.monthly,
    'YEARLY' => Freq.yearly,
    _ => null,
  };
  if (freq == null) return (rule: null, simplified: true);
  var simplified = false;
  final interval = (int.tryParse(p['INTERVAL'] ?? '') ?? 1).clamp(1, 999);
  DateTime? until;
  if (p['UNTIL'] != null) {
    final u = parseIcsDate(p['UNTIL']!);
    if (u != null) until = DateTime(u.value.year, u.value.month, u.value.day);
  }
  final count = int.tryParse(p['COUNT'] ?? '');
  const unsupported = ['BYSETPOS', 'BYYEARDAY', 'BYWEEKNO', 'BYHOUR', 'BYMINUTE', 'BYSECOND'];
  if (unsupported.any(p.containsKey)) simplified = true;

  final byday = (p['BYDAY'] ?? '').split(',').where((e) => e.isNotEmpty).toList();
  final bymonthday = (p['BYMONTHDAY'] ?? '').split(',').map(int.tryParse).whereType<int>().toList();

  switch (freq) {
    case Freq.daily:
      return (rule: Recurrence(freq: freq, interval: interval, until: until, count: count), simplified: simplified);
    case Freq.weekly:
      final days = <int>[];
      for (final d in byday) {
        final w = _wd[d.replaceAll(RegExp(r'[+\-0-9]'), '')];
        if (w != null) days.add(w);
      }
      return (
        rule: Recurrence(freq: freq, interval: interval, weekdays: days..sort(), until: until, count: count),
        simplified: simplified,
      );
    case Freq.monthly:
      // 요일 기준: 둘째 금요일(2FR), 마지막 월요일(-1MO)
      if (byday.length == 1 && RegExp(r'^[+-]?\d').hasMatch(byday.first)) {
        final m = RegExp(r'^([+-]?\d+)([A-Z]{2})$').firstMatch(byday.first);
        final n = int.tryParse(m?[1] ?? '');
        final w = _wd[m?[2] ?? ''];
        if (n != null && w != null && (n == -1 || (n >= 1 && n <= 4))) {
          return (
            rule: Recurrence(freq: freq, interval: interval, nth: n, nthWeekday: w, until: until, count: count),
            simplified: simplified,
          );
        }
        simplified = true;
      } else if (byday.isNotEmpty) {
        simplified = true; // "매월 모든 월요일" 같은 건 지원 안 함
      }
      return (
        rule: Recurrence(
            freq: freq,
            interval: interval,
            monthDays: bymonthday.where((d) => d == -1 || (d >= 1 && d <= 31)).toList()..sort(),
            until: until,
            count: count),
        simplified: simplified,
      );
    case Freq.yearly:
      if (p.containsKey('BYMONTH') && int.tryParse(p['BYMONTH']!) != start.month) simplified = true;
      if (bymonthday.isNotEmpty && !(bymonthday.length == 1 && bymonthday.first == start.day)) simplified = true;
      if (byday.isNotEmpty) simplified = true;
      return (rule: Recurrence(freq: freq, interval: interval, until: until, count: count), simplified: simplified);
  }
}

class ImportResult {
  final List<Item> items;
  final int simplified; // 반복이 단순해진 일정 수
  final int skippedCancelled;
  const ImportResult(this.items, this.simplified, this.skippedCancelled);
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
String _key(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 가져온 일정들을 Item으로. [ownerUid]/[visibility]/[categoryId]는 가져오기 때 정한 값.
ImportResult icsToItems(List<IcsEvent> events,
    {required String ownerUid, required Visibility visibility, required String categoryId}) {
  final items = <Item>[];
  var simplified = 0, cancelled = 0;
  // 반복 일정 중 "이 날짜만 변경"된 회차(RECURRENCE-ID)는 원본에서 빼고 따로 가져온다
  final overrides = <String, List<DateTime>>{};
  for (final e in events) {
    if (e.recurrenceId != null) (overrides[e.uid] ??= []).add(e.recurrenceId!);
  }
  for (final e in events) {
    if (e.cancelled) {
      cancelled++;
      continue;
    }
    Recurrence? rule;
    if (e.rrule != null && e.recurrenceId == null) {
      final r = rruleToRecurrence(e.rrule!, e.start);
      rule = r.rule;
      if (r.simplified) simplified++;
    }
    final exceptions = <String>{
      for (final d in e.exdates) _key(_day(d)),
      if (rule != null) for (final d in overrides[e.uid] ?? const <DateTime>[]) _key(_day(d)),
    };
    DateTime? end = e.end;
    if (rule != null && !e.allDay && end != null) {
      // 반복 일정은 첫 회차 날짜에 종료 시각만 둔다 (등록 화면과 같은 방식)
      end = DateTime(e.start.year, e.start.month, e.start.day, end.hour, end.minute);
    }
    if (e.allDay && rule != null) end = null;
    items.add(Item(
      id: '',
      type: ItemType.event,
      title: e.title,
      note: e.note,
      location: e.location,
      start: e.start,
      end: end,
      allDay: e.allDay,
      categories: [categoryId],
      visibility: visibility,
      ownerUid: ownerUid,
      repeat: repeatFor(rule),
      rule: rule,
      exceptions: exceptions.toList()..sort(),
    ));
  }
  return ImportResult(items, simplified, cancelled);
}

import 'dart:convert';

import 'item.dart';
import 'recurrence.dart';

/// 일정/할 일을 iCalendar(.ics) 텍스트로 내보낸다 (백업, 다른 캘린더로 옮기기용).
/// 음력 반복은 .ics 표준에 없어서 첫 날짜 하나만 내보낸다.

String _two(int n) => n.toString().padLeft(2, '0');
String _date(DateTime d) => '${d.year}${_two(d.month)}${_two(d.day)}';
String _utc(DateTime d) {
  final u = d.toUtc();
  return '${_date(u)}T${_two(u.hour)}${_two(u.minute)}${_two(u.second)}Z';
}

String _esc(String s) =>
    s.replaceAll(r'\', r'\\').replaceAll(';', r'\;').replaceAll(',', r'\,').replaceAll('\r\n', r'\n').replaceAll('\n', r'\n');

/// 75바이트(UTF-8)를 넘는 줄은 접는다.
String _fold(String line) {
  if (utf8.encode(line).length <= 75) return line;
  final out = StringBuffer();
  var bytes = 0;
  var first = true;
  for (final r in line.runes) {
    final ch = String.fromCharCode(r);
    final n = utf8.encode(ch).length;
    if (bytes + n > (first ? 75 : 74)) {
      out.write('\r\n ');
      bytes = 0;
      first = false;
    }
    out.write(ch);
    bytes += n;
  }
  return out.toString();
}

const _wd = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];

/// 반복 규칙 → RRULE 값. 표현 못 하면(음력) null.
String? rruleOf(Recurrence r) {
  if (r.lunar) return null;
  final p = <String>[
    'FREQ=${switch (r.freq) { Freq.daily => 'DAILY', Freq.weekly => 'WEEKLY', Freq.monthly => 'MONTHLY', Freq.yearly => 'YEARLY' }}',
  ];
  if (r.interval > 1) p.add('INTERVAL=${r.interval}');
  if (r.freq == Freq.weekly && r.weekdays.isNotEmpty) {
    p.add('BYDAY=${(List<int>.of(r.weekdays)..sort()).map((d) => _wd[d - 1]).join(',')}');
  }
  if (r.freq == Freq.monthly) {
    if (r.nth != null && r.nthWeekday != null) {
      p.add('BYDAY=${r.nth}${_wd[r.nthWeekday! - 1]}');
    } else if (r.monthDays.isNotEmpty) {
      p.add('BYMONTHDAY=${r.monthDays.join(',')}');
    }
  }
  if (r.until != null) p.add('UNTIL=${_date(r.until!)}');
  if (r.count != null) p.add('COUNT=${r.count}');
  return p.join(';');
}

String exportIcs(List<Item> items, {String calendarName = '순대희 캘린더', DateTime? now}) {
  final stamp = _utc(now ?? DateTime.now());
  final l = <String>[
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//soondaehui//calendar//KO',
    'CALSCALE:GREGORIAN',
    'X-WR-CALNAME:${_esc(calendarName)}',
  ];
  for (final i in items) {
    final rule = i.effectiveRule;
    final isTodo = i.type == ItemType.todo;
    l.add(isTodo ? 'BEGIN:VTODO' : 'BEGIN:VEVENT');
    l.add('UID:${i.id.isEmpty ? i.hashCode : i.id}@soondaehui');
    l.add('DTSTAMP:$stamp');
    final startKey = isTodo ? 'DUE' : 'DTSTART';
    if (i.allDay) {
      l.add('$startKey;VALUE=DATE:${_date(i.start)}');
      if (!isTodo) {
        final last = i.end != null ? DateTime(i.end!.year, i.end!.month, i.end!.day) : DateTime(i.start.year, i.start.month, i.start.day);
        l.add('DTEND;VALUE=DATE:${_date(DateTime(last.year, last.month, last.day + 1))}'); // 종일의 DTEND는 다음 날
      }
    } else {
      l.add('$startKey:${_utc(i.start)}');
      if (!isTodo && i.end != null) l.add('DTEND:${_utc(i.end!)}');
    }
    l.add('SUMMARY:${_esc(i.title)}');
    if (i.location.isNotEmpty) l.add('LOCATION:${_esc(i.location)}');
    final desc = [
      if (i.note.isNotEmpty) i.note,
      if (i.checklist.isNotEmpty) i.checklist.map((c) => '${c.done ? '[x]' : '[ ]'} ${c.text}').join('\n'),
    ].join('\n');
    if (desc.isNotEmpty) l.add('DESCRIPTION:${_esc(desc)}');
    if (rule != null) {
      final rr = rruleOf(rule);
      if (rr != null) l.add('RRULE:$rr');
      for (final e in i.exceptions) {
        l.add(i.allDay ? 'EXDATE;VALUE=DATE:${e.replaceAll('-', '')}' : 'EXDATE:${e.replaceAll('-', '')}T${_two(i.start.toUtc().hour)}${_two(i.start.toUtc().minute)}00Z');
      }
    }
    if (isTodo) l.add('STATUS:${i.done ? 'COMPLETED' : 'NEEDS-ACTION'}');
    l.add(isTodo ? 'END:VTODO' : 'END:VEVENT');
  }
  l.add('END:VCALENDAR');
  return '${l.map(_fold).join('\r\n')}\r\n';
}

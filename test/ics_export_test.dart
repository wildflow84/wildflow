import 'package:flutter_test/flutter_test.dart';
import 'package:ourday/models/ics.dart';
import 'package:ourday/models/ics_export.dart';
import 'package:ourday/models/item.dart';
import 'package:ourday/models/recurrence.dart';

void main() {
  final items = [
    Item(
        id: 'a', type: ItemType.event, title: '오키나와 여행, 가족', start: DateTime(2026, 10, 14), end: DateTime(2026, 10, 17),
        ownerUid: 'me', location: '오키나와; 일본', note: '항공권\n호텔'),
    Item(
        id: 'b', type: ItemType.event, title: '운동', start: DateTime(2026, 10, 5, 19), end: DateTime(2026, 10, 5, 20, 30),
        allDay: false, ownerUid: 'me', rule: const Recurrence(freq: Freq.weekly, weekdays: [1, 3], until: null, count: 10),
        exceptions: const ['2026-10-12']),
    Item(
        id: 'c', type: ItemType.event, title: '둘째 금요일 모임', start: DateTime(2026, 10, 9), ownerUid: 'me',
        rule: const Recurrence(freq: Freq.monthly, nth: 2, nthWeekday: 5)),
    Item(
        id: 'd', type: ItemType.event, title: '엄마 생신(음력)', start: DateTime(2026, 6, 29), ownerUid: 'me',
        rule: const Recurrence(freq: Freq.yearly, lunar: true)),
    Item(id: 'e', type: ItemType.todo, title: '장보기', start: DateTime(2026, 10, 3), ownerUid: 'me', done: true,
        checklist: const [CheckEntry('우유', done: true), CheckEntry('계란')]),
  ];

  test('내보내기 → 다시 가져오기: 제목/날짜/반복/예외가 그대로', () {
    final text = exportIcs(items, now: DateTime.utc(2026, 10, 3));
    expect(text.contains('\r\n'), true);
    expect(text.split('\r\n').every((l) => l.length < 200), true);
    final cal = parseIcs(text);
    final ev = {for (final e in cal.events) e.title: e};
    expect(ev.length, 4); // 일정 4개 (할 일은 VTODO라 가져오기에서 제외)
    final trip = ev['오키나와 여행, 가족']!;
    expect(trip.allDay, true);
    expect(trip.start, DateTime(2026, 10, 14));
    expect(trip.end, DateTime(2026, 10, 17)); // 마지막 날(17일 포함)이 그대로 돌아옴
    expect(trip.location, '오키나와; 일본');
    expect(trip.note, '항공권\n호텔');
    final gym = ev['운동']!;
    expect(gym.start, DateTime(2026, 10, 5, 19));
    expect(gym.rrule, 'FREQ=WEEKLY;BYDAY=MO,WE;COUNT=10');
    expect(gym.exdates.length, 1);
    expect(ev['둘째 금요일 모임']!.rrule, 'FREQ=MONTHLY;BYDAY=2FR');
    expect(ev['엄마 생신(음력)']!.rrule, isNull); // 음력은 첫 날짜만
  });

  test('할 일은 VTODO로, 체크리스트는 설명에', () {
    final text = exportIcs(items);
    expect(text.contains('BEGIN:VTODO'), true);
    expect(text.contains('STATUS:COMPLETED'), true);
    expect(text.replaceAll('\r\n ', '').contains(r'[x] 우유\n[ ] 계란'), true);
  });

  test('긴 한글 줄도 75바이트 안에서 접힌다', () {
    final long = Item(id: 'x', type: ItemType.event, title: '가' * 80, start: DateTime(2026, 10, 3), ownerUid: 'me');
    final text = exportIcs([long]);
    for (final line in text.split('\r\n')) {
      expect(line.codeUnits.length < 200, true);
    }
    expect(parseIcs(text).events.single.title, '가' * 80);
  });
}

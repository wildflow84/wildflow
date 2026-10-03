import 'package:flutter_test/flutter_test.dart';
import 'package:ourday/models/ics.dart';
import 'package:ourday/models/item.dart';
import 'package:ourday/models/recurrence.dart';

const _sample = '''BEGIN:VCALENDAR
VERSION:2.0
X-WR-CALNAME:대희 아빠
BEGIN:VEVENT
UID:a1
DTSTART;VALUE=DATE:20261010
DTEND;VALUE=DATE:20261013
SUMMARY:오키나와 여행
LOCATION:오키나와\\, 일본
DESCRIPTION:항공권 확인\\n호텔 예약
END:VEVENT
BEGIN:VEVENT
UID:a2
DTSTART;TZID=Asia/Seoul:20261005T190000
DTEND;TZID=Asia/Seoul:20261005T203000
RRULE:FREQ=WEEKLY;BYDAY=MO,WE;UNTIL=20261231T145959Z
EXDATE;TZID=Asia/Seoul:20261012T190000
SUMMARY:운동
END:VEVENT
BEGIN:VEVENT
UID:a2
RECURRENCE-ID;TZID=Asia/Seoul:20261007T190000
DTSTART;TZID=Asia/Seoul:20261007T200000
DTEND;TZID=Asia/Seoul:20261007T213000
SUMMARY:운동 (늦게)
END:VEVENT
BEGIN:VEVENT
UID:a3
DTSTART;VALUE=DATE:20261001
DTEND;VALUE=DATE:20261002
RRULE:FREQ=MONTHLY;BYDAY=2FR
SUMMARY:둘째 금요일 모임
END:VEVENT
BEGIN:VEVENT
UID:a4
DTSTART;VALUE=DATE:20261001
RRULE:FREQ=MONTHLY;BYDAY=MO
SUMMARY:매월 모든 월요일
END:VEVENT
BEGIN:VEVENT
UID:a5
DTSTART;VALUE=DATE:20261020
STATUS:CANCELLED
SUMMARY:취소됨
END:VEVENT
BEGIN:VEVENT
UID:a6
DTSTART:20261020T010000Z
DURATION:PT1H30M
SUMMARY:UTC 일정 with a long
 folded line
END:VEVENT
END:VCALENDAR
''';

void main() {
  test('날짜/시각 읽기', () {
    expect(parseIcsDate('20261010')!.dateOnly, true);
    expect(parseIcsDate('20261010')!.value, DateTime(2026, 10, 10));
    expect(parseIcsDate('20261005T190000')!.value, DateTime(2026, 10, 5, 19));
    expect(parseIcsDate('20261020T010000Z')!.value, DateTime.utc(2026, 10, 20, 1).toLocal());
    expect(parseIcsDate('garbage'), isNull);
  });

  test('.ics 파싱: 이름, 종일 기간(DTEND 미포함 보정), 이스케이프, 줄 접기', () {
    final c = parseIcs(_sample);
    expect(c.name, '대희 아빠');
    expect(c.events.length, 7);
    final trip = c.events.first;
    expect(trip.allDay, true);
    expect(trip.start, DateTime(2026, 10, 10));
    expect(trip.end, DateTime(2026, 10, 12)); // 13일 미포함 → 12일까지
    expect(trip.location, '오키나와, 일본');
    expect(trip.note, '항공권 확인\n호텔 예약');
    final folded = c.events.last;
    expect(folded.title, 'UTC 일정 with a longfolded line');
    expect(folded.end, folded.start.add(const Duration(hours: 1, minutes: 30)));
  });

  test('RRULE 변환', () {
    final s = DateTime(2026, 10, 5);
    final w = rruleToRecurrence('FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE;COUNT=10', s);
    expect(w.rule!.freq, Freq.weekly);
    expect(w.rule!.interval, 2);
    expect(w.rule!.weekdays, [1, 3]);
    expect(w.rule!.count, 10);
    expect(w.simplified, false);
    final nth = rruleToRecurrence('FREQ=MONTHLY;BYDAY=-1FR', s);
    expect(nth.rule!.nth, -1);
    expect(nth.rule!.nthWeekday, 5);
    final last = rruleToRecurrence('FREQ=MONTHLY;BYMONTHDAY=-1', s);
    expect(last.rule!.monthDays, [-1]);
    expect(rruleToRecurrence('FREQ=MONTHLY;BYDAY=MO', s).simplified, true);
    expect(rruleToRecurrence('FREQ=MONTHLY;BYDAY=1MO,2MO', s).simplified, true);
    expect(rruleToRecurrence('FREQ=YEARLY;BYMONTH=3', s).simplified, true);
    expect(rruleToRecurrence('FREQ=SECONDLY', s).rule, isNull);
    final y = rruleToRecurrence('FREQ=YEARLY', s);
    expect(y.rule!.freq, Freq.yearly);
    expect(y.simplified, false);
  });

  test('Item 변환: 반복/예외/변경된 회차/취소/단순화 집계', () {
    final r = icsToItems(parseIcs(_sample).events,
        ownerUid: 'me', visibility: Visibility.shared, categoryId: 'default');
    expect(r.skippedCancelled, 1);
    expect(r.simplified, 1); // 매월 모든 월요일
    expect(r.items.length, 6);
    final gym = r.items.firstWhere((i) => i.title == '운동');
    expect(gym.rule!.weekdays, [1, 3]);
    expect(gym.rule!.until, isNotNull);
    expect(gym.allDay, false);
    expect(gym.end, DateTime(2026, 10, 5, 20, 30));
    expect(gym.exceptions, containsAll(['2026-10-12', '2026-10-07'])); // EXDATE + 변경된 회차
    final moved = r.items.firstWhere((i) => i.title == '운동 (늦게)');
    expect(moved.isRecurring, false);
    expect(moved.start, DateTime(2026, 10, 7, 20));
    final nth = r.items.firstWhere((i) => i.title == '둘째 금요일 모임');
    expect(nth.rule!.nth, 2);
    expect(occursOn(nth, DateTime(2026, 10, 9)), true); // 10월 둘째 금요일
    expect(occursOn(nth, DateTime(2026, 11, 13)), true);
    final trip = r.items.firstWhere((i) => i.title == '오키나와 여행');
    expect(trip.end, DateTime(2026, 10, 12));
    expect(trip.visibility, Visibility.shared);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:ourday/models/item.dart';
import 'package:ourday/models/lunar.dart';
import 'package:ourday/models/recurrence.dart';

void main() {
  test('D-day 문구', () {
    final today = DateTime(2026, 10, 3, 15);
    expect(ddayLabel(DateTime(2026, 10, 3), today), 'D-day');
    expect(ddayLabel(DateTime(2026, 10, 13), today), 'D-10');
    expect(ddayLabel(DateTime(2026, 10, 1), today), 'D+2');
  });

  test('매년 반복 N주년: 양력/음력', () {
    final solar = Item(
        id: 'a', type: ItemType.event, title: '결혼기념일', start: DateTime(2018, 11, 8), ownerUid: 'me',
        rule: const Recurrence(freq: Freq.yearly));
    expect(anniversaryLabel(solar, DateTime(2018, 11, 8)), isNull);
    expect(anniversaryLabel(solar, DateTime(2026, 11, 8)), '8주년');
    final start = lunarToSolar(1990, 5, 15)!;
    final lunar = Item(
        id: 'b', type: ItemType.event, title: '엄마 생신', start: start, ownerUid: 'me',
        rule: const Recurrence(freq: Freq.yearly, lunar: true));
    expect(anniversaryLabel(lunar, lunarToSolar(2026, 5, 15)!), '36주년');
    final weekly = solar.copyWith(rule: const Recurrence(freq: Freq.weekly));
    expect(anniversaryLabel(weekly, DateTime(2026, 11, 8)), isNull);
  });

  test('복제: 기록은 비우고 새 항목으로', () {
    final it = Item(
        id: 'a', type: ItemType.todo, title: '약', start: DateTime(2026, 10, 3), ownerUid: 'me',
        done: true, doneDates: const ['2026-10-01'], exceptions: const ['2026-10-02'],
        checklist: const [CheckEntry('a', done: true)], dday: true, assignee: 'you');
    final c = copyOfItem(it);
    expect(c.id, '');
    expect(c.title, '약 (복사)');
    expect(c.done, false);
    expect(c.doneDates, isEmpty);
    expect(c.exceptions, isEmpty);
    expect(c.checklist.single.done, false);
    expect(c.dday, true);
    expect(c.assignee, 'you');
  });

  test('알림 시각 계산: 시각 일정은 N분 전, 종일은 오전 9시 기준, 반복(규칙)은 없음', () {
    final timed = Item(
        id: 'a', type: ItemType.event, title: 't', start: DateTime(2026, 10, 7, 15, 0), allDay: false,
        ownerUid: 'me', remindMinutes: 30);
    expect(timed.remindAt, DateTime(2026, 10, 7, 14, 30));
    expect(timed.toMap()['remindMinutes'], 30);
    final allDay = timed.copyWith(allDay: true, start: DateTime(2026, 10, 7));
    expect(allDay.remindAt, DateTime(2026, 10, 7, 8, 30)); // 오전 9시의 30분 전
    final dayBefore = allDay.copyWith(remindMinutes: 1440);
    expect(dayBefore.remindAt, DateTime(2026, 10, 6, 9));
    final weekly = timed.copyWith(rule: const Recurrence(freq: Freq.weekly));
    expect(weekly.remindAt, isNull);
    expect(timed.copyWith(clearRemind: true).remindAt, isNull);
    // 이동형(규칙 반복 아님)은 다음 날짜로 옮기면 알림 시각도 같이 옮겨진다
    final rolled = timed.copyWith(start: DateTime(2026, 10, 8, 15, 0));
    expect(rolled.remindAt, DateTime(2026, 10, 8, 14, 30));
  });
}

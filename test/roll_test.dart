import 'package:flutter_test/flutter_test.dart';
import 'package:ourday/models/item.dart';

Item _roll(DateTime start, int every, RollUnit unit, {bool fromCompletion = true}) => Item(
    id: 'x', type: ItemType.todo, title: '약', start: start, ownerUid: 'me',
    rollEvery: every, rollUnit: unit, rollFromCompletion: fromCompletion);

String _d(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

void main() {
  timeTests();
  test('매일, 완료한 날 기준: 오늘 완료하면 내일', () {
    final i = _roll(DateTime(2026, 10, 2), 1, RollUnit.day);
    expect(_d(nextRollDate(i, DateTime(2026, 10, 2))), '2026-10-03');
  });

  test('매일, 완료한 날 기준: 며칠 밀려도 완료한 날의 다음 날', () {
    final i = _roll(DateTime(2026, 9, 28), 1, RollUnit.day);
    expect(_d(nextRollDate(i, DateTime(2026, 10, 2))), '2026-10-03');
  });

  test('예정일 기준: 밀리면 오늘 이후가 될 때까지 건너뜀', () {
    final i = _roll(DateTime(2026, 9, 28), 3, RollUnit.day, fromCompletion: false);
    // 9/28 -> 10/1 -> 10/4 (오늘 10/2 이후 첫 날짜)
    expect(_d(nextRollDate(i, DateTime(2026, 10, 2))), '2026-10-04');
  });

  test('예정일 기준: 제때 완료하면 예정일 + 간격', () {
    final i = _roll(DateTime(2026, 10, 25), 1, RollUnit.month, fromCompletion: false);
    expect(_d(nextRollDate(i, DateTime(2026, 10, 20))), '2026-11-25');
  });

  test('매주/2주마다', () {
    final i = _roll(DateTime(2026, 10, 1), 1, RollUnit.week, fromCompletion: false);
    expect(_d(nextRollDate(i, DateTime(2026, 10, 2))), '2026-10-08');
    final j = _roll(DateTime(2026, 10, 2), 2, RollUnit.week);
    expect(_d(nextRollDate(j, DateTime(2026, 10, 2))), '2026-10-16');
  });

  test('매월 31일은 짧은 달 말일로 보정, 연말 넘김', () {
    final i = _roll(DateTime(2026, 1, 31), 1, RollUnit.month);
    expect(_d(nextRollDate(i, DateTime(2026, 1, 31))), '2026-02-28');
    final j = _roll(DateTime(2026, 12, 15), 1, RollUnit.month);
    expect(_d(nextRollDate(j, DateTime(2026, 12, 15))), '2027-01-15');
  });

  test('매년 2/29는 평년엔 2/28', () {
    final i = _roll(DateTime(2028, 2, 29), 1, RollUnit.year);
    expect(_d(nextRollDate(i, DateTime(2028, 2, 29))), '2029-02-28');
  });

  test('라벨', () {
    expect(rollLabel(_roll(DateTime(2026, 10, 2), 1, RollUnit.day)), '매일');
    expect(rollLabel(_roll(DateTime(2026, 10, 2), 3, RollUnit.day)), '3일마다');
    expect(rollLabel(_roll(DateTime(2026, 10, 2), 2, RollUnit.month)), '2개월마다');
  });

  test('이동형 여부', () {
    expect(_roll(DateTime(2026, 10, 2), 1, RollUnit.day).isRolling, true);
    expect(_roll(DateTime(2026, 10, 2), 0, RollUnit.day).isRolling, false);
  });
}

void timeTests() {
  Item timed({DateTime? end, bool allDay = false, Repeat repeat = Repeat.none, int roll = 0}) => Item(
      id: 'x', type: ItemType.event, title: 't', start: DateTime(2026, 10, 7, 15, 0), end: end,
      allDay: allDay, ownerUid: 'me', repeat: repeat, rollEvery: roll);

  test('시간 표기', () {
    expect(timeLabel(timed(allDay: true)), isNull);
    expect(timeLabel(timed()), '15:00');
    expect(timeLabel(timed(end: DateTime(2026, 10, 7, 16, 30))), '15:00–16:30');
    expect(timeLabel(timed(end: DateTime(2026, 10, 9, 12, 0))), '15:00 → 10/9 12:00');
    // 반복 일정은 종료 날짜와 무관하게 시각 범위만
    expect(timeLabel(timed(end: DateTime(2026, 10, 7, 16, 0), repeat: Repeat.weekly)), '15:00–16:00');
    // 종료가 날짜만(00:00)이면 종료 시각 없음
    expect(timeLabel(timed(end: DateTime(2026, 10, 9))), '15:00');
  });

  test('이동형 반복은 다음 날짜로 옮기되 시각을 유지', () {
    final i = timed(roll: 1);
    final next = rollStart(i, DateTime(2026, 10, 7, 20, 0));
    expect(next, DateTime(2026, 10, 8, 15, 0));
    final allDay = timed(allDay: true, roll: 1);
    expect(rollStart(allDay, DateTime(2026, 10, 7)), DateTime(2026, 10, 8));
  });

  test('시간 있는 일정도 날짜 기준으로 달력에 나타남', () {
    final i = timed(end: DateTime(2026, 10, 9, 12, 0));
    expect(occursOn(i, DateTime(2026, 10, 7)), true);
    expect(occursOn(i, DateTime(2026, 10, 9)), true);
    expect(occursOn(i, DateTime(2026, 10, 10)), false);
  });
}

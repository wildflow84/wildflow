import 'package:flutter_test/flutter_test.dart';
import 'package:ourday/models/item.dart';

Item _roll(DateTime start, int every, RollUnit unit, {bool fromCompletion = true}) => Item(
    id: 'x', type: ItemType.todo, title: '약', start: start, ownerUid: 'me',
    rollEvery: every, rollUnit: unit, rollFromCompletion: fromCompletion);

String _d(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

void main() {
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

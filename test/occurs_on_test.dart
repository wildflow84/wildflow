import 'package:flutter_test/flutter_test.dart';
import 'package:ourday/models/item.dart';

Item _item(DateTime start, {DateTime? end, Repeat repeat = Repeat.none}) => Item(
    id: 'x', type: ItemType.event, title: 't', start: start, end: end, ownerUid: 'u', repeat: repeat);

void main() {
  test('멀티데이 일정은 시작~종료일 모두 포함', () {
    final i = _item(DateTime(2026, 10, 14), end: DateTime(2026, 10, 17));
    expect(occursOn(i, DateTime(2026, 10, 13)), false);
    expect(occursOn(i, DateTime(2026, 10, 14)), true);
    expect(occursOn(i, DateTime(2026, 10, 17)), true);
    expect(occursOn(i, DateTime(2026, 10, 18)), false);
  });

  test('매월 31일 반복은 짧은 달 말일로 보정', () {
    final i = _item(DateTime(2026, 1, 31), repeat: Repeat.monthly);
    expect(occursOn(i, DateTime(2026, 2, 28)), true);
    expect(occursOn(i, DateTime(2026, 2, 27)), false);
    expect(occursOn(i, DateTime(2026, 3, 31)), true);
  });

  test('매주 반복은 시작일 이전엔 안 나옴', () {
    final i = _item(DateTime(2026, 10, 5), repeat: Repeat.weekly);
    expect(occursOn(i, DateTime(2026, 9, 28)), false);
    expect(occursOn(i, DateTime(2026, 10, 12)), true);
    expect(occursOn(i, DateTime(2026, 10, 13)), false);
  });

  test('매년 반복', () {
    final i = _item(DateTime(2020, 10, 29), repeat: Repeat.yearly);
    expect(occursOn(i, DateTime(2026, 10, 29)), true);
    expect(occursOn(i, DateTime(2026, 10, 30)), false);
  });
}

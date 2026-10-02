import 'package:flutter_test/flutter_test.dart';
import 'package:ourday/models/lunar.dart';
import 'package:ourday/models/recurrence.dart';

void main() {
  test('매년 음력 5월 15일: 해마다 같은 음력 날짜 (양력은 매년 달라짐)', () {
    final start = lunarToSolar(2026, 5, 15)!;
    final r = presetRule(RepeatPreset.lunarYearly, start)!;
    expect(r.lunar, true);
    for (final y in [2027, 2030, 2040, 2100, 2199]) {
      final solar = lunarToSolar(y, 5, 15)!;
      expect(r.occursOn(start, solar), true, reason: '$y');
      expect(r.occursOn(start, solar.add(const Duration(days: 1))), false);
    }
    // 양력 같은 날짜는 해당 안 됨
    expect(r.occursOn(start, DateTime(2027, start.month, start.day)),
        solarToLunar(DateTime(2027, start.month, start.day))!.month == 5 &&
            solarToLunar(DateTime(2027, start.month, start.day))!.day == 15);
    // 시작 이전은 없음
    expect(r.occursOn(start, lunarToSolar(2025, 5, 15)!), false);
  });

  test('1년에 정확히 한 번 (평달만)', () {
    final start = lunarToSolar(2020, 4, 10)!; // 2020은 윤4월이 있는 해
    final r = presetRule(RepeatPreset.lunarYearly, start)!;
    for (var y = 2021; y <= 2060; y++) {
      var n = 0;
      for (var d = DateTime(y - 1, 12, 1); d.isBefore(DateTime(y + 1, 3, 1)); d = d.add(const Duration(days: 1))) {
        final l = solarToLunar(d)!;
        if (l.year == y && r.occursOn(start, d)) n++;
      }
      expect(n, 1, reason: '$y');
    }
    // 윤4월 10일에는 해당 안 됨
    final leap = lunarToSolar(2020, 4, 10, leap: true)!;
    expect(r.occursOn(start, leap), false);
  });

  test('음력 30일은 29일까지인 달에는 29일', () {
    // 음력 30일이 있는 달을 시작으로
    DateTime? start;
    for (var y = 2020; y < 2030 && start == null; y++) {
      for (var m = 1; m <= 12; m++) {
        final d = lunarToSolar(y, m, 30);
        if (d != null) {
          start = d;
          break;
        }
      }
    }
    final ls = solarToLunar(start!)!;
    final r = presetRule(RepeatPreset.lunarMonthly, start)!;
    var hit29 = 0, hit30 = 0;
    for (var d = start; d.isBefore(DateTime(start.year + 3, 1, 1)); d = d.add(const Duration(days: 1))) {
      if (!r.occursOn(start, d)) continue;
      final l = solarToLunar(d)!;
      if (l.day == 30) hit30++;
      if (l.day == 29) {
        hit29++;
        expect(lunarToSolar(l.year, l.month, 30, leap: l.leap), isNull);
      }
    }
    expect(ls.day, 30);
    expect(hit30 > 0 && hit29 > 0, true);
  });

  test('저장/복원, 설명, 빠른 선택 일치', () {
    final start = lunarToSolar(2026, 5, 15)!;
    final r = presetRule(RepeatPreset.lunarYearly, start)!;
    expect(Recurrence.fromMap(r.toMap()), r);
    expect(r.describe(start), '매년 음력 5월 15일');
    expect(presetRule(RepeatPreset.lunarMonthly, start)!.describe(start), '매월 음력 15일');
    expect(presetOf(r, start), RepeatPreset.lunarYearly);
    expect(presetChoices(start).any((c) => c.$1 == RepeatPreset.lunarYearly && c.$2 == '매년 음력 5월 15일'), true);
    // 양력 매년 규칙과는 다른 규칙
    expect(const Recurrence(freq: Freq.yearly) == r, false);
  });
}

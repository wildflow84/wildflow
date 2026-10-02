import 'package:flutter_test/flutter_test.dart';
import 'package:ourday/models/item.dart';
import 'package:ourday/models/recurrence.dart';

DateTime d(int y, int m, int day) => DateTime(y, m, day);

/// [from]~[to] 사이 발생일을 "M/d" 목록으로
List<String> occ(Recurrence r, DateTime start, DateTime from, DateTime to) {
  final out = <String>[];
  for (var x = from; !x.isAfter(to); x = DateTime(x.year, x.month, x.day + 1)) {
    if (r.occursOn(start, x)) out.add('${x.month}/${x.day}');
  }
  return out;
}

void main() {
  itemTests();
  group('일/주', () {
    test('매일, 3일마다', () {
      expect(occ(const Recurrence(freq: Freq.daily), d(2026, 10, 2), d(2026, 10, 1), d(2026, 10, 5)), ['10/2', '10/3', '10/4', '10/5']);
      expect(occ(const Recurrence(freq: Freq.daily, interval: 3), d(2026, 10, 2), d(2026, 10, 1), d(2026, 10, 12)), ['10/2', '10/5', '10/8', '10/11']);
    });

    test('매주 월·수·금 (구글의 요일 여러 개)', () {
      const r = Recurrence(freq: Freq.weekly, weekdays: [1, 3, 5]);
      // 2026-10-05는 월요일
      expect(occ(r, d(2026, 10, 5), d(2026, 10, 1), d(2026, 10, 14)), ['10/5', '10/7', '10/9', '10/12', '10/14']);
    });

    test('2주마다 월요일: 시작한 주 기준으로 격주', () {
      const r = Recurrence(freq: Freq.weekly, interval: 2, weekdays: [1]);
      expect(occ(r, d(2026, 10, 5), d(2026, 10, 1), d(2026, 11, 10)), ['10/5', '10/19', '11/2']);
    });

    test('시작일이 요일 규칙과 달라도 시작일 이전은 안 나옴', () {
      const r = Recurrence(freq: Freq.weekly, weekdays: [1, 3]);
      // 10/2는 금요일 -> 다음 월요일(10/5)부터
      expect(occ(r, d(2026, 10, 2), d(2026, 9, 28), d(2026, 10, 8)), ['10/5', '10/7']);
      expect(r.firstOnOrAfter(d(2026, 10, 2)), d(2026, 10, 5));
    });

    test('평일', () {
      const r = Recurrence(freq: Freq.weekly, weekdays: [1, 2, 3, 4, 5]);
      expect(occ(r, d(2026, 10, 2), d(2026, 10, 2), d(2026, 10, 7)), ['10/2', '10/5', '10/6', '10/7']);
    });
  });

  group('월 - 날짜 기준', () {
    test('매월 1일, 15일 (여러 날짜)', () {
      const r = Recurrence(freq: Freq.monthly, monthDays: [1, 15]);
      expect(occ(r, d(2026, 10, 1), d(2026, 10, 1), d(2026, 12, 31)), ['10/1', '10/15', '11/1', '11/15', '12/1', '12/15']);
    });

    test('매월 마지막 날: 달마다 28/29/30/31', () {
      const r = Recurrence(freq: Freq.monthly, monthDays: [-1]);
      expect(occ(r, d(2026, 1, 31), d(2026, 1, 1), d(2026, 5, 31)), ['1/31', '2/28', '3/31', '4/30', '5/31']);
      // 윤년 2월
      expect(occ(r, d(2028, 1, 31), d(2028, 2, 1), d(2028, 2, 29)), ['2/29']);
    });

    test('매월 31일: 구글처럼 31일이 없는 달은 건너뜀', () {
      const r = Recurrence(freq: Freq.monthly, monthDays: [31]);
      expect(occ(r, d(2026, 1, 31), d(2026, 1, 1), d(2026, 5, 31)), ['1/31', '3/31', '5/31']);
    });

    test('매월 31일 + 없는 달은 말일로 조정', () {
      const r = Recurrence(freq: Freq.monthly, monthDays: [31], clampMonthEnd: true);
      expect(occ(r, d(2026, 1, 31), d(2026, 1, 1), d(2026, 5, 31)), ['1/31', '2/28', '3/31', '4/30', '5/31']);
    });

    test('2개월마다 15일', () {
      const r = Recurrence(freq: Freq.monthly, interval: 2, monthDays: [15]);
      expect(occ(r, d(2026, 10, 15), d(2026, 10, 1), d(2027, 3, 31)), ['10/15', '12/15', '2/15']);
    });

    test('날짜를 비우면 시작일의 날짜', () {
      const r = Recurrence(freq: Freq.monthly);
      expect(occ(r, d(2026, 10, 7), d(2026, 10, 1), d(2026, 12, 31)), ['10/7', '11/7', '12/7']);
    });
  });

  group('월 - 요일 기준', () {
    test('매월 둘째 화요일', () {
      const r = Recurrence(freq: Freq.monthly, nth: 2, nthWeekday: 2);
      expect(occ(r, d(2026, 10, 13), d(2026, 10, 1), d(2026, 12, 31)), ['10/13', '11/10', '12/8']);
    });

    test('매월 마지막 금요일', () {
      const r = Recurrence(freq: Freq.monthly, nth: -1, nthWeekday: 5);
      expect(occ(r, d(2026, 10, 30), d(2026, 10, 1), d(2027, 1, 31)), ['10/30', '11/27', '12/25', '1/29']);
    });

    test('첫째 월요일', () {
      const r = Recurrence(freq: Freq.monthly, nth: 1, nthWeekday: 1);
      expect(occ(r, d(2026, 10, 5), d(2026, 10, 1), d(2026, 12, 31)), ['10/5', '11/2', '12/7']);
    });
  });

  group('년', () {
    test('매년 10월 2일, 2년마다', () {
      const r = Recurrence(freq: Freq.yearly, interval: 2);
      expect(occ(r, d(2026, 10, 2), d(2026, 1, 1), d(2030, 12, 31)).length, 3); // 2026, 2028, 2030
      expect(r.occursOn(d(2026, 10, 2), d(2027, 10, 2)), false);
      expect(r.occursOn(d(2026, 10, 2), d(2028, 10, 2)), true);
    });

    test('2월 29일: 구글처럼 윤년에만 / 조정하면 평년엔 28일', () {
      const skip = Recurrence(freq: Freq.yearly);
      expect(skip.occursOn(d(2028, 2, 29), d(2029, 2, 28)), false);
      expect(skip.occursOn(d(2028, 2, 29), d(2032, 2, 29)), true);
      const clamp = Recurrence(freq: Freq.yearly, clampMonthEnd: true);
      expect(clamp.occursOn(d(2028, 2, 29), d(2029, 2, 28)), true);
      expect(clamp.occursOn(d(2028, 2, 29), d(2032, 2, 28)), false); // 윤년엔 29일
    });
  });

  group('종료 조건', () {
    test('날짜까지(포함)', () {
      final r = Recurrence(freq: Freq.daily, until: d(2026, 10, 4));
      expect(occ(r, d(2026, 10, 2), d(2026, 10, 1), d(2026, 10, 8)), ['10/2', '10/3', '10/4']);
    });

    test('횟수: 정확히 N번', () {
      const r = Recurrence(freq: Freq.weekly, weekdays: [1, 3], count: 5);
      // 월/수 5번: 10/5, 10/7, 10/12, 10/14, 10/19
      expect(occ(r, d(2026, 10, 5), d(2026, 10, 1), d(2026, 12, 31)), ['10/5', '10/7', '10/12', '10/14', '10/19']);
      expect(r.lastOccurrence(d(2026, 10, 5)), d(2026, 10, 19));
    });

    test('횟수 + 매월 마지막 날', () {
      const r = Recurrence(freq: Freq.monthly, monthDays: [-1], count: 3);
      expect(occ(r, d(2026, 1, 31), d(2026, 1, 1), d(2026, 12, 31)), ['1/31', '2/28', '3/31']);
    });

    test('먼 미래 조회도 빠르게 끝남 (횟수 종료 없음)', () {
      const r = Recurrence(freq: Freq.daily);
      final sw = Stopwatch()..start();
      for (var i = 0; i < 2000; i++) {
        r.occursOn(d(2026, 1, 1), d(2150, 6, 1));
      }
      expect(sw.elapsedMilliseconds < 1500, true);
    });
  });

  group('설명 문구', () {
    test('한국어 요약', () {
      final s = d(2026, 10, 7); // 수요일
      expect(const Recurrence(freq: Freq.daily).describe(s), '매일');
      expect(const Recurrence(freq: Freq.daily, interval: 3).describe(s), '3일마다');
      expect(const Recurrence(freq: Freq.weekly, weekdays: [1, 3]).describe(s), '매주 월·수');
      expect(const Recurrence(freq: Freq.weekly, weekdays: [3]).describe(s), '매주 수요일');
      expect(const Recurrence(freq: Freq.weekly, weekdays: [1, 2, 3, 4, 5]).describe(s), '평일 (월~금)');
      expect(const Recurrence(freq: Freq.weekly, interval: 2, weekdays: [1]).describe(s), '2주마다 월');
      expect(const Recurrence(freq: Freq.monthly, monthDays: [1, 15, -1]).describe(s), '매월 1일·15일·마지막 날');
      expect(const Recurrence(freq: Freq.monthly, nth: 2, nthWeekday: 2).describe(s), '매월 둘째 화요일');
      expect(const Recurrence(freq: Freq.monthly, nth: -1, nthWeekday: 5).describe(s), '매월 마지막 금요일');
      expect(const Recurrence(freq: Freq.monthly, interval: 3, monthDays: [10]).describe(s), '3개월마다 10일');
      expect(const Recurrence(freq: Freq.yearly).describe(s), '매년 10월 7일');
      expect(Recurrence(freq: Freq.daily, until: d(2027, 1, 31)).describe(s), '매일 · 2027.1.31까지');
      expect(const Recurrence(freq: Freq.daily, count: 10).describe(s), '매일 · 10회');
      expect(const Recurrence(freq: Freq.monthly, monthDays: [31], clampMonthEnd: true).describe(s), '매월 31일 (없는 달은 말일)');
    });
  });

  group('빠른 선택', () {
    test('선택 항목은 시작일에서 정해진다', () {
      final s = d(2026, 10, 30); // 금요일, 10월 마지막 주
      final labels = presetChoices(s).map((e) => e.$2).toList();
      expect(labels, contains('매주 금요일'));
      expect(labels, contains('매월 30일'));
      expect(labels, contains('매월 마지막 금요일'));
      expect(labels, contains('매월 마지막 날'));
      expect(labels, contains('매년 10월 30일'));
      // 다섯째 금요일이면 "첫째~넷째"는 안 나온다
      expect(labels.any((l) => l.contains('다섯')), false);
    });

    test('규칙 -> 빠른 선택 되짚기', () {
      final s = d(2026, 10, 7);
      expect(presetOf(null, s), RepeatPreset.none);
      expect(presetOf(presetRule(RepeatPreset.weekly, s), s), RepeatPreset.weekly);
      expect(presetOf(presetRule(RepeatPreset.monthlyDate, s), s), RepeatPreset.monthlyDate);
      expect(presetOf(presetRule(RepeatPreset.monthlyNth, s), s), RepeatPreset.monthlyNth);
      expect(presetOf(presetRule(RepeatPreset.weekdays, s), s), RepeatPreset.weekdays);
      expect(presetOf(const Recurrence(freq: Freq.daily, count: 5), s), RepeatPreset.custom);
      expect(presetOf(const Recurrence(freq: Freq.weekly, weekdays: [1, 3]), s), RepeatPreset.custom);
    });
  });

  test('저장/복원', () {
    final r = Recurrence(freq: Freq.monthly, interval: 2, monthDays: [1, -1], clampMonthEnd: true, until: d(2027, 5, 1));
    final back = Recurrence.fromMap(r.toMap());
    expect(back, r);
    expect(back.until, d(2027, 5, 1));
    expect(Recurrence.fromMap(const Recurrence(freq: Freq.weekly, weekdays: [2], count: 4).toMap()).count, 4);
  });
}

// ---- Item 연동: 옛 반복 데이터 호환 / 구글식 규칙 / 삭제 범위 ----
void itemTests() {
  Item mk({Repeat repeat = Repeat.none, Recurrence? rule, DateTime? start}) => Item(
      id: 'x', type: ItemType.event, title: 't', start: start ?? DateTime(2026, 10, 7), ownerUid: 'me',
      repeat: repeat, rule: rule);

  test('옛 데이터(repeat만 있음)가 같은 의미의 규칙으로 해석된다', () {
    final w = mk(repeat: Repeat.weekly);
    expect(w.effectiveRule!.describe(w.start), '매주 수요일');
    expect(w.isRecurring, true);
    expect(occursOn(w, DateTime(2026, 10, 14)), true);
    expect(occursOn(w, DateTime(2026, 10, 15)), false);
    // 매월 31일: 옛 동작대로 짧은 달은 말일로
    final m = mk(repeat: Repeat.monthly, start: DateTime(2026, 1, 31));
    expect(occursOn(m, DateTime(2026, 2, 28)), true);
    expect(occursOn(m, DateTime(2026, 4, 30)), true);
    // 매년 2/29: 평년엔 2/28
    final y = mk(repeat: Repeat.yearly, start: DateTime(2028, 2, 29));
    expect(occursOn(y, DateTime(2029, 2, 28)), true);
  });

  test('새 규칙이 있으면 repeat 값보다 우선', () {
    final i = mk(
        repeat: Repeat.weekly,
        rule: const Recurrence(freq: Freq.monthly, monthDays: [-1]),
        start: DateTime(2026, 10, 31));
    expect(occursOn(i, DateTime(2026, 11, 30)), true);
    expect(occursOn(i, DateTime(2026, 11, 7)), false);
    expect(repeatFor(i.rule), Repeat.monthly);
    expect(repeatFor(null), Repeat.none);
  });

  test('규칙 저장 필드: toMap에 rule 포함, 반복 없으면 null', () {
    final i = mk(rule: const Recurrence(freq: Freq.weekly, weekdays: [1, 3]));
    expect(i.toMap()['rule']['weekdays'], [1, 3]);
    expect(mk().toMap()['rule'], isNull);
  });

  test('구글식 규칙에서도 "이 날짜만/이후 삭제"가 동작', () {
    final i = mk(rule: const Recurrence(freq: Freq.monthly, nth: 2, nthWeekday: 2), start: DateTime(2026, 10, 13));
    final one = applyRepeatDelete(i, DateTime(2026, 11, 10), RepeatDelete.thisOnly)!;
    expect(occursOn(one, DateTime(2026, 11, 10)), false);
    expect(occursOn(one, DateTime(2026, 12, 8)), true);
    final after = applyRepeatDelete(i, DateTime(2026, 12, 8), RepeatDelete.following)!;
    expect(occursOn(after, DateTime(2026, 11, 10)), true);
    expect(occursOn(after, DateTime(2026, 12, 8)), false);
    expect(occursOn(after, DateTime(2027, 1, 12)), false);
  });

  test('횟수 종료 + 예외 날짜 + 이후 삭제가 함께 동작', () {
    final i = mk(rule: const Recurrence(freq: Freq.daily, count: 5), start: DateTime(2026, 10, 1));
    expect(occursOn(i, DateTime(2026, 10, 5)), true);
    expect(occursOn(i, DateTime(2026, 10, 6)), false);
    final skip = applyRepeatDelete(i, DateTime(2026, 10, 3), RepeatDelete.thisOnly)!;
    expect(occursOn(skip, DateTime(2026, 10, 3)), false);
    expect(occursOn(skip, DateTime(2026, 10, 4)), true);
  });

  test('시간 표기: 구글식 규칙도 반복으로 취급해 종료 날짜 무관', () {
    final i = Item(
        id: 'x', type: ItemType.event, title: 't', start: DateTime(2026, 10, 7, 15, 0),
        end: DateTime(2026, 10, 7, 16, 0), allDay: false, ownerUid: 'me',
        rule: const Recurrence(freq: Freq.weekly, weekdays: [3]));
    expect(timeLabel(i), '15:00–16:00');
  });
}

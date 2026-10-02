import 'package:flutter_test/flutter_test.dart';
import 'package:ourday/models/item.dart';
import 'package:ourday/models/recurrence.dart';

Item _roll(DateTime start, int every, RollUnit unit, {bool fromCompletion = true}) => Item(
    id: 'x', type: ItemType.todo, title: '약', start: start, ownerUid: 'me',
    rollEvery: every, rollUnit: unit, rollFromCompletion: fromCompletion);

String _d(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

void main() {
  timeTests();
  todoTimeTests();
  repeatDeleteTests();
  futureCompleteTests();
  rollRuleTests();
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

void todoTimeTests() {
  Item todo({bool allDay = false, DateTime? start}) => Item(
      id: 'x', type: ItemType.todo, title: '약', start: start ?? DateTime(2026, 10, 2, 8, 0),
      allDay: allDay, ownerUid: 'me');

  test('할 일의 시각은 마감: "08:00까지", 칩은 "~08:00"', () {
    expect(timeLabel(todo()), '08:00까지');
    expect(chipTimeLabel(todo()), '~08:00');
    expect(timeLabel(todo(allDay: true)), isNull);
  });

  test('마감 시각이 지나면 지난 할 일, 종일이면 날짜가 지났을 때만', () {
    final now = DateTime(2026, 10, 2, 10, 0);
    expect(isOverdue(todo(), now), true); // 오늘 8시 마감, 지금 10시
    expect(isOverdue(todo(start: DateTime(2026, 10, 2, 18, 0)), now), false);
    expect(isOverdue(todo(allDay: true, start: DateTime(2026, 10, 2)), now), false); // 오늘 종일은 아직
    expect(isOverdue(todo(allDay: true, start: DateTime(2026, 10, 1)), now), true);
  });
}

void repeatDeleteTests() {
  Item weekly() => Item(
      id: 'x', type: ItemType.event, title: '정기점검', start: DateTime(2026, 10, 7), ownerUid: 'me',
      repeat: Repeat.weekly);

  test('이 날짜만 삭제: 그 회차만 빠지고 나머지는 유지', () {
    final r = applyRepeatDelete(weekly(), DateTime(2026, 10, 21), RepeatDelete.thisOnly)!;
    expect(occursOn(r, DateTime(2026, 10, 14)), true);
    expect(occursOn(r, DateTime(2026, 10, 21)), false);
    expect(occursOn(r, DateTime(2026, 10, 28)), true);
    // 같은 날짜를 두 번 지워도 중복되지 않는다
    final again = applyRepeatDelete(r, DateTime(2026, 10, 21), RepeatDelete.thisOnly)!;
    expect(again.exceptions.length, 1);
  });

  test('이 날짜 이후 삭제: 앞의 기록은 남고 이후로는 사라짐', () {
    final r = applyRepeatDelete(weekly(), DateTime(2026, 10, 21), RepeatDelete.following)!;
    expect(occursOn(r, DateTime(2026, 10, 7)), true);
    expect(occursOn(r, DateTime(2026, 10, 14)), true);
    expect(occursOn(r, DateTime(2026, 10, 21)), false);
    expect(occursOn(r, DateTime(2026, 10, 28)), false);
    expect(occursOn(r, DateTime(2030, 1, 2)), false); // 먼 미래도
  });

  test('첫 회차에서 "이 날짜 이후"를 고르면 전체 삭제와 같음', () {
    expect(applyRepeatDelete(weekly(), DateTime(2026, 10, 7), RepeatDelete.following), isNull);
    expect(applyRepeatDelete(weekly(), DateTime(2026, 10, 1), RepeatDelete.following), isNull);
  });

  test('전체 삭제', () {
    expect(applyRepeatDelete(weekly(), DateTime(2026, 10, 21), RepeatDelete.all), isNull);
  });

  test('저장/복원 필드: repeatUntil, exceptions 가 toMap에 들어간다', () {
    final r = applyRepeatDelete(weekly(), DateTime(2026, 10, 21), RepeatDelete.following)!;
    expect(r.toMap()['repeatUntil'], isNotNull);
    final t = applyRepeatDelete(weekly(), DateTime(2026, 10, 21), RepeatDelete.thisOnly)!;
    expect(t.toMap()['exceptions'], ['2026-10-21']);
  });

  test('매월 31일 같은 반복도 until/exceptions 가 동작', () {
    final m = Item(
        id: 'm', type: ItemType.todo, title: '퇴직연금', start: DateTime(2026, 1, 31), ownerUid: 'me',
        repeat: Repeat.monthly);
    final r = applyRepeatDelete(m, DateTime(2026, 4, 30), RepeatDelete.following)!;
    expect(occursOn(r, DateTime(2026, 3, 31)), true);
    expect(occursOn(r, DateTime(2026, 4, 30)), false);
    expect(occursOn(r, DateTime(2026, 5, 31)), false);
  });
}

void futureCompleteTests() {
  Item pill(DateTime start, {bool completion = true}) => Item(
      id: 'p', type: ItemType.todo, title: '약', start: start, ownerUid: 'me',
      rollEvery: 1, rollUnit: RollUnit.day, rollFromCompletion: completion);

  test('내일 것을 오늘 미리 완료하면 모레로 넘어감', () {
    final tomorrowPill = pill(DateTime(2026, 10, 3));
    expect(_d(nextRollDate(tomorrowPill, DateTime(2026, 10, 2))), '2026-10-04');
  });

  test('미리 계속 완료할 수 있음 (오늘 안에 연속으로)', () {
    var item = pill(DateTime(2026, 10, 2));
    final today = DateTime(2026, 10, 2);
    final seen = <String>[];
    for (var i = 0; i < 3; i++) {
      final next = nextRollDate(item, today);
      seen.add(_d(next));
      item = item.copyWith(start: next);
    }
    expect(seen, ['2026-10-03', '2026-10-04', '2026-10-05']);
  });

  test('밀린 것을 완료하면 여전히 내일 (기존 동작 유지)', () {
    expect(_d(nextRollDate(pill(DateTime(2026, 9, 28)), DateTime(2026, 10, 2))), '2026-10-03');
  });

  test('날짜 드래그 이동: 시각과 기간 유지', () {
    final e = Item(
        id: 'e', type: ItemType.event, title: '여행', start: DateTime(2026, 10, 14, 9, 30),
        end: DateTime(2026, 10, 17, 18, 0), allDay: false, ownerUid: 'me');
    final m = moveItemByDays(e, 3);
    expect(m.start, DateTime(2026, 10, 17, 9, 30));
    expect(m.end, DateTime(2026, 10, 20, 18, 0));
    final back = moveItemByDays(m, -3);
    expect(back.start, e.start);
    // 월 경계
    expect(moveItemByDays(e, 20).start, DateTime(2026, 11, 3, 9, 30));
  });
}

void rollRuleTests() {
  // 2026-10-08은 목요일
  Item weeklyThu({DateTime? start, Recurrence? rule}) => Item(
      id: 'r', type: ItemType.todo, title: '목요일 점검', start: start ?? DateTime(2026, 10, 8), ownerUid: 'me',
      rollRule: rule ?? const Recurrence(freq: Freq.weekly, weekdays: [4]));

  test('이동형 기본 기준은 예정일', () {
    final i = Item(id: 'x', type: ItemType.todo, title: 't', start: DateTime(2026, 10, 2), ownerUid: 'me', rollEvery: 1);
    expect(i.rollFromCompletion, false);
  });

  test('매주 목요일 이동형: 완료하면 다음 목요일로', () {
    final i = weeklyThu();
    expect(i.isRolling, true);
    expect(i.isRecurring, false); // 달력에 계속 반복해서 나오지 않는다
    expect(_d(nextRollDate(i, DateTime(2026, 10, 8))), '2026-10-15');
    final done = rollNextItem(i, DateTime(2026, 10, 8, 20), 'me');
    expect(_d(done.start), '2026-10-15');
    expect(done.done, false);
    expect(done.lastDoneBy, 'me');
  });

  test('미리 완료해도 다음 회차로 한 칸만 전진', () {
    // 10/8 목요일 항목을 10/2에 미리 완료 -> 10/15
    expect(_d(nextRollDate(weeklyThu(), DateTime(2026, 10, 2))), '2026-10-15');
  });

  test('밀린 것을 늦게 완료하면 오늘 이후 첫 목요일', () {
    // 10/1 목요일 항목을 토요일 10/3에 완료 -> 10/8
    expect(_d(nextRollDate(weeklyThu(start: DateTime(2026, 10, 1)), DateTime(2026, 10, 3))), '2026-10-08');
    // 여러 주 밀렸어도 오늘 이후 첫 목요일 (9/10 항목, 10/3 완료 -> 10/8)
    expect(_d(nextRollDate(weeklyThu(start: DateTime(2026, 9, 10)), DateTime(2026, 10, 3))), '2026-10-08');
  });

  test('매월 마지막 날 이동형', () {
    final i = weeklyThu(start: DateTime(2026, 1, 31), rule: const Recurrence(freq: Freq.monthly, monthDays: [-1]));
    expect(_d(nextRollDate(i, DateTime(2026, 1, 31))), '2026-02-28');
    final n = rollNextItem(i, DateTime(2026, 1, 31), 'me');
    expect(_d(rollNextItem(n, DateTime(2026, 2, 28), 'me').start), '2026-03-31');
  });

  test('격주 이동형은 위상을 유지', () {
    final i = weeklyThu(rule: const Recurrence(freq: Freq.weekly, interval: 2, weekdays: [4]));
    var cur = i;
    final seen = <String>[];
    for (var k = 0; k < 3; k++) {
      cur = rollNextItem(cur, cur.start, 'me');
      seen.add(_d(cur.start));
    }
    expect(seen, ['2026-10-22', '2026-11-05', '2026-11-19']);
  });

  test('평일 이동형: 금요일 완료 -> 월요일', () {
    final i = weeklyThu(start: DateTime(2026, 10, 2), rule: const Recurrence(freq: Freq.weekly, weekdays: [1, 2, 3, 4, 5]));
    expect(_d(nextRollDate(i, DateTime(2026, 10, 2))), '2026-10-05');
  });

  test('시각을 유지한다', () {
    final i = Item(
        id: 'r', type: ItemType.todo, title: 't', start: DateTime(2026, 10, 8, 8, 30), allDay: false, ownerUid: 'me',
        rollRule: const Recurrence(freq: Freq.weekly, weekdays: [4]));
    expect(rollNextItem(i, DateTime(2026, 10, 8), 'me').start, DateTime(2026, 10, 15, 8, 30));
  });

  test('횟수 종료: 3회 뒤 완료 처리, 남은 횟수가 줄어든다', () {
    var cur = weeklyThu(rule: const Recurrence(freq: Freq.weekly, weekdays: [4], count: 3));
    cur = rollNextItem(cur, cur.start, 'me');
    expect(cur.rollRule!.count, 2);
    expect(_d(cur.start), '2026-10-15');
    cur = rollNextItem(cur, cur.start, 'me');
    expect(cur.rollRule!.count, 1);
    cur = rollNextItem(cur, cur.start, 'me');
    expect(cur.done, true); // 마지막 회차를 끝냄
    expect(_d(cur.start), '2026-10-22'); // 날짜는 마지막 회차에 머문다
  });

  test('종료일을 지나면 완료 처리', () {
    final i = weeklyThu(rule: Recurrence(freq: Freq.weekly, weekdays: [4], until: DateTime(2026, 10, 10)));
    expect(rollNextItem(i, DateTime(2026, 10, 8), 'me').done, true);
  });

  test('라벨, 저장 필드', () {
    final i = weeklyThu();
    expect(rollLabel(i), '매주 목요일');
    expect(i.toMap()['rollRule']['weekdays'], [4]);
    expect(i.copyWith(clearRollRule: true).rollRule, isNull);
  });

  test('이전 방식(간격형, 완료한 날 기준)도 그대로 동작', () {
    final i = Item(
        id: 'p', type: ItemType.todo, title: '약', start: DateTime(2026, 10, 3), ownerUid: 'me',
        rollEvery: 1, rollUnit: RollUnit.day, rollFromCompletion: true);
    expect(_d(rollNextItem(i, DateTime(2026, 10, 2), 'me').start), '2026-10-04');
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:ourday/models/item.dart';

void main() {
  timeTests();
  todoTimeTests();
  repeatDeleteTests();
  moveTests();
}

void timeTests() {
  Item timed({DateTime? end, bool allDay = false, Repeat repeat = Repeat.none}) => Item(
      id: 'x', type: ItemType.event, title: 't', start: DateTime(2026, 10, 7, 15, 0), end: end,
      allDay: allDay, ownerUid: 'me', repeat: repeat);

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

void moveTests() {
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

  test('반복 일정의 한 회차만 앞당기기', () {
    final e = Item(
        id: 'e', type: ItemType.event, title: '병원', start: DateTime(2026, 10, 1, 9, 30),
        repeat: Repeat.weekly, allDay: false, ownerUid: 'me');
    final r = moveOccurrence(e, DateTime(2026, 10, 29), DateTime(2026, 10, 16));
    expect(r[0].id, '');
    expect(r[0].isRecurring, false);
    expect(r[0].start, DateTime(2026, 10, 16, 9, 30));
    expect(r[1].exceptions, ['2026-10-29']);
    expect(r[1].isRecurring, true);
  });
}

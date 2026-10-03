import 'package:flutter_test/flutter_test.dart';
import 'package:ourday/models/item.dart';
import 'package:ourday/models/recurrence.dart';

Item _weekly() => Item(
    id: 'w', type: ItemType.event, title: '운동', start: DateTime(2026, 10, 5, 19), allDay: false, ownerUid: 'me',
    rule: const Recurrence(freq: Freq.weekly, weekdays: [1]),
    exceptions: const ['2026-10-19', '2026-11-16'],
    doneDates: const ['2026-10-05', '2026-10-26']);

void main() {
  final day = DateTime(2026, 10, 26); // 넷째 월요일 회차
  final occ = DateTime(2026, 10, 26, 20);

  test('모든 일정: 수정본 그대로', () {
    final e = _weekly().copyWith(title: '러닝');
    final r = applyRepeatEdit(_weekly(), e, day, RepeatEdit.all, occurrenceStart: occ);
    expect(r.length, 1);
    expect(r.single.id, 'w');
    expect(r.single.title, '러닝');
  });

  test('이 일정만: 그날 제외 + 그날 하루짜리 새 일정', () {
    final o = _weekly();
    final e = o.copyWith(title: '러닝', note: '비 오면 취소');
    final r = applyRepeatEdit(o, e, day, RepeatEdit.thisOnly, occurrenceStart: occ);
    expect(r.length, 2);
    final single = r[0], orig = r[1];
    expect(single.id, '');
    expect(single.title, '러닝');
    expect(single.isRecurring, false);
    expect(single.start, occ);
    expect(single.exceptions, isEmpty);
    expect(orig.id, 'w');
    expect(orig.title, '운동'); // 원본 내용은 그대로
    expect(orig.exceptions, contains('2026-10-26'));
    expect(occursOn(orig, day), false);
    expect(occursOn(orig, DateTime(2026, 11, 2)), true);
    expect(occursOn(single, day), true);
    expect(occursOn(single, DateTime(2026, 11, 2)), false);
  });

  test('이 일정 및 이후: 원본은 전날까지, 새 반복은 그날부터', () {
    final o = _weekly();
    final e = o.copyWith(title: '러닝', start: occ);
    final r = applyRepeatEdit(o, e, day, RepeatEdit.following, occurrenceStart: occ);
    expect(r.length, 2);
    final next = r[0], orig = r[1];
    expect(next.id, '');
    expect(next.title, '러닝');
    expect(next.isRecurring, true);
    expect(next.start, occ);
    expect(next.doneDates, ['2026-10-26']); // 그날 이후 기록만 새 쪽으로
    expect(next.exceptions, ['2026-11-16']);
    expect(orig.repeatUntil, DateTime(2026, 10, 25));
    // 같은 날이 두 항목에 겹치지 않는다
    for (final d in [DateTime(2026, 10, 12), DateTime(2026, 10, 26), DateTime(2026, 11, 2), DateTime(2026, 11, 9)]) {
      expect(occursOn(orig, d) != occursOn(next, d), true, reason: '$d');
    }
    expect(occursOn(orig, DateTime(2026, 10, 12)), true);
    expect(occursOn(next, DateTime(2026, 10, 12)), false);
    expect(occursOn(next, DateTime(2026, 11, 16)), false); // 이후 예외 날짜 유지
  });

  test('첫 회차에서 이후 수정은 전체 수정과 같다', () {
    final o = _weekly();
    final e = o.copyWith(title: '러닝');
    final r = applyRepeatEdit(o, e, DateTime(2026, 10, 5), RepeatEdit.following, occurrenceStart: DateTime(2026, 10, 5, 19));
    expect(r.length, 1);
    expect(r.single.id, 'w');
  });
}

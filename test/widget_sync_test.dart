import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ourday/data/widget_sync.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:ourday/models/item.dart';
import 'package:ourday/models/kr_calendar.dart' show CustomDay;
import 'package:ourday/models/lunar.dart' show dayNumber;
import 'package:ourday/models/recurrence.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ko'));

  Item ev(String t, DateTime d) => Item(id: t, type: ItemType.event, title: t, start: d, ownerUid: 'me', allDay: true);

  test('목록형: 오늘이 비면 안내 문구, 앞으로 일정은 날짜 머리글과 함께', () {
    final today = DateTime(2026, 10, 3);
    final text = WidgetSync.agendaText([ev('치과', DateTime(2026, 10, 5))], today);
    expect(text.split('\n').first, '오늘은 일정이 없어');
    expect(text, contains('10/5'));
    expect(text, contains('• 치과'));
  });

  test('목록형: 최대 줄 수를 넘기지 않음', () {
    final today = DateTime(2026, 10, 3);
    final many = [for (var i = 0; i < 30; i++) ev('일정$i', today)];
    expect(WidgetSync.agendaText(many, today).split('\n').length, lessThanOrEqualTo(10));
  });

  agendaJsonTests();

  test('달력형: 일정이 있는 날만 yyyyMMdd로', () {
    final today = DateTime(2026, 10, 3);
    final days = WidgetSync.eventDays([ev('a', DateTime(2026, 10, 5)), ev('b', DateTime(2026, 11, 2))], today).split(',');
    expect(days, containsAll(['20261005', '20261102']));
    expect(days, isNot(contains('20261006')));
  });
}

void agendaJsonTests() {
  test('목록형 JSON: 오늘 머리글, 공휴일 표시, 항목 필드', () {
    final today = DateTime(2026, 10, 3);
    final it = Item(
        id: 'a', type: ItemType.event, title: '미용실', start: DateTime(2026, 10, 4, 14), ownerUid: 'me',
        end: DateTime(2026, 10, 4, 17), location: '헤어유메이');
    final json = WidgetSync.agendaJson(
      [it],
      today,
      colorOf: (_) => 0xFF123456,
      categoryName: (_) => '가족',
      holidaysOn: (d) => d.day == 5 ? ['개천절 대체공휴일'] : const [],
    );
    final days = jsonDecode(json) as List;
    final todayDay = days.firstWhere((d) => (d as Map)['date'] == '2026-10-03') as Map;
    expect(todayDay['kind'], 'today');
    expect(todayDay['label'], startsWith('오늘 ·'));
    // 지난 날도 위에 담긴다 (날짜순)
    final dates = [for (final d in days) (d as Map)['date'] as String];
    expect(dates, [...dates]..sort());
    expect(dates.first.compareTo('2026-10-03') < 0, isTrue);
    final d4 = days.firstWhere((d) => (d as Map)['label'].toString().contains('4일')) as Map;
    final item = (d4['items'] as List).first as Map;
    expect(item['t'], '미용실');
    expect(item['cat'], '가족');
    expect(item['place'], '헤어유메이');
    expect(item['color'], 0xFF123456);
    final d5 = days.firstWhere((d) => (d as Map)['label'].toString().contains('5일')) as Map;
    expect(d5['kind'], 'holiday');
    expect(d5['note'], contains('개천절'));
    // 자정이 지난 뒤 위젯이 지난 날을 빼는 데 쓰는 날짜, 이동형 표시
    expect(d4['date'], '2026-10-04');
    expect(item['roll'], false);
  });

  test('이동형 할 일은 위젯 JSON에 roll 표시', () {
    final today = DateTime(2026, 10, 3);
    final roll = Item(
        id: 'r', type: ItemType.todo, title: '약', start: DateTime(2026, 10, 3), ownerUid: 'me',
        rollEvery: 1, rollUnit: RollUnit.day);
    final days = jsonDecode(WidgetSync.agendaJson([roll], today, spaceId: 's')) as List;
    final it = ((days.first as Map)['items'] as List).first as Map;
    expect(it['roll'], true);
    expect(it['can'], true);
  });

  test('달력형 칸 내용: 그날 항목 수와 앞의 2개(제목, 색)', () {
    final today = DateTime(2026, 10, 3);
    Item ev(String id, String t, int d) =>
        Item(id: id, type: ItemType.event, title: t, start: DateTime(2026, 10, d, 9), ownerUid: 'me', allDay: false);
    final cells = WidgetSync.calendarCells(
      [ev('a', '미용실', 4), ev('b', '아주아주아주긴일정제목입니다', 4), ev('c', '치과', 4), ev('d', '점심', 7)],
      today,
      colorOf: (i) => i.id == 'a' ? 0xFF111111 : 0xFF222222,
    );
    final d4 = cells['20261004'] as Map;
    expect(d4['n'], 3);
    expect((d4['e'] as List).length, 2);
    expect(((d4['e'] as List)[0] as Map)['t'], '미용실');
    expect(((d4['e'] as List)[0] as Map)['c'], 0xFF111111);
    expect((((d4['e'] as List)[1]) as Map)['t'].toString().length, 10); // 긴 제목은 10자까지
    expect((cells['20261007'] as Map)['n'], 1);
    expect(cells.containsKey('20261005'), isFalse);
  });

  test('달력형 칸: 공휴일/명절 이름이 들어가고, 공휴일만 있는 날은 점 표시에서 빠진다', () {
    final today = DateTime(2026, 9, 20);
    final ev = Item(id: 'a', type: ItemType.event, title: '성묘', start: DateTime(2026, 9, 25, 9), ownerUid: 'me', allDay: false);
    List<String> hol(DateTime d) => d.month == 9 && d.day >= 24 && d.day <= 26 ? ['추석'] : const [];
    final cells = WidgetSync.calendarCells([ev], today, holidaysOn: hol);
    expect((cells['20260925'] as Map)['h'], '추석');
    expect((cells['20260925'] as Map)['n'], 1);
    expect((cells['20260924'] as Map)['n'], 0);
    expect((cells['20260924'] as Map)['h'], '추석');
  });

  group('날짜별 항목 표 (성능 개선)', () {
    List<Item> sample() {
      final items = <Item>[];
      for (var i = 0; i < 40; i++) {
        items.add(Item(
            id: 's$i', type: i.isEven ? ItemType.event : ItemType.todo, title: 's$i',
            start: DateTime(2026, 1 + i % 12, 1 + i % 27, 9), ownerUid: 'u', allDay: false,
            end: i % 7 == 0 ? DateTime(2026, 1 + i % 12, 3 + i % 27) : null));
      }
      const rules = [
        Recurrence(freq: Freq.daily, interval: 3),
        Recurrence(freq: Freq.weekly, interval: 2, weekdays: [1, 3, 7]),
        Recurrence(freq: Freq.monthly, monthDays: [31]),
        Recurrence(freq: Freq.monthly, monthDays: [-1]),
        Recurrence(freq: Freq.monthly, nth: 2, nthWeekday: 2),
        Recurrence(freq: Freq.yearly, clampMonthEnd: true),
        Recurrence(freq: Freq.yearly, lunar: true),
        Recurrence(freq: Freq.monthly, lunar: true),
        Recurrence(freq: Freq.weekly, count: 12),
        Recurrence(freq: Freq.daily, count: 30, interval: 2),
      ];
      for (var i = 0; i < rules.length; i++) {
        items.add(Item(id: 'r$i', type: ItemType.event, title: 'r$i', start: DateTime(2025, 2, 10 + i), ownerUid: 'u', rule: rules[i]));
      }
      items.add(Item(id: 'x1', type: ItemType.event, title: 'x', start: DateTime(2026, 1, 1), ownerUid: 'u',
          rule: const Recurrence(freq: Freq.daily), repeatUntil: DateTime(2026, 12, 20),
          exceptions: ['2026-10-05', '2026-10-06', '2026-11-30']));
      items.add(Item(id: 'x2', type: ItemType.event, title: 'x', start: DateTime(2025, 1, 1), ownerUid: 'u',
          rule: Recurrence(freq: Freq.weekly, until: DateTime(2026, 10, 1))));
      items.add(Item(id: 'x3', type: ItemType.event, title: 'x', start: DateTime(2026, 3, 1), ownerUid: 'u', repeat: Repeat.monthly));
      items.add(Item(id: 'x4', type: ItemType.event, title: 'x', start: DateTime(2026, 3, 9), ownerUid: 'u', end: DateTime(2026, 3, 2)));
      return items;
    }

    test('날짜별 표가 날마다 occursOn 으로 거른 결과와 같다', () {
      final items = sample();
      final today = DateTime(2026, 10, 22);
      final (from, to) = WidgetSync.rangeFor(today);
      final idx = WidgetSync.dayIndex(items, from, to);
      var checked = 0;
      for (var d = from; !d.isAfter(to); d = DateTime(d.year, d.month, d.day + 1)) {
        final want = {for (final i in items) if (occursOn(i, d)) i.id};
        final got = {for (final i in idx[dayNumber(d)] ?? const <Item>[]) i.id};
        expect(got, want, reason: '$d');
        checked += want.length;
      }
      expect(checked, greaterThan(500)); // 비어 있는 비교가 아니다
    });

    test('같은 날 안의 순서: 일정 먼저, 그다음 시작 시각, 같으면 id 순', () {
      final a = Item(id: 'b', type: ItemType.todo, title: 'a', start: DateTime(2026, 10, 22, 8), ownerUid: 'u', allDay: false);
      final b = Item(id: 'a', type: ItemType.event, title: 'b', start: DateTime(2026, 10, 22, 12), ownerUid: 'u', allDay: false);
      final c = Item(id: 'c', type: ItemType.event, title: 'c', start: DateTime(2026, 10, 22, 12), ownerUid: 'u', allDay: false);
      final idx = WidgetSync.dayIndex([c, a, b], DateTime(2026, 10, 22), DateTime(2026, 10, 22));
      expect([for (final i in idx[dayNumber(DateTime(2026, 10, 22))]!) i.id], ['a', 'c', 'b']);
    });

    test('별도 격리에서 계산한 결과가 같은 자리에서 계산한 것과 같다 (격리로 보낼 수 있다)', () async {
      final items = sample();
      final today = DateTime(2026, 10, 22);
      final input = WidgetPayloadInput(
        visible: items, today: today, spaceId: 's',
        colors: {for (final i in items) i.id: 0xFF123456},
        categories: {for (final i in items) i.id: '가족'},
        customDays: [CustomDay(id: 'c', date: DateTime(2026, 10, 25), name: '쉬는날')],
      );
      final inIsolate = await compute(buildWidgetPayload, input);
      final here = buildWidgetPayload(input);
      expect(inIsolate.agenda, here.agenda);
      expect(inIsolate.cellsJson, here.cellsJson);
      expect(inIsolate.days, here.days);
      expect(inIsolate.body, here.body);
      expect(inIsolate.agenda, contains('쉬는날')); // 사용자 지정 휴일도 격리 안에서 반영
      expect(inIsolate.agenda, contains('"color":${0xFF123456}'));
    });

    test('항목이 많아도 위젯 데이터 계산이 빠르다', () {
      final items = [...sample(), ...sample().map((i) => Item(
            id: 'z${i.id}', type: i.type, title: i.title, start: i.start, ownerUid: 'u', allDay: i.allDay, end: i.end, rule: i.rule, repeat: i.repeat,
            exceptions: i.exceptions, repeatUntil: i.repeatUntil))];
      for (var k = 0; k < 150; k++) {
        items.add(Item(id: 'm$k', type: ItemType.event, title: 'm', start: DateTime(2026, 1 + k % 12, 1 + k % 27, 9), ownerUid: 'u', allDay: false));
      }
      final sw = Stopwatch()..start();
      buildWidgetPayload(WidgetPayloadInput(
          visible: items, today: DateTime(2026, 10, 22), spaceId: 's', colors: const {}, categories: const {}, customDays: const []));
      // 예전 방식(날마다 모든 항목 검사)은 이 정도 양에서 수 초(JIT)가 걸렸다
      expect(sw.elapsedMilliseconds, lessThan(2500), reason: '${sw.elapsedMilliseconds}ms');
    });
  });
}

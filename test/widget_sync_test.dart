import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ourday/data/widget_sync.dart';
import 'package:ourday/models/item.dart';

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
    expect((days.first as Map)['kind'], 'today');
    expect((days.first as Map)['label'], startsWith('오늘 ·'));
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
    expect((days.first as Map)['date'], '2026-10-03');
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
}

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

  test('달력형: 일정이 있는 날만 yyyyMMdd로', () {
    final today = DateTime(2026, 10, 3);
    final days = WidgetSync.eventDays([ev('a', DateTime(2026, 10, 5)), ev('b', DateTime(2026, 11, 2))], today).split(',');
    expect(days, containsAll(['20261005', '20261102']));
    expect(days, isNot(contains('20261006')));
  });
}

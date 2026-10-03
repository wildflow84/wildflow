import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ourday/data/repository.dart';
import 'package:ourday/data/store.dart';
import 'package:provider/provider.dart';
import 'package:ourday/models/item.dart';
import 'package:ourday/ui/agenda.dart';

void main() {
  smoke();
  final it = Item(
      id: 'a', type: ItemType.event, title: '치과 예약', start: DateTime(2026, 10, 7), ownerUid: 'me',
      note: '스케일링 · 보험 확인', location: '오산 세교 치과', checklist: const [CheckEntry('신분증')]);

  test('검색: 제목/메모/위치/체크리스트, 대소문자 무시, 빈 검색어는 없음', () {
    expect(itemMatches(it, '치과'), true);
    expect(itemMatches(it, '스케일'), true);
    expect(itemMatches(it, '세교'), true);
    expect(itemMatches(it, '신분'), true);
    expect(itemMatches(it, '  치과 '), true);
    expect(itemMatches(it, '약국'), false);
    expect(itemMatches(it, ''), false);
    expect(itemMatches(it.copyWith(title: 'Dentist'), 'dENT'), true);
  });
}


void smoke() {
  testWidgets('목록 뷰/검색 화면이 오류 없이 그려진다', (t) async {
    await initializeDateFormatting('ko');
    final today = DateTime.now();
    final st = Store.preview(Repository(), uid: 'me', names: {'me': '나'}, items: [
      Item(id: '1', type: ItemType.event, title: '치과 예약', start: DateTime(today.year, today.month, today.day + 2, 10), allDay: false, ownerUid: 'me', location: '오산'),
      Item(id: '2', type: ItemType.todo, title: '장보기', start: DateTime(today.year, today.month, today.day), ownerUid: 'me', checklist: const [CheckEntry('우유')]),
    ]);
    Widget wrap(Widget w) => ChangeNotifierProvider<Store>.value(value: st, child: MaterialApp(home: Scaffold(body: w)));
    await t.pumpWidget(wrap(const AgendaView()));
    await t.pumpAndSettle();
    expect(find.text('치과 예약'), findsOneWidget);
    expect(find.text('장보기'), findsOneWidget);
    await t.pumpWidget(wrap(const SearchScreen()));
    await t.enterText(find.byType(TextField), '치과');
    await t.pumpAndSettle();
    expect(find.text('치과 예약'), findsOneWidget);
    expect(find.text('장보기'), findsNothing);
  });
}

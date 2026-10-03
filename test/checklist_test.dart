import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ourday/data/repository.dart';
import 'package:ourday/data/store.dart';
import 'package:ourday/models/item.dart';
import 'package:ourday/ui/checklist.dart';

Item _todo({List<CheckEntry> checklist = const []}) => Item(
    id: 'x', type: ItemType.todo, title: '장보기', start: DateTime(2026, 10, 3), ownerUid: 'me', checklist: checklist);

void main() {
  test('체크리스트 저장/복원, 진행도', () {
    final it = _todo(checklist: const [CheckEntry('우유'), CheckEntry('계란', done: true)]);
    expect(it.checksLeft, 1);
    final map = it.toMap();
    expect(map['checklist'], [
      {'t': '우유', 'd': false},
      {'t': '계란', 'd': true},
    ]);
    expect(CheckEntry.fromMap(Map<String, dynamic>.from((map['checklist'] as List)[1] as Map)), const CheckEntry('계란', done: true));
    expect(allChecked(it.checklist, true).every((c) => c.done), true);
    expect(it.copyWith(title: 'a').checklist.length, 2); // 다른 필드를 바꿔도 유지
  });

  test('이동형을 완료하면 다음 회차 체크리스트는 새로 시작', () {
    final it = Item(
        id: 'x', type: ItemType.todo, title: '약', start: DateTime(2026, 10, 3), ownerUid: 'me',
        rollEvery: 1, checklist: const [CheckEntry('아침', done: true), CheckEntry('저녁', done: true)]);
    final next = rollNextItem(it, DateTime(2026, 10, 3), 'me');
    expect(next.checklist.every((c) => !c.done), true);
    expect(next.checklist.length, 2);
  });

  test('toggleDone checkAll / setCheck', () async {
    final st = Store.preview(Repository(), uid: 'me', names: {'me': '나'}, items: [
      _todo(checklist: const [CheckEntry('a'), CheckEntry('b')]),
    ]);
    await st.setCheck(st.items.first, 0, true);
    expect(st.items.first.checklist[0].done, true);
    await st.toggleDone(st.items.first, DateTime(2026, 10, 3), checkAll: true);
    expect(st.items.first.done, true);
    expect(st.items.first.checklist.every((c) => c.done), true);
  });

  testWidgets('남은 체크가 있으면 확인창, 없으면 바로 통과', (t) async {
    late BuildContext ctx;
    await t.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    final none = await confirmIncompleteChecklist(ctx, _todo(checklist: const [CheckEntry('a', done: true)]));
    expect(none, CompleteChoice.anyway);

    CompleteChoice? got;
    final f = confirmIncompleteChecklist(ctx, _todo(checklist: const [CheckEntry('a'), CheckEntry('b')])).then((v) => got = v);
    await t.pumpAndSettle();
    expect(find.textContaining('2개'), findsOneWidget);
    await t.tap(find.text('모두 체크하고 완료'));
    await t.pumpAndSettle();
    await f;
    expect(got, CompleteChoice.checkAll);
  });

  testWidgets('편집기: 여러 줄 붙여넣기는 각각 한 항목, 체크/삭제', (t) async {
    List<CheckEntry> last = const [];
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: ChecklistEditor(initial: const [], onChanged: (l) => last = l))),
    ));
    await t.enterText(find.byType(TextField).last, '- 우유\n계란\n  \n• 빵');
    await t.pump();
    expect(last.map((c) => c.text).toList(), ['우유', '계란', '빵']);
    await t.tap(find.byType(Checkbox).first);
    await t.pump();
    expect(last.first.done, true);
    await t.tap(find.text('체크한 것 지우기'));
    await t.pump();
    expect(last.map((c) => c.text).toList(), ['계란', '빵']);
  });
}

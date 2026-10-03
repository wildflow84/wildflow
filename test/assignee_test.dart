import 'package:flutter_test/flutter_test.dart';
import 'package:ourday/models/item.dart';

Item _t({String assignee = '', String owner = 'me'}) =>
    Item(id: 'x', type: ItemType.todo, title: 't', start: DateTime(2026, 10, 3), ownerUid: owner, assignee: assignee);

void main() {
  test('담당자: 정해지면 그 사람 몫, 아니면 만든 사람 몫', () {
    expect(_t().isMineTo('me'), true);
    expect(_t().isMineTo('you'), false);
    expect(_t(assignee: 'you').isMineTo('you'), true);
    expect(_t(assignee: 'you').isMineTo('me'), false);
    expect(_t(owner: 'you').isMineTo('you'), true);
  });

  test('담당자 저장/복원/복사', () {
    final it = _t(assignee: 'you');
    expect(it.toMap()['assignee'], 'you');
    expect(it.copyWith(title: 'a').assignee, 'you');
    expect(Item.fresh(it).assignee, 'you');
    expect(it.copyWith(assignee: '').assignee, '');
  });

  test('구독 일정 표시는 수정해도 유지되고, 복제하면 사라진다', () {
    final it = Item(
        id: 'sub_x', type: ItemType.event, title: 'Arsenal v Everton', start: DateTime(2026, 10, 24), ownerUid: 'me',
        subscriptionId: 'abc');
    expect(it.copyWith(title: '수정').subscriptionId, 'abc');
    expect(it.toMap()['subscriptionId'], 'abc');
    expect(copyOfItem(it).subscriptionId, isNull);
  });
}

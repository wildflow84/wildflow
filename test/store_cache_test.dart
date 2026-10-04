import 'package:flutter_test/flutter_test.dart';
import 'package:ourday/data/repository.dart';
import 'package:ourday/data/store.dart';
import 'package:ourday/models/item.dart';

void main() {
  test('날짜별 목록은 상태가 안 바뀌면 같은 결과를 재사용하고, 바뀌면 다시 계산한다', () {
    final s = Store.preview(Repository(), uid: 'me', names: {'me': '나'}, items: [
      Item(id: 'a', type: ItemType.event, title: 'a', start: DateTime(2026, 10, 5), ownerUid: 'me'),
    ]);
    final d = DateTime(2026, 10, 5);
    final first = s.itemsOn(d);
    expect(identical(first, s.itemsOn(d)), isTrue);
    expect(first.length, 1);
    s.items = [...s.items, Item(id: 'b', type: ItemType.event, title: 'b', start: d, ownerUid: 'me')];
    s.notifyListeners();
    expect(s.itemsOn(d).length, 2);
  });
}

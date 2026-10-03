import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:ourday/data/repository.dart';
import 'package:ourday/data/store.dart';
import 'package:ourday/models/category.dart';
import 'package:ourday/models/item.dart' as m;
import 'package:ourday/models/item.dart' show Item, ItemType;

Store _store() => Store.preview(Repository(), uid: 'me', names: {'me': '나'}, items: []);

Item _item({List<String> categories = const ['default'], int? color}) => Item(
    id: 'x', type: ItemType.todo, title: 't', start: DateTime(2026, 10, 2), ownerUid: 'me',
    categories: categories, color: color);

void main() {
  test('항목 색 > 카테고리 색, 없는 카테고리는 첫 번째로 대체', () {
    final s = _store();
    s.categories = const [
      Category(id: 'a', name: 'A', colorValue: 0xFF111111),
      Category(id: 'b', name: 'B', colorValue: 0xFF222222),
    ];
    expect(s.colorOf(_item(categories: ['b'])), const Color(0xFF222222));
    expect(s.colorOf(_item(categories: ['b'], color: 0xFF333333)), const Color(0xFF333333));
    expect(s.colorOf(_item(categories: ['deleted'])), const Color(0xFF111111));
  });

  test('공개 범위: 카테고리 기본값 > 내 기본 설정', () {
    final s = _store();
    s.categories = const [
      Category(id: 'free', name: '자유', colorValue: 0xFF111111),
      Category(id: 'med', name: '약', colorValue: 0xFF222222, defaultVisibility: m.Visibility.private),
      Category(id: 'fam', name: '가족', colorValue: 0xFF333333, defaultVisibility: m.Visibility.shared),
    ];
    s.defaultVisibility = m.Visibility.shared;
    expect(s.visibilityFor(['free']), m.Visibility.shared);
    expect(s.visibilityFor(['med']), m.Visibility.private);
    s.defaultVisibility = m.Visibility.private;
    expect(s.visibilityFor(['free']), m.Visibility.private);
    expect(s.visibilityFor(['fam']), m.Visibility.shared);
  });

  test('다중 카테고리: 대표 색은 첫 번째, 삭제된 카테고리는 건너뜀', () {
    final s = _store();
    s.categories = const [
      Category(id: 'a', name: 'A', colorValue: 0xFF111111),
      Category(id: 'b', name: 'B', colorValue: 0xFF222222),
    ];
    final i = _item(categories: ['b', 'a']);
    expect(s.categoriesOf(i).map((c) => c.id), ['b', 'a']);
    expect(s.colorOf(i), const Color(0xFF222222));
    expect(s.categoriesOf(_item(categories: ['gone', 'a'])).map((c) => c.id), ['a']);
    expect(s.categoriesOf(_item(categories: ['gone'])).map((c) => c.id), ['a']);
  });

  test('다중 카테고리 공개 범위: 하나라도 나만이면 나만', () {
    final s = _store();
    s.categories = const [
      Category(id: 'med', name: '약', colorValue: 0xFF222222, defaultVisibility: m.Visibility.private),
      Category(id: 'fam', name: '가족', colorValue: 0xFF333333, defaultVisibility: m.Visibility.shared),
      Category(id: 'free', name: '자유', colorValue: 0xFF444444),
    ];
    s.defaultVisibility = m.Visibility.shared;
    expect(s.visibilityFor(['fam', 'med']), m.Visibility.private);
    expect(s.visibilityFor(['free', 'fam']), m.Visibility.shared);
    s.defaultVisibility = m.Visibility.private;
    expect(s.visibilityFor(['free']), m.Visibility.private);
  });

  test('이전 버전 항목(category 한 개)도 읽힌다 + 저장 시 호환 필드 유지', () {
    final i = _item(categories: ['x', 'y']);
    expect(i.toMap()['categories'], ['x', 'y']);
    expect(i.toMap()['category'], 'x');
  });

  test('Item 색 저장/해제', () {
    final i = _item(color: 0xFF123456);
    expect(i.toMap()['color'], 0xFF123456);
    expect(i.copyWith(clearColor: true).color, isNull);
    expect(i.copyWith(title: 'x').color, 0xFF123456);
  });

  test('기본 카테고리 id는 기존 항목과 호환 (default/work/family/money/travel/kid)', () {
    expect(defaultCategories.map((c) => c.id), ['default', 'work', 'family', 'money', 'travel', 'kid']);
  });

  test('닉네임: 저장하면 내 이름표와 만든 사람 표시가 바뀐다 (빈 값/너무 긴 값은 무시)', () async {
    final st = Store.preview(Repository(), uid: 'me', names: {'me': '구글이름', 'you': '상대'}, items: []);
    expect(st.ownerLabel(_item()), '구글이름');
    await st.setNickname('  대희아빠 ');
    expect(st.myNickname, '대희아빠');
    expect(st.ownerLabel(_item()), '대희아빠');
    await st.setNickname('   ');
    await st.setNickname('가' * (Store.maxNicknameLength + 1));
    expect(st.myNickname, '대희아빠');
    expect(st.names['you'], '상대');
  });

  test('카테고리 숨기기: 숨긴 카테고리 항목은 보이지 않고, 모두 보기로 되돌린다', () async {
    final a = Item(id: 'a', type: ItemType.todo, title: 'a', start: DateTime(2026, 10, 3), ownerUid: 'me', categories: const ['work']);
    final b = Item(id: 'b', type: ItemType.todo, title: 'b', start: DateTime(2026, 10, 3), ownerUid: 'me', categories: const ['family']);
    final st = Store.preview(Repository(), uid: 'me', names: {'me': '나'}, items: [a, b]);
    expect(st.visibleItems.length, 2);
    await st.setCategoryHidden('work', true);
    expect(st.hiddenCategories, {'work'});
    expect(st.visibleItems.map((i) => i.id), ['b']);
    await st.setCategoryHidden('family', true);
    expect(st.visibleItems, isEmpty);
    await st.setCategoryHidden('work', false);
    expect(st.visibleItems.map((i) => i.id), ['a']);
    await st.showAllCategories();
    expect(st.visibleItems.length, 2);
  });
}

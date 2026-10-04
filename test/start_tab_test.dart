import 'package:flutter_test/flutter_test.dart';
import 'package:ourday/data/repository.dart';
import 'package:ourday/data/store.dart';

void main() {
  Store make(Map<String, dynamic> profile) {
    final s = Store.preview(Repository(), uid: 'me', names: {'me': '나'}, items: []);
    s.profile = profile;
    return s;
  }

  test('시작 화면: 기본은 마지막으로 본 탭, 없으면 캘린더', () {
    expect(make({}).initialTab, 0);
    expect(make({'lastTab': 1}).initialTab, 1);
    expect(make({'lastTab': 9}).initialTab, 0);
  });

  test('시작 화면을 고정하면 마지막 탭과 상관없이 그 탭', () {
    expect(make({'startTab': 'list', 'lastTab': 2}).initialTab, 1);
    expect(make({'startTab': 'todo'}).initialTab, 2);
    expect(make({'startTab': 'calendar', 'lastTab': 1}).initialTab, 0);
    expect(make({'startTab': 'weird', 'lastTab': 2}).initialTab, 2);
  });
}

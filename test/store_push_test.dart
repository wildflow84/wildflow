import 'package:flutter_test/flutter_test.dart';
import 'package:ourday/data/repository.dart';
import 'package:ourday/data/store.dart';

void main() {
  test('알림 설정 기본값: 재촉/완료 알림 켜짐, 반복 완료 알림 꺼짐', () async {
    final st = Store.preview(Repository(), uid: 'me', names: {'me': '나', 'you': '상대'}, items: []);
    expect(st.allowNudge, true);
    expect(st.notifyComplete, true);
    expect(st.notifyCompleteRepeating, false);
    await st.setPref('allowNudge', false);
    await st.setPref('notifyCompleteRepeating', true);
    expect(st.allowNudge, false);
    expect(st.notifyCompleteRepeating, true);
  });
}

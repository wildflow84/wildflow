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

  test('방장은 members 맨 앞 사람, 내보낸 사람은 목록에서 빠진다', () {
    final st = Store.preview(Repository(), uid: 'me', names: {'me': '나', 'you': '상대'}, items: []);
    expect(st.isHost, false); // 구성원 정보가 아직 없을 때
    st.members = ['me', 'you'];
    expect(st.isHost, true);
    st.members = ['you', 'me'];
    expect(st.isHost, false);
  });
}

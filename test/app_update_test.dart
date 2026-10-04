import 'package:flutter_test/flutter_test.dart';
import 'package:ourday/data/app_update.dart';

void main() {
  final base = Uri.parse('https://x.web.app/');

  test('더 큰 빌드 번호만 새 버전으로 본다', () {
    const body = '{"build": 12, "version": "abc1234", "apk": "app/ourday.apk"}';
    final u = parseLatest(body, 11, base);
    expect(u?.build, 12);
    expect(u?.version, 'abc1234');
    expect(u?.apkUrl.toString(), 'https://x.web.app/app/ourday.apk');
    expect(parseLatest(body, 12, base), isNull);
    expect(parseLatest(body, 99, base), isNull);
  });

  test('깨지거나 빠진 정보는 업데이트 없음으로', () {
    expect(parseLatest('이상한 글', 1, base), isNull);
    expect(parseLatest('[]', 1, base), isNull);
    expect(parseLatest('{"build": 5}', 1, base), isNull);
    expect(parseLatest('{"apk": "a.apk"}', 1, base), isNull);
  });
}

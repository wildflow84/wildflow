# 안드로이드 앱 "앱 안에서 업데이트" 붙이는 법 (스토어 없이)

다른 앱에도 그대로 붙일 수 있게 정리했다. 원리는 단순하다.

1. CI가 빌드할 때마다 **APK 파일**과 **버전 정보(`latest.json`)** 를 아무 정적 호스팅에 올린다.
2. 앱이 켜질 때 `latest.json`을 읽어서, 지금 앱보다 번호가 크면 "새 버전이 나왔어" 창을 띄운다.
3. "업데이트"를 누르면 APK 주소를 브라우저로 열어 내려받고, 알림을 눌러 설치한다. 기존 앱 위에 덮어써지고 데이터는 유지된다.

## 꼭 지켜야 할 것
- **서명키가 항상 같아야 한다.** 다른 키로 서명한 APK는 덮어설치가 안 된다. (키를 CI에서 암호화해 저장소에 두고 재사용하는 방법은 `docs/REUSE.md` 참고)
- **빌드 번호(versionCode)가 계속 커져야 한다.** 우리는 `GITHUB_RUN_NUMBER`를 쓴다.
- 처음 한 번은 이 기능이 들어간 APK를 **수동으로 설치**해야 한다. 그 뒤부터 자동 안내가 뜬다.
- 폰이 처음 내려받을 때 "이 출처에서 앱 설치 허용"을 물어볼 수 있다 (한 번만 켜면 된다).
- 설치 단계의 "설치" 버튼 한 번은 안드로이드 정책상 피할 수 없다. 완전 자동은 구글 플레이 같은 스토어가 필요하다.

## 1. 호스팅 고르기 (APK와 latest.json을 올릴 곳)
| 방법 | 장점 | 주소 예 |
|---|---|---|
| **A. Firebase Hosting** (우리가 쓰는 방식) | 무료, CI에서 한 줄 배포 | `https://<프로젝트>.web.app/app/latest.json` |
| **B. GitHub Releases** | 호스팅 따로 필요 없음. 공개 저장소면 무료 | `https://github.com/<소유자>/<저장소>/releases/latest/download/latest.json` |
| **C. 아무 웹서버/S3** | 이미 서버가 있으면 | 자기 주소 |

APK는 보통 수십 MB다. 호스팅 용량과 전송량 한도를 확인한다.

## 2. CI에 넣을 것 (GitHub Actions)

### 빌드 단계: 번호를 넣어서 빌드
```yaml
- name: APK 빌드
  run: >
    flutter build apk --release
    --build-number=${GITHUB_RUN_NUMBER}
    --dart-define=APP_BUILD=${GITHUB_RUN_NUMBER}
    --dart-define=APP_VERSION=${GITHUB_SHA::7}
    --dart-define=UPDATE_BASE_URL=https://example.web.app/app/
```

### A. Firebase Hosting에 올리기
빌드된 웹 폴더(`public`으로 지정한 폴더) 안에 파일을 만들고 평소처럼 배포한다.
```yaml
- name: 앱 업데이트 파일 준비
  run: |
    mkdir -p build/web/app
    cp build/app/outputs/flutter-apk/app-release.apk build/web/app/app.apk
    printf '{"build":%s,"version":"%s","apk":"app.apk"}\n' "$GITHUB_RUN_NUMBER" "${GITHUB_SHA::7}" > build/web/app/latest.json
```
`firebase.json`의 `hosting.headers`에 아래를 넣는다. (APK가 브라우저에서 열리지 않고 내려받아지게, 그리고 버전 정보가 캐시되지 않게)
```json
{ "source": "/app/app.apk",
  "headers": [
    { "key": "Content-Type", "value": "application/vnd.android.package-archive" },
    { "key": "Content-Disposition", "value": "attachment; filename=\"app.apk\"" } ] },
{ "source": "/app/latest.json",
  "headers": [ { "key": "Cache-Control", "value": "no-cache" } ] }
```
Firebase Hosting이 SPA 규칙(`** → index.html`)을 쓰고 있어도 실제 파일이 있으면 그 파일이 먼저 나간다.

### B. GitHub Releases에 올리기
```yaml
- name: 릴리스 만들기
  env: { GH_TOKEN: "${{ github.token }}" }
  run: |
    printf '{"build":%s,"version":"%s","apk":"app-release.apk"}\n' "$GITHUB_RUN_NUMBER" "${GITHUB_SHA::7}" > latest.json
    gh release create "build-$GITHUB_RUN_NUMBER" --title "build $GITHUB_RUN_NUMBER" --notes "" \
      build/app/outputs/flutter-apk/app-release.apk latest.json
```
- 워크플로 권한에 `contents: write`가 필요하다.
- `releases/latest/download/…` 주소는 가장 최근 릴리스의 파일로 연결된다. 그러면 앱의 `UPDATE_BASE_URL`은 `https://github.com/<소유자>/<저장소>/releases/latest/download/`.
- 비공개 저장소는 APK를 로그인 없이 못 받으니 A나 C를 쓴다.

## 3. 앱에 넣을 코드

`pubspec.yaml`에 의존성 두 개:
```yaml
dependencies:
  http: ^1.6.0
  url_launcher: ^6.3.2
```

### `lib/app_update.dart`
```dart
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

class AppUpdate {
  final int build;
  final String version;
  final Uri apkUrl;
  const AppUpdate({required this.build, required this.version, required this.apkUrl});
}

/// latest.json 내용에서, 지금 앱([current] 빌드 번호)보다 새 버전이 있으면 그 정보를, 아니면 null.
AppUpdate? parseLatest(String body, int current, Uri base) {
  try {
    final m = jsonDecode(body);
    if (m is! Map) return null;
    final build = (m['build'] as num?)?.toInt();
    final apk = m['apk'] as String?;
    if (build == null || apk == null || apk.isEmpty || build <= current) return null;
    return AppUpdate(build: build, version: (m['version'] as String?) ?? '', apkUrl: base.resolve(apk));
  } catch (_) {
    return null;
  }
}

class UpdateChecker {
  /// CI가 넣는 값. 개발 빌드나 웹은 비어 있어서 업데이트 확인을 안 한다.
  static const currentBuild = int.fromEnvironment('APP_BUILD', defaultValue: 0);
  static const _baseUrl = String.fromEnvironment('UPDATE_BASE_URL');

  static bool get supported => !kIsWeb && currentBuild > 0 && _baseUrl.isNotEmpty;

  static Future<AppUpdate?> check() async {
    if (!supported) return null;
    try {
      final base = Uri.parse(_baseUrl);
      final res = await http.get(base.resolve('latest.json')).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      return parseLatest(utf8.decode(res.bodyBytes), currentBuild, base);
    } catch (_) {
      return null;
    }
  }
}
```

### `lib/update_dialog.dart`
```dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_update.dart';

bool _askedThisLaunch = false;

/// 앱을 켠 뒤 한 번만 새 버전을 확인하고, 있으면 안내한다. 첫 화면의 initState에서 post-frame으로 부른다.
Future<void> askUpdateOnce(BuildContext context) async {
  if (_askedThisLaunch || !UpdateChecker.supported) return;
  _askedThisLaunch = true;
  final u = await UpdateChecker.check();
  if (u != null && context.mounted) await showUpdateDialog(context, u);
}

Future<void> showUpdateDialog(BuildContext context, AppUpdate u) => showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('새 버전이 나왔어요'),
        content: Text('${u.version.isEmpty ? '' : '버전 ${u.version}\n\n'}'
            '업데이트를 누르면 앱 파일을 내려받아요. 받은 파일(알림)을 눌러 설치하면 기존 앱 위에 그대로 덮어써져요.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('나중에')),
          FilledButton(
            onPressed: () {
              launchUrl(u.apkUrl, mode: LaunchMode.externalApplication);
              Navigator.pop(ctx);
            },
            child: const Text('업데이트'),
          ),
        ],
      ),
    );

/// 설정 화면의 "업데이트 확인" 버튼에서 부른다.
Future<void> checkUpdateNow(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final u = await UpdateChecker.check();
  if (!context.mounted) return;
  if (u == null) {
    messenger.showSnackBar(const SnackBar(content: Text('지금이 최신 버전이에요')));
  } else {
    await showUpdateDialog(context, u);
  }
}
```

### 첫 화면에서 부르기
```dart
@override
void initState() {
  super.initState();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) askUpdateOnce(context);
  });
}
```

### 안드로이드 설정
- `AndroidManifest.xml`에 `INTERNET` 권한이 있어야 한다 (대부분 이미 있음).
- 브라우저로 내려받는 방식이라 `REQUEST_INSTALL_PACKAGES` 권한은 필요 없다.
- `android/app/build.gradle.kts`의 서명 설정(release 서명키)은 기존 그대로 쓰면 된다.

## 4. 단위 테스트 예 (선택)
```dart
test('더 큰 빌드 번호만 새 버전', () {
  final base = Uri.parse('https://x.web.app/app/');
  const body = '{"build": 12, "version": "abc1234", "apk": "app.apk"}';
  expect(parseLatest(body, 11, base)?.apkUrl.toString(), 'https://x.web.app/app/app.apk');
  expect(parseLatest(body, 12, base), isNull);
  expect(parseLatest('이상한 글', 1, base), isNull);
});
```

## 5. 확인 순서
1. 이 기능이 들어간 APK를 폰에 한 번 설치한다. (빌드 번호 N)
2. 코드를 조금 바꿔서 push → CI가 N+1을 올린다.
3. 폰에서 앱을 켜면 "새 버전이 나왔어요" 창이 뜬다 → 업데이트 → 설치.
4. 안 뜨면: `latest.json` 주소를 브라우저로 열어 번호가 보이는지, 앱을 빌드할 때 `UPDATE_BASE_URL`과 `APP_BUILD`를 넣었는지 확인한다.

## 6. 자주 막히는 곳
- 설치가 "앱이 설치되지 않았어요"로 실패 → 서명키가 다르거나, 빌드 번호가 같거나 작다.
- 창이 안 뜸 → `APP_BUILD`가 0(개발 빌드)이거나 주소 끝의 `/`가 빠졌다. `UPDATE_BASE_URL`은 `/`로 끝나야 한다.
- APK 주소가 브라우저에서 글자로 열림 → Content-Type/Content-Disposition 헤더를 확인한다 (A 방식).
- 문서(`*.md`)만 바꿨는데 새 버전 알림이 뜸 → 워크플로 `on.push.paths-ignore: ['docs/**', '**.md']`로 막는다.

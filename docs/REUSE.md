# 이 저장소를 다른 프로젝트에서 재사용하는 법

순대희 캘린더(Flutter + Firebase)를 만들면서 쌓은 배포 구조와 요령을 정리했다. 새 앱을 만들 때 그대로 가져다 쓰면 된다.
(비밀 값은 여기에 없다. 이름만 적는다.)

## 기본 정보
| 항목 | 값 |
|---|---|
| 저장소 | https://github.com/wildflow84/wildflow (공개 저장소) |
| 작업 브랜치 | `claude/calendar-todo-shared-app-xhpt7c` (push하면 자동 빌드/배포) |
| 앱 패키지명 | `com.wildflow.ourday` |
| Firebase 프로젝트 ID | `soondaehui` (웹: https://soondaehui.web.app) |
| 서버 함수 | Node 22, 리전 `asia-northeast3`, firebase-functions 7 / firebase-admin 14 |
| 앱 | Flutter(안드로이드 + 웹), Firestore/Auth/FCM/Functions |

## 폴더 지도
- `.github/workflows/build-deploy.yml` — 빌드·테스트·배포 전부 (핵심, 아래 참고)
- `config/firebase_public.json` — Firebase 웹/안드로이드 **공개** 키 (커밋해도 되는 값)
- `functions/` — 서버 함수(`index.js`), 순수 로직(`lib.js`), 테스트(`test.js`)
- `firestore.rules`, `firestore.indexes.json`, `firebase.json` — 보안 규칙/색인/호스팅 설정
- `android/` — 위젯, 백그라운드 작업, 서명키(`ourday.jks.enc`, 암호화본)
- `lib/` — 앱 코드, `test/` — 앱 테스트
- `TEST_CHECKLIST.md` — 사용자 확인 목록(확인하면 지움)

## GitHub 시크릿 (Settings → Secrets and variables → Actions)
| 이름 | 필수 | 용도 |
|---|---|---|
| `KEYSTORE_PASSPHRASE` | 필수 | 안드로이드 서명키 암호. **16자 이상** (저장소가 공개라 약하면 위험) |
| `FIREBASE_SERVICE_ACCOUNT` | 선택 | 서비스 계정 JSON 전체. 없으면 웹/함수 배포는 건너뜀 |
| `KAKAO_REST_KEY` | 선택 | 카카오 장소 검색/길찾기. 서버 함수 환경(`functions/.env`)으로만 들어감 |

## 새 프로젝트에 적용하는 순서
1. 이 저장소를 템플릿으로 복사하거나 `.github`, `config`, `functions`, `firebase.json`, `firestore.*`, `android/app/build.gradle.kts`를 가져간다.
2. Firebase 프로젝트를 새로 만들고 `config/firebase_public.json`을 새 값으로 바꾼다. 패키지명(`android/app/build.gradle.kts`, `AndroidManifest.xml`, 코틀린 패키지 폴더)과 서명키 별칭/파일 이름도 바꾼다.
3. GitHub 시크릿 2~3개를 등록한다.
4. Firebase 콘솔에 안드로이드 앱의 **SHA 지문**을 등록한다. 첫 빌드 로그(Actions 요약)에 SHA1/SHA256이 찍힌다.
5. push하면 CI가 알아서 빌드·배포한다. APK는 실행 결과의 Artifacts(`ourday-apk`)와 웹 호스팅(`/app/ourday.apk`)에 올라간다.

## 이 구조의 요령 (다른 프로젝트에서도 그대로 유효)
- **서명키는 암호화해서 저장소에 커밋**한다. 첫 실행에 새로 만들어 암호화·커밋하고, 이후엔 복호화해서 재사용한다. 키가 항상 같아야 APK를 덮어써서 업데이트할 수 있다. 암호를 잃으면 업데이트 불가이니 `KEYSTORE_PASSPHRASE`는 따로 보관한다.
- **빌드 번호**는 `GITHUB_RUN_NUMBER`를 `--build-number`와 `--dart-define=APP_BUILD`로 넘긴다. 앱이 `app/latest.json`과 비교해 "새 버전이 나왔어" 창을 띄운다 (스토어 없이 업데이트).
- **호출형 함수(onCall)는 Cloud Run 호출 권한을 열어야** 앱에서 부를 수 있다. 안 열면 401 `UNAUTHENTICATED`가 난다. 코드의 `invoker: 'public'`만으로는 안 되어서, CI 단계에서 `gcloud run services add-iam-policy-binding … --member=allUsers --role=roles/run.invoker`를 건다. 로그인 확인은 함수 안(`req.auth`)에서 한다.
- **서버 함수 배포는 웹 배포와 분리**하고 `continue-on-error`를 준다. 권한 문제로 함수가 실패해도 웹은 배포되고, 로그로 원인을 본다.
- **Firestore 쓰기는 `mergeFields`** 로 앱이 아는 필드만 덮어쓴다. 서버가 따로 쓰는 필드(재촉 횟수 등)가 지워지지 않는다. 반복 알림처럼 일부 필드만 갱신할 땐 `update`로 그 필드만 쓴다.
- **홈 화면 위젯**(안드로이드)은 `home_widget` 패키지 + `RemoteViews`. 규칙: 일반 `<View>` 대신 `ImageView`, 색은 `setColorFilter` + `setImageAlpha`, 목록 갱신은 `notifyAppWidgetViewDataChanged`. 백그라운드 완료/갱신은 `HomeWidgetBackgroundIntent`로 Flutter 콜백을 깨운다. 안드로이드 코드는 로컬에서 컴파일하지 못하니 CI로만 검증된다.
- **CI 동시 실행**은 `concurrency`로 줄 세운다 (`cancel-in-progress: false`). 함수 배포 결과를 놓치지 않으려는 것.
- 장시간 빌드(약 10분): APK 6~7분, 웹 1분, 함수 배포 1~2분.

## 주의
- 저장소가 **공개**다. 비밀 값(서비스 계정 JSON, 서명 암호, 카카오 REST 키)은 시크릿에만 둔다. 서명키 암호화본(`ourday.jks.enc`)은 커밋돼 있으니 암호가 약하면 안 된다.
- 웹 호스팅의 `/app/ourday.apk`는 주소를 아는 사람이면 내려받을 수 있다 (앱 데이터는 로그인해야 보인다).
- 서버 라이브러리 보안 경고(uuid, 중간 심각도 2건)는 간접 의존성이라 그대로 두었다.

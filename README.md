# 순대희 캘린더

대희 아빠 & 민아 전용 캘린더 + 할 일 앱. Flutter(Android + Web) / Firebase.

## 기능
- 월 달력 / 다가오는 일정 목록 / 할 일 탭, 검색, 카테고리별 보기, 일정·할 일 색상 카테고리
- 항목마다 **공유 / 프라이빗** (프라이빗은 Firestore 보안 규칙으로 서버에서 차단), 같이 보기 항목은 같이 편집
- 구글 캘린더식 반복(요일·매월 N일/n번째 요일/마지막 날·종료 조건), **음력 반복**(생일·기일), 이동형 반복(약 먹기), 반복 삭제·수정 범위 선택
- 체크리스트(반복 회차별), 담당자 지정, D-day·N주년, 위치(카카오 장소 검색, 위키백과 사진), 복제
- 푸시 알림: 일정 알림(정각~하루 전), 재촉(항목당 3번), 같이 하는 할 일 완료·새로 공유 알림 — 설정에서 각각 끌 수 있음
- 일정 구독(.ics 주소를 12시간마다 갱신: 아스날 경기 등)
- 닉네임, 구성원 관리(방장이 초대한 사람 내보내기/다시 받기)
- 안드로이드 홈화면 위젯 (오늘 일정/할 일), PC/폰 브라우저는 Flutter Web을 Firebase Hosting에 배포

## 달력 엔진 (오프라인, 먼 미래까지)
- **음력**: 1900~2049는 한국천문연구원(KASI) 공식 데이터, 2050~2200은 천문 계산(삭 + 24절기, 한국 표준시 기준)
  - 천문 계산법은 KASI와 **1913~2049년 일 단위 전수 대조에서 불일치 0일**일 때만 채택 (`tool/gen_calendar_data.py`)
  - 1900~1912년은 KASI가 옛 시헌력 자료를 써서 현대 계산으로는 재현되지 않으므로 KASI 표를 그대로 사용
- **공휴일**: 양력 고정 + 음력(설날/추석/부처님오신날) + **대체공휴일 규칙**(설·추석 2014, 어린이날 2014/2018, 광복·개천·한글날 2021, 삼일절 2022, 부처님오신날·성탄절 2023-05-04 시행) + 선거일/임시공휴일 목록
- **임시공휴일**: 선포되면 `lib/models/special_holidays.dart`에 추가 (앱의 "휴일/기념일 추가" 메뉴는 없앴다. 예전에 앱에서 넣은 휴일은 그대로 표시됨)
- **24절기**, 한식, 삼복(초/중/말복), 정월대보름·단오·칠석·백중·중양절, 어버이날 등 기념일
- 제약: 규칙으로 알 수 없는 임시공휴일·선거일은 선포 후 직접 추가해야 함. 2100년 이후 절기는 지구 자전 예측 오차로 자정 근처(±10분) 사례가 하루 달라질 수 있음(전체의 약 1%)
- 표 재생성: `pip install ephem korean-lunar-calendar && python3 tool/gen_calendar_data.py`
- 화면만 미리보기: `flutter run -d chrome -t lib/preview_main.dart` (Firebase 불필요)

## 구조
```
lib/models   Item, 반복 규칙(Recurrence), 음력·공휴일
lib/data     Repository(Firestore/Auth/서버 함수 호출), Store(상태), Push(알림), 장소 검색, WidgetSync(홈 위젯)
lib/ui       로그인 / 공간 설정 / 홈 / 편집 시트 / 설정 / 구독 / 구성원 등
functions/   서버 함수(Node 22, 서울 리전): nudge, notifyShared, notifyComplete, sendReminders(5분마다),
             syncSubscription·syncAllSubscriptions(12시간마다)·removeSubscription, removeMember·allowMember
android/.../OurDayWidget.kt   홈화면 위젯
firestore.rules / firestore.indexes.json   보안 규칙(공유·프라이빗·구성원)과 인덱스
tool/rules-test               보안 규칙 에뮬레이터 테스트(로컬)
TEST_CHECKLIST.md             대희 아빠가 직접 확인할 항목 목록
```

## 설정 (PC에 아무것도 설치하지 않고, 웹 브라우저만으로)
빌드와 배포는 GitHub Actions(`.github/workflows/build-deploy.yml`)가 한다. 이 저장소는 **공개**라서 설정값과 키는 전부 GitHub Secrets에 넣는다.

### 1. Firebase 프로젝트 (https://console.firebase.google.com)
1. 프로젝트 만들기 (Analytics는 꺼도 됨)
2. 빌드 → **Authentication** → 시작하기 → 로그인 방법 → **Google** 사용 설정
3. 빌드 → **Firestore Database** → 만들기 (프로덕션 모드, 위치 `asia-northeast3` 서울)
4. 빌드 → **Hosting** → 시작하기 (안내는 건너뛰고 활성화만)
5. 프로젝트 설정 → 내 앱 → **웹 앱 추가** (`</>`). 나오는 config 값을 메모
6. 프로젝트 설정 → 내 앱 → **Android 앱 추가**: 패키지 이름 `com.wildflow.ourday`. `google-services.json`은 받지 않아도 됨. 앱 ID(`1:...:android:...`)와 API 키를 메모
7. 프로젝트 설정 → **서비스 계정** → "새 비공개 키 생성" → 받은 JSON 파일 내용을 복사

### 2. GitHub Secrets (저장소 Settings → Secrets and variables → Actions)
Firebase 웹/Android 키·앱 ID는 공개 값이라 `config/firebase_public.json`에 커밋한다 (복붙 오류 방지). 진짜 비밀만 시크릿으로 둔다.

| 이름 | 값 |
|---|---|
| `KEYSTORE_PASSPHRASE` | 16자 이상 랜덤 문자열 (서명 키 암호. 따로 보관할 것) |
| `FIREBASE_SERVICE_ACCOUNT` | 7번의 서비스 계정 JSON 전체 |

```json
{
  "PROJECT_ID": "ourday-xxxx",
  "MESSAGING_SENDER_ID": "1234567890",
  "AUTH_DOMAIN": "ourday-xxxx.firebaseapp.com",
  "STORAGE_BUCKET": "ourday-xxxx.firebasestorage.app",
  "WEB_API_KEY": "AIza...",
  "WEB_APP_ID": "1:1234567890:web:abcdef",
  "ANDROID_API_KEY": "AIza...",
  "ANDROID_APP_ID": "1:1234567890:android:abcdef"
}
```

### 3. 빌드
`main`이나 `claude/**` 브랜치에 푸시되면 자동으로 돈다. Actions 탭에서 확인.
- 웹과 Firestore 보안 규칙이 Firebase에 자동 배포됨 (`https://<project>.web.app`)
- APK는 실행 결과의 **Artifacts → ourday-apk**에서 받음
- 첫 실행 때 서명 키가 만들어져 암호화된 채 저장소에 커밋되고, 실행 요약(Summary)에 SHA 지문이 나옴 → Firebase Android 앱의 **SHA 인증서 지문**에 등록

### 로컬에서 돌릴 때 (선택)
`firebase_config.json`을 위 JSON으로 만들고 `flutter run -d chrome --dart-define-from-file=firebase_config.json`

## 사용 순서
1. 대희 아빠가 Google 로그인 → "새 공간 만들기"
2. 메뉴 → "초대 코드 복사" → 카톡으로 민아에게 전달
3. 민아가 로그인 → 코드로 참여
4. 홈화면 길게 눌러 위젯 → 순대희 캘린더 추가

## TODO
- 음력 공휴일(설날/추석/부처님오신날), 생일 음력 반복
- 알림(FCM), 빠른 입력("내일 로또 구매")
- 위젯 체크 토글, 위젯 월 뷰

## 운영 메모
- 배포: `claude/**`나 `main`에 푸시하면 GitHub Actions가 분석·테스트 후 웹/APK 빌드, 호스팅·규칙·인덱스 배포, 서버 함수 배포(실패해도 웹 배포는 유지)를 한다. 설정 → 앱 버전이 최신 커밋 번호인지로 반영 여부를 확인.
- 테스트: `flutter test`(앱), `cd functions && npm test`(서버), 보안 규칙은 `tool/rules-test/README.md`.
- 키: Firebase·카카오 JavaScript 키는 도메인 제한된 공개 값이라 `config/firebase_public.json`에 둔다. 서비스 계정 키, 서명 키 비밀번호 등은 GitHub Secrets에만.
- 비용: Blaze(종량제). 무료 한도 안에서 쓰는 규모이고 Google Cloud에 예산 알림을 걸어두었다.

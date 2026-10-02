# 순대희 캘린더

대희 아빠 & 민아 전용 캘린더 + 할 일 앱. Flutter(Android + Web) / Firebase.

- 일정과 할 일을 한 화면에서 (월 뷰, 색상 카테고리, 체크 아이콘)
- 항목마다 **공유 / 프라이빗** 선택. 프라이빗은 Firestore 보안 규칙으로 서버에서 차단
- 반복(매일/매주/매월/매년), 멀티데이 일정, 양력 공휴일
- 안드로이드 홈화면 위젯 (오늘 일정/할 일)
- PC는 Flutter Web을 Firebase Hosting에 배포

## 달력 엔진 (오프라인, 먼 미래까지)
- **음력**: 1900~2049는 한국천문연구원(KASI) 공식 데이터, 2050~2200은 천문 계산(삭 + 24절기, 한국 표준시 기준)
  - 천문 계산법은 KASI와 **1913~2049년 일 단위 전수 대조에서 불일치 0일**일 때만 채택 (`tool/gen_calendar_data.py`)
  - 1900~1912년은 KASI가 옛 시헌력 자료를 써서 현대 계산으로는 재현되지 않으므로 KASI 표를 그대로 사용
- **공휴일**: 양력 고정 + 음력(설날/추석/부처님오신날) + **대체공휴일 규칙**(설·추석 2014, 어린이날 2014/2018, 광복·개천·한글날 2021, 삼일절 2022, 부처님오신날·성탄절 2023-05-04 시행) + 선거일/임시공휴일 목록
- **임시공휴일**: 앱에서 날짜를 눌러 "휴일 / 기념일 추가"로 넣으면 공유 공간에 저장되어 즉시 반영 (`lib/models/special_holidays.dart`에 영구 추가도 가능)
- **24절기**, 한식, 삼복(초/중/말복), 정월대보름·단오·칠석·백중·중양절, 어버이날 등 기념일
- 제약: 규칙으로 알 수 없는 임시공휴일·선거일은 선포 후 직접 추가해야 함. 2100년 이후 절기는 지구 자전 예측 오차로 자정 근처(±10분) 사례가 하루 달라질 수 있음(전체의 약 1%)
- 표 재생성: `pip install ephem korean-lunar-calendar && python3 tool/gen_calendar_data.py`
- 화면만 미리보기: `flutter run -d chrome -t lib/preview_main.dart` (Firebase 불필요)

## 구조
```
lib/models   Item, 반복 규칙(occursOn), 공휴일
lib/data     Repository(Firestore/Auth), Store(상태), WidgetSync(홈 위젯)
lib/ui       로그인 / 공간 설정 / 홈 / 편집 시트
android/.../OurDayWidget.kt   홈화면 위젯
firestore.rules               공유·프라이빗 보안 규칙
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
- 알림(FCM), 빠른 입력("내일 로또 구매"), 구글 캘린더 ICS 가져오기
- 위젯 체크 토글, 위젯 월 뷰

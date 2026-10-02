# OurDay

대희 아빠 & 민아 전용 캘린더 + 할 일 앱. Flutter(Android + Web) / Firebase.

- 일정과 할 일을 한 화면에서 (월 뷰, 색상 카테고리, 체크 아이콘)
- 항목마다 **공유 / 프라이빗** 선택. 프라이빗은 Firestore 보안 규칙으로 서버에서 차단
- 반복(매일/매주/매월/매년), 멀티데이 일정, 양력 공휴일
- 안드로이드 홈화면 위젯 (오늘 일정/할 일)
- PC는 Flutter Web을 Firebase Hosting에 배포

## 구조
```
lib/models   Item, 반복 규칙(occursOn), 공휴일
lib/data     Repository(Firestore/Auth), Store(상태), WidgetSync(홈 위젯)
lib/ui       로그인 / 공간 설정 / 홈 / 편집 시트
android/.../OurDayWidget.kt   홈화면 위젯
firestore.rules               공유·프라이빗 보안 규칙
```

## Firebase 설정 (최초 1회, 내 PC에서)
```bash
npm i -g firebase-tools && dart pub global activate flutterfire_cli
firebase login
firebase projects:create ourday-xxxx            # 또는 콘솔에서 생성
flutterfire configure --project=ourday-xxxx --platforms=android,web
```
`flutterfire configure`가 `lib/firebase_options.dart`를 만들고 `google-services.json`을 추가해줘.

콘솔에서 해야 할 것:
1. Authentication → 로그인 방법 → **Google** 사용 설정
2. Firestore Database 생성 (프로덕션 모드)
3. 안드로이드 로그인용 **SHA-1 지문** 등록: `cd android && ./gradlew signingReport`
   → Project settings → Android 앱에 추가 후 `flutterfire configure` 재실행

```bash
firebase deploy --only firestore:rules
```

## 실행
```bash
flutter run -d chrome          # PC 확인
flutter run                    # 안드로이드 기기
flutter build apk --release    # 민아 폰에 설치할 APK
flutter build web && firebase deploy --only hosting
```

## 사용 순서
1. 대희 아빠가 Google 로그인 → "새 공간 만들기"
2. 메뉴 → "초대 코드 복사" → 카톡으로 민아에게 전달
3. 민아가 로그인 → 코드로 참여
4. 홈화면 길게 눌러 위젯 → OurDay 추가

## TODO
- 음력 공휴일(설날/추석/부처님오신날), 생일 음력 반복
- 알림(FCM), 빠른 입력("내일 로또 구매"), 구글 캘린더 ICS 가져오기
- 위젯 체크 토글, 위젯 월 뷰

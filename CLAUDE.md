# 순대희 캘린더 (OurDay) — Claude 작업 안내

이 파일은 Claude 가 이 저장소에서 새로 작업을 시작할 때 읽는 프로젝트 기억이야. 대희 아빠 & 민아 전용 앱 (Flutter Android + Web / Firebase). 기능 설명은 `README.md`, 기능별 상세는 `docs/*.md`.

## 같이 일하는 방식
- 말투: **반말, 친구처럼 유머 있게.** 나는 "퀀텀", 사용자는 "대희 아빠". 사실 기반으로 말하고 가능하면 교차 검증한다. 모르는 건 모른다고 한다.
- **직접 해준다.** 사용자가 할 일은 꼭 필요한 것(비밀값 입력, 콘솔 클릭, 권한 승인)만 남기고, 클릭할 링크를 바로 준다. 같은 걸 다시 묻지 않는다.
- 새 기능을 넣을 때마다 `TEST_CHECKLIST.md`에 확인 항목을 추가하고, 사용자가 확인했다고 한 항목은 지운다.
- 말투(반말)와 위젯 카테고리 필터 동작은 사용자가 "그대로 두라"고 정했다. 바꾸지 않는다.
- 비밀값(토큰, 키)은 채팅/로그/커밋에 절대 남기지 않는다. 사용자가 터미널이나 시크릿 화면에 직접 넣게 안내한다. 보안에 영향 주는 IAM·공개 설정 변경은 사용자 허락을 받고 한다.

## 저장소와 배포
- 저장소 `wildflow84/wildflow` (공개), 작업 브랜치 `claude/calendar-todo-shared-app-xhpt7c`. 이 브랜치에 푸시하면 CI(`.github/workflows/build-deploy.yml`)가 analyze → 테스트 → APK/웹 빌드 → Firebase 배포(호스팅, 보안 규칙, 함수)를 한다. 보통 10~12분.
- `docs/**`, `**.md` 만 바뀐 푸시는 CI 를 건너뛴다. 코드 변경 없이 배포만 다시 돌리려면 workflow_dispatch(GitHub 도구의 `run_workflow`, ref = 위 브랜치).
- Firebase 프로젝트 `soondaehui`, 안드로이드 패키지 `com.wildflow.ourday`, 함수 리전 `asia-northeast3`, Node 22. 앱 내 업데이트는 `app/latest.json`의 빌드 번호(`GITHUB_RUN_NUMBER`)로 알린다 (`docs/IN_APP_UPDATE.md`).
- CI 결과는 GitHub 도구(`actions_list`, `get_job_logs`)로 확인한다. 로그는 job 이 끝난 뒤에만 읽힌다. "서버 함수 배포" 단계는 `continue-on-error` 라서 초록이어도 로그를 봐야 한다.

## 로컬 검증 (푸시 전에 꼭)
```
export PATH=/opt/flutter/bin:$PATH
flutter analyze lib test && flutter test        # 앱
cd functions && npm test                        # 서버 (node --test)
# 보안 규칙: tool/rules-test (에뮬레이터 포트 8085 설정 필요, README 참고)
```
안드로이드 Kotlin(`android/.../*.kt`, 위젯)은 로컬에서 컴파일할 수 없고 CI 에서만 확인된다.

## 구조 한눈에
- `lib/models` 항목·반복 규칙·음력·공휴일, `lib/data` Firestore/Store/위젯 동기화, `lib/ui` 화면, `lib/features` **달력 말고 붙이는 기능들**.
- **새 기능 추가**: 화면을 `lib/features/<기능>/` 에 만들고 `lib/features/feature_registry.dart` 의 `appFeatures` 에 한 줄 추가하면 홈 위 ⊞ "기능" 메뉴에 나타난다. 서버 쪽은 `functions/` 에 모듈 + `index.js` 에 연결 + 테스트.
- `functions/` : `lunar.js`, `recurrence.js`, `holidays.js`, `itemcalc.js` 는 앱의 Dart 계산(`lunar.dart`, `recurrence.dart`, `kr_calendar.dart`, `item.dart`)을 JS 로 옮긴 것이다. `functions/golden/golden.json` 은 Dart 가 만든 기준값이라 **앱의 반복/달력 규칙을 바꾸면 JS 와 기준값도 같이 고친다** (`test/recurrence_golden_test.dart`, `functions/digest.test.js`).
- 기능 문서: `docs/DAILY_DIGEST.md`(브리핑 자동화용 읽기 API), `docs/BRIEFING_DIGEST.md`(GitHub 저장소로 일정 요약 파일 기록), `docs/COUPONS.md`(쿠폰 판매), `docs/IN_APP_UPDATE.md`, `docs/REUSE.md`(다른 프로젝트 재사용 가이드).

## 겪고 알게 된 함정
- **호출형(onCall) 함수는 Cloud Run 앞단 호출 권한(allUsers invoker)이 비어 있으면 앱이 401 UNAUTHENTICATED.** CI 의 "호출형 함수 호출 권한 열기" 단계 목록에 새 callable 이름을 추가해야 한다 (인증은 함수 안에서 `req.auth` 로 한다).
- **공개 HTTPS 엔드포인트(`dailyDigest`)는 배포 직후 반드시 curl 로 "토큰 없음/틀린 토큰 → 401"을 확인한다.** 한 번 배포 직후 약 15분간 토큰 없이 응답한 적이 있고 원인은 못 찾았다 (코드는 로컬에서 401, `docs/DAILY_DIGEST.md` 참고). 확인 전에는 자동화에 연결하지 않는다.
- **시크릿(`DIGEST_TOKEN`, `GITHUB_TOKEN`, 번호 읽기용 Vision API 등)**: CI 배포 계정 `firebase-adminsdk-fbsvc@soondaehui.iam.gserviceaccount.com` 에 그 시크릿의 "보안 비밀 관리자 관리" 권한이 있어야 한다. 시크릿이 없거나 못 읽으면 CI 가 해당 함수만 빼고 배포한다 (`DIGEST_DISABLED`, `BRIEFING_DISABLED`).
- **Firestore 트리거 함수 첫 배포**는 Eventarc 권한 전파 때문에 한 번 실패할 수 있다. 몇 분 뒤 다시 배포하면 된다.
- Firestore 목록 구독은 `includeMetadataChanges: true` 여야 "서버와 맞춰짐"을 알 수 있다 (안 그러면 "서버와 안 맞춰졌어" 안내가 계속 뜬다).
- 위젯 데이터 계산은 날짜별 표(`WidgetSync.dayIndex`)로 한 번만 하고 별도 격리에서 돌린다. 날마다 모든 항목을 검사하는 방식으로 되돌리지 않는다 (예전엔 수 초).
- 달력형 위젯/목록형 위젯 데이터 형식은 `WidgetSync` 와 Kotlin(`OurDayWidget.kt`, `WidgetListService.kt`)이 짝이다. 한쪽만 바꾸면 안 된다.

## 지금 확인 대기 중인 것 (2026-10-29 기준)
- `TEST_CHECKLIST.md` 의 확인하지 않은 항목들 (위젯, 앱 켜는 속도, 쿠폰 판매, 공유 버튼 제거 등).
- 브리핑 파일(`calendar/digest.md`)의 첫 기록: Cloud Scheduler 에서 `firebase-schedule-dailyBriefingFile-asia-northeast3` 강제 실행 후 확인.
- 쿠폰 판매 실사용: 번호 읽기(Cloud Vision) 정확도, 스크린샷 저장, 판매 완료 전환.
- `dailyDigest` 를 자동화에 연결한 뒤 며칠간 무토큰 호출이 막히는지 지켜보기.

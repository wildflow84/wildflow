# 브리핑용 다이제스트 파일 기록

일정/할 일이 등록·수정·삭제될 때마다(그리고 매일 00:05 KST에), 가족 브리핑 저장소의 파일을 최신으로 다시 써주는 서버 기능이야.
브리핑 쪽은 이 파일을 **읽기만** 해. 앱 화면, 위젯, 기존 함수(`dailyDigest` 포함), `firestore.rules` 는 그대로야. (`functions/briefing.js`, `briefing_run.js`)

| 항목 | 값 |
|---|---|
| 저장소 / 브랜치 / 파일 | `wildflow84/family-portfolio` (private) / `calendar-digest` / `calendar/digest.md` |
| 방법 | GitHub Contents API (GET 으로 sha 확인 → PUT) |
| 함수 | `onItemWriteBriefing` (items 문서 생성·수정·삭제), `dailyBriefingFile` (매일 00:05 Asia/Seoul) |
| 시크릿 | `GITHUB_TOKEN` (fine-grained PAT) — 없으면 아무것도 하지 않아 |

## 동작

- **공유(shared) 항목만** 써. 나만 보기(private)는 소유자가 누구든 쓰지 않아 (`functions/briefing.test.js` 의 "private 항목은 어떤 경우에도 파일에 나오지 않는다").
- 반복/음력/이동형 반복/멀티데이/제외 날짜/종료일은 `dailyDigest` 가 쓰는 계산(앱의 `occursOn` 과 같은 JS 이식)을 그대로 써.
- 변경이 연달아 오면 마지막 것만 45초 뒤에 한 번 기록해 (디바운스). 알림 시각만 바뀐 수정이나 나만 보기끼리의 수정은 아예 건너뛰어.
- 본문(날짜 섹션 전체)이 이전과 **달라졌을 때만** `revision` 을 +1 하고 커밋해. 시각(`generated_at`)만 바뀌는 재생성은 파일을 다시 커밋하지 않아.
- sha 충돌(409)이면 최신 파일을 다시 읽어 재시도 (최대 3번).
- 실패해도 앱에는 영향이 없어. 오류 코드만 로그에 남기고, 토큰과 응답 본문은 남기지 않아.

## 파일 형식

```
# OURDAY CALENDAR DIGEST
revision: 12
generated_at: 2026-10-22T08:00:00+09:00
scope: shared-only
days: 14

## 2026-10-22 (목)
- [H] 공휴일/명절/사용자 지정일 이름
- [E] 18:30-19:00 | 제목 | 대희아빠 | 장소
- [T] ~15:00 | 제목 | 민아 | 지남

## 2026-10-23 (금)
(항목 없음)
```

- 오늘(KST)부터 14일치 모두. `[E]` 시간은 `HH:MM-HH:MM`, `HH:MM`, `종일` (여러 날 시각 일정은 첫날만 시각, 나머지 날은 종일).
- `[T]` 시간은 `~HH:MM` 또는 `종일`, 상태는 `지남`(마감이 지난 미완료, **오늘 섹션**에만) / `완료` / 빈칸.
- 소유자·담당자는 이름표에서 공백을 뺀 이름(`민아`, `대희아빠`). 할 일은 담당자가 있으면 담당자, 없으면 만든 사람. 알 수 없으면 `공통`.
- 필드 구분은 ` | `. 제목·장소의 `|` 는 `/` 로, 줄바꿈은 공백으로 바꿔.

## 설정 (대희 아빠가 직접)

### 1) GitHub 토큰(PAT) 만들기
1. GitHub → Settings → Developer settings → Personal access tokens → **Fine-grained tokens** → Generate new token.
2. **Repository access → Only select repositories** 에서 `wildflow84/family-portfolio` 하나만 골라.
3. **Repository permissions → Contents: Read and write** 만 켜 (나머지는 그대로 No access). 만료일은 길게(예: 1년) 잡고 생성 → 토큰은 한 번만 보이니 바로 아래 2)에 입력해.

### 2) 시크릿 저장과 배포
토큰은 **터미널에 직접 입력**해. 채팅/메모/커밋에 붙여넣지 마.

```bash
firebase functions:secrets:set GITHUB_TOKEN --project soondaehui   # 값을 물어보면 토큰을 붙여넣고 엔터
firebase deploy --only functions --project soondaehui
```

- 시크릿은 브라우저(Google Cloud → Secret Manager → 보안 비밀 만들기, 이름 `GITHUB_TOKEN`)로 만들어도 돼. 그러면 배포는 이 저장소의 CI 가 해줘 (Actions → build-deploy 에서 최근 실행을 다시 돌리거나 새로 푸시).
- CI 로 배포하려면 `firebase-adminsdk-fbsvc@soondaehui.iam.gserviceaccount.com` 에 **이 시크릿의 "보안 비밀 관리자 관리(Secret Manager Admin)"** 권한을 줘야 해 (`DIGEST_TOKEN` 때 한 것과 같은 방법: 시크릿 → 권한 → 액세스 권한 부여). 그 권한이 없으면 CI 는 이 두 함수만 빼고 배포해.
- 첫 배포 때 Firestore 트리거(Eventarc) 권한이 아직 준비 중이라는 오류가 나면 몇 분 뒤 한 번 더 배포하면 돼.

### 3) 확인
`calendar-digest` 브랜치의 `calendar/digest.md` 가 `revision: 1` 이상으로 바뀌고, 앱에서 공유 일정을 하나 추가하면 1분쯤 뒤 `revision` 이 오르는지 봐. 같은 내용이면 커밋이 생기지 않아.

## 보안 주의

- 토큰은 저장소 하나, Contents 읽기/쓰기만 가진 것으로 만들어. 노출되면 GitHub 에서 토큰을 지우고 새로 만든 뒤 `firebase functions:secrets:set GITHUB_TOKEN` 으로 교체하고 다시 배포해.
- 파일에는 **공유 항목의 제목·장소·시간**이 들어가. 저장소가 private 인 걸 유지해.
- `serverState/briefing` 문서(디바운스용)는 서버만 읽고 써. `firestore.rules` 에 규칙이 없어서 앱에서는 접근할 수 없어.

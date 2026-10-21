# 오늘의 요약 (dailyDigest)

다른 서비스(가족 아침 브리핑 자동화)가 하루 한 번 불러서, 한 구성원(예: 민아)의 **오늘 일정과 할 일**만 받아가는 읽기 전용 주소야.
앱 화면, 위젯, 다른 함수, `firestore.rules` 는 그대로고 이 함수만 새로 생겼어. (`functions/digest.js`)

## 한눈에

| 항목 | 값 |
|---|---|
| 주소 | `https://asia-northeast3-soondaehui.cloudfunctions.net/dailyDigest` (배포하면 터미널에도 주소가 찍혀) |
| 방식 | `GET` 만 (다른 메서드는 405) |
| 인증 | `Authorization: Bearer <DIGEST_TOKEN>` 헤더. 쿼리스트링으로는 안 받아 |
| 시크릿 이름 | `DIGEST_TOKEN` (Firebase 시크릿) |
| 쿼리 | `member` (필수: 이름표 예 `민아`, 또는 uid) · `date` (선택: `yyyy-MM-dd`, 없으면 한국시간 오늘) |

## 배포 (대희 아빠가 직접)

토큰은 길고 랜덤한 문자열로 만들어서 **터미널에 직접 입력**해. 채팅/메모/커밋에 붙여넣지 마.

```bash
# 1) 토큰 만들기 (화면에 보이는 값을 복사해 두거나, 아래 3)처럼 바로 환경변수에 담아도 돼)
openssl rand -base64 36

# 2) 시크릿 저장: 실행하면 값을 물어봐. 위 토큰을 붙여넣고 엔터 (값은 화면에 안 보여)
firebase functions:secrets:set DIGEST_TOKEN --project soondaehui

# 3) 배포
firebase deploy --only functions:dailyDigest --project soondaehui
```

> 이 저장소의 CI 는 `DIGEST_TOKEN` 시크릿이 없으면 이 함수만 빼고 나머지를 배포해. 위 순서대로 한 번 하고 나면 이후 CI 배포에도 같이 올라가.

## 호출 예시

토큰은 환경변수로만 써 (명령 기록에 값이 남지 않게 `read -s` 로 받는 걸 추천):

```bash
read -rs DIGEST_TOKEN; export DIGEST_TOKEN        # 토큰 붙여넣고 엔터
curl -sS -H "Authorization: Bearer $DIGEST_TOKEN" \
  "https://asia-northeast3-soondaehui.cloudfunctions.net/dailyDigest?member=%EB%AF%BC%EC%95%84"
# 날짜를 정해서:  ...dailyDigest?member=%EB%AF%BC%EC%95%84&date=2026-10-21
```

`curl -G --data-urlencode "member=민아"` 처럼 쓰면 한글을 직접 쓸 수 있어.

## 응답 예시

```json
{
  "date": "2026-09-25",
  "member": "민아",
  "holidays": ["추석"],
  "events": [
    {"id": "a1", "title": "시댁 식사", "allDay": false, "time": "12:00–14:00", "location": "수원",
     "categories": ["가족"], "ownerName": "대희 아빠", "subscription": false}
  ],
  "todos": [
    {"id": "b2", "title": "송편 주문", "time": null, "done": false, "overdue": true,
     "assigneeName": "민아", "ownerName": "대희 아빠", "checklistLeft": 2, "dday": "D+1", "categories": ["일반"]}
  ]
}
```

- `holidays`: 그날의 공휴일(대체공휴일 포함), 설날·추석 같은 명절, 이 공간에서 추가한 날 이름.
- `events`: 그날 나타나는 같이 보기 일정 (멀티데이, 반복 규칙, 음력 반복, 예외·종료일 반영). 구독(.ics) 일정은 `subscription: true`.
- `todos`: 대상 구성원 몫(담당자가 있으면 담당자, 없으면 만든 사람)의 할 일. 그날 마감인 것과 마감이 지났는데 미완료인 것(`overdue: true`). 이동형 반복은 문서에 들어 있는 다음 1회만 나와. 반복 할 일의 완료는 그날이 `doneDates` 에 있는지로 판단해 (앱과 같음). `time` 은 마감 시각(`~15:00`).
- 정렬: 종일 먼저, 그다음 시각순. 메모, 사진 주소, 좌표, 체크리스트 본문은 응답에 없어.

| 상태 | 뜻 |
|---|---|
| 200 | 정상 |
| 400 | `member` 없음, `date` 형식 오류, 또는 구성원이 여러 공간/이름에 걸쳐 있음 (uid 로 지정) |
| 401 | 토큰이 없거나 달라 |
| 404 | 구성원을 못 찾음 |
| 405 | GET 이 아님 |

## 프라이버시

- **`visibility == 'shared'` 인 항목만** 돌려줘. 나만 보기(private)는 소유자가 `member` 본인이어도 응답에 안 들어가. 읽는 쿼리부터 shared 만 가져오고, 만드는 쪽에서 한 번 더 걸러. (`functions/digest.test.js` 의 "private 항목은 어떤 경우에도 나오지 않는다")
- 응답은 `Cache-Control: no-store`, CORS 는 열지 않아 (브라우저에서 부르는 용도가 아니야).
- 토큰과 요청 헤더는 로그에 남기지 않아.

## 보안 주의 / 토큰이 새면

주소는 인터넷에서 열려 있고 **토큰이 열쇠**야. 토큰이 있으면 우리 집 shared 일정·할 일이 보여.

1. 새 토큰을 만들어 시크릿을 교체해: `firebase functions:secrets:set DIGEST_TOKEN --project soondaehui` (새 값 입력)
2. 다시 배포해야 새 값이 적용돼: `firebase deploy --only functions:dailyDigest --project soondaehui`
3. 호출하는 쪽의 토큰도 새 값으로 바꿔.
4. 옛 버전 정리 (선택): `firebase functions:secrets:destroy DIGEST_TOKEN@<옛 버전 번호> --project soondaehui` (`firebase functions:secrets:get DIGEST_TOKEN` 으로 버전 확인)

토큰이 소스, 설정 파일, 채팅에 들어가지 않게 조심해. 호출하는 서비스의 비밀 저장소(시크릿 매니저 등)에만 넣어.

## 앱과 같은 결과를 내는 방법

반복/음력/공휴일 계산은 앱의 Dart 코드를 그대로 옮겼어 (`functions/lunar.js`, `recurrence.js`, `holidays.js`, `itemcalc.js`).
`functions/golden/golden.json` 은 **Dart 코드가 만든 기준값**(반복 규칙 25가지의 5년치 발생일, 2012~2034 공휴일, 음력 표본)이고, `digest.test.js` 가 JS 결과와 하나씩 비교해.
음력 표(`functions/lunar_table.js`)는 `python3 tool/gen_functions_lunar.py` 로 앱의 표에서 다시 만들 수 있어. 앱의 반복/달력 규칙을 바꾸면 이 JS 쪽과 기준값도 같이 고쳐야 해.

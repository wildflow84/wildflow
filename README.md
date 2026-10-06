# 퀀텀 모닝 브리핑

매일 07:00(KST)에 Claude + 웹검색으로 마켓 브리핑을 만들어 카카오톡(요약+전문 링크)과 텔레그램(전문)으로 보낸다.
프롬프트는 `briefing/prompt.md` 에서 수정. 전문은 `briefings/YYYY-MM-DD.md` 에 누적.

## 세팅 (최초 1회)
GitHub 레포 → Settings → Secrets and variables → Actions 에 등록:

| Secret | 설명 |
|---|---|
| `ANTHROPIC_API_KEY` | 필수. console.anthropic.com |
| `KAKAO_REST_API_KEY` | 카카오 개발자 앱의 REST API 키 |
| `KAKAO_REFRESH_TOKEN` | 아래 절차로 발급 |
| `KAKAO_CLIENT_SECRET` | 앱에서 Client Secret을 켰을 때만 |
| `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID` | 선택. @BotFather로 봇 생성 후 |

### 카카오 토큰 발급
1. developers.kakao.com → 애플리케이션 추가 → 카카오 로그인 활성화
2. Redirect URI에 `https://example.com/oauth` 등록, 동의항목에서 **카카오톡 메시지 전송(talk_message)** 설정
3. `KAKAO_REST_API_KEY=<키> python briefing/kakao.py auth` 실행 → 안내대로 진행 → 출력된 refresh token을 Secret으로 등록

> 카톡 "나에게 보내기"는 메시지당 200자 제한이라 요약만 보내고 전문은 링크로 연결한다.
> 리프레시 토큰은 60일 유효, 갱신되면 워크플로 로그에 경고가 뜬다. 전송 실패 시 Actions가 실패 처리돼 GitHub 메일로 알려준다.
> 크론은 **기본 브랜치**에 머지돼야 동작한다. Actions 탭 → morning-briefing → Run workflow 로 수동 실행(=/브리핑) 가능.

## 로컬 테스트
`pip install -r requirements.txt && ANTHROPIC_API_KEY=... python briefing/main.py` (시크릿 없으면 콘솔 출력)

"""매일 아침 마켓 브리핑 생성 + 메신저 전송."""
import os
import sys
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import anthropic

import kakao
import telegram

ROOT = Path(__file__).resolve().parent.parent
MODEL = os.environ.get("BRIEFING_MODEL", "claude-sonnet-5-5")
SPLIT = "===SUMMARY==="
WEEKDAYS = "월화수목금토일"


def generate(now: datetime) -> str:
    client = anthropic.Anthropic()
    system = (Path(__file__).parent / "prompt.md").read_text(encoding="utf-8")
    user = (
        f"오늘은 {now:%Y년 %-m월 %-d일} {WEEKDAYS[now.weekday()]}요일 {now:%H:%M} (KST)이야. "
        "웹 검색으로 최신 수치를 확인해서 브리핑해줘."
    )
    messages = [{"role": "user", "content": user}]
    tools = [{"type": "web_search_20250305", "name": "web_search", "max_uses": 20}]
    for _ in range(5):  # 서버 툴 루프가 pause_turn으로 끊기면 이어서 진행
        resp = client.messages.create(
            model=MODEL, max_tokens=8000, system=system, tools=tools, messages=messages
        )
        if resp.stop_reason != "pause_turn":
            break
        messages += [{"role": "assistant", "content": resp.content}]
    text = "".join(b.text for b in resp.content if b.type == "text").strip()
    if not text:
        raise RuntimeError("빈 응답")
    return text


def main() -> int:
    now = datetime.now(ZoneInfo("Asia/Seoul"))
    full = generate(now)
    body, _, summary = full.partition(SPLIT)
    body, summary = body.strip(), summary.strip()
    if not summary:
        summary = f"마켓 모닝 브리핑 {now:%-m/%-d}({WEEKDAYS[now.weekday()]}) 도착!"

    out = ROOT / "briefings" / f"{now:%Y-%m-%d}.md"
    out.write_text(body + "\n", encoding="utf-8")
    print(f"saved {out}")

    repo = os.environ.get("GITHUB_REPOSITORY")
    ref = os.environ.get("GITHUB_REF_NAME", "main")
    link = (
        f"{os.environ.get('GITHUB_SERVER_URL', 'https://github.com')}/{repo}/blob/{ref}/briefings/{out.name}"
        if repo
        else "https://github.com"
    )

    failed = False
    if os.environ.get("KAKAO_REFRESH_TOKEN"):
        try:
            kakao.send_memo(summary, link)
            print("kakao sent")
        except Exception as e:  # noqa: BLE001
            print(f"::error::카카오 전송 실패: {e}")
            failed = True
    if telegram.configured():
        try:
            telegram.send(body)
            print("telegram sent")
        except Exception as e:  # noqa: BLE001
            print(f"::error::텔레그램 전송 실패: {e}")
            failed = True
    if not os.environ.get("KAKAO_REFRESH_TOKEN") and not telegram.configured():
        print(body)  # 로컬 테스트용
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())

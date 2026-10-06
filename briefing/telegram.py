"""텔레그램 전송 (전문이 길어서 카톡보다 읽기 편함). 시크릿이 없으면 건너뜀."""
import os

import requests

LIMIT = 4000


def configured() -> bool:
    return bool(os.environ.get("TELEGRAM_BOT_TOKEN") and os.environ.get("TELEGRAM_CHAT_ID"))


def send(text: str) -> None:
    url = f"https://api.telegram.org/bot{os.environ['TELEGRAM_BOT_TOKEN']}/sendMessage"
    chunks, cur = [], ""
    for line in text.splitlines(keepends=True):
        if len(cur) + len(line) > LIMIT:
            chunks.append(cur)
            cur = ""
        cur += line
    if cur:
        chunks.append(cur)
    for c in chunks:
        r = requests.post(
            url,
            data={"chat_id": os.environ["TELEGRAM_CHAT_ID"], "text": c, "disable_web_page_preview": "true"},
            timeout=30,
        )
        r.raise_for_status()

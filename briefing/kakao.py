"""카카오톡 '나에게 보내기' 유틸 + 최초 토큰 발급 도우미.

최초 1회 토큰 발급:
  KAKAO_REST_API_KEY=... python briefing/kakao.py auth
"""
import json
import os
import sys

import requests

AUTH_URL = "https://kauth.kakao.com/oauth/authorize"
TOKEN_URL = "https://kauth.kakao.com/oauth/token"
MEMO_URL = "https://kapi.kakao.com/v2/api/talk/memo/default/send"
REDIRECT_URI = "https://example.com/oauth"  # 카카오 개발자 콘솔 Redirect URI와 동일해야 함


def _client_params() -> dict:
    p = {"client_id": os.environ["KAKAO_REST_API_KEY"]}
    if os.environ.get("KAKAO_CLIENT_SECRET"):
        p["client_secret"] = os.environ["KAKAO_CLIENT_SECRET"]
    return p


def refresh_access_token() -> str:
    r = requests.post(
        TOKEN_URL,
        data={
            "grant_type": "refresh_token",
            "refresh_token": os.environ["KAKAO_REFRESH_TOKEN"],
            **_client_params(),
        },
        timeout=30,
    )
    r.raise_for_status()
    body = r.json()
    if body.get("refresh_token"):
        # 만료 1개월 미만일 때만 새 리프레시 토큰이 내려온다. (유효기간 60일)
        print(
            "::warning::카카오 리프레시 토큰이 갱신됐어. "
            "GitHub Secret KAKAO_REFRESH_TOKEN을 새 값으로 교체해줘 (값은 로그에 안 찍음)."
        )
        with open(os.environ.get("KAKAO_NEW_TOKEN_FILE", "/dev/null"), "w") as f:
            f.write(body["refresh_token"])
    return body["access_token"]


def send_memo(text: str, link_url: str) -> None:
    """text는 최대 200자. link_url은 전문 보기 버튼."""
    token = refresh_access_token()
    template = {
        "object_type": "text",
        "text": text[:200],
        "link": {"web_url": link_url, "mobile_web_url": link_url},
        "button_title": "전문 보기",
    }
    r = requests.post(
        MEMO_URL,
        headers={"Authorization": f"Bearer {token}"},
        data={"template_object": json.dumps(template, ensure_ascii=False)},
        timeout=30,
    )
    r.raise_for_status()


def _auth_helper() -> None:
    key = os.environ["KAKAO_REST_API_KEY"]
    print("1) 브라우저에서 아래 URL 열고 로그인/동의:\n")
    print(f"{AUTH_URL}?client_id={key}&redirect_uri={REDIRECT_URI}&response_type=code&scope=talk_message\n")
    code = input("2) 이동된 주소창의 code= 값 붙여넣기: ").strip()
    r = requests.post(
        TOKEN_URL,
        data={
            "grant_type": "authorization_code",
            "redirect_uri": REDIRECT_URI,
            "code": code,
            **_client_params(),
        },
        timeout=30,
    )
    r.raise_for_status()
    print("\nKAKAO_REFRESH_TOKEN =", r.json()["refresh_token"])


if __name__ == "__main__":
    if sys.argv[1:] == ["auth"]:
        _auth_helper()
    else:
        print(__doc__)

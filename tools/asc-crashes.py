#!/usr/bin/env python3
"""TestFlight のクラッシュ報告を App Store Connect API から取り出す。

鍵さえ置いてあれば、追加のインストールは要らない（署名は openssl に任せる）。

    python3 tools/asc-crashes.py                 # 直近のクラッシュ報告を一覧
    python3 tools/asc-crashes.py --save /tmp/crash   # .ips も保存する

鍵の置き場所と識別子は、次のいずれかで渡す。

    ~/private_keys/AuthKey_<KEYID>.p8          （ファイル名から KEYID を読む）
    ~/private_keys/asc-config.json             {"keyId": "...", "issuerId": "..."}
    環境変数 ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH

Issuer ID は App Store Connect の「ユーザーとアクセス ＞ 各種統合 ＞
App Store Connect API」の上部に出ている UUID。
"""

from __future__ import annotations

import argparse
import base64
import glob
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

API = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = "com.non-migi.RailAngyerApp"
KEY_DIR = os.path.expanduser("~/private_keys")


# ---------------------------------------------------------------- 鍵と署名

def find_key() -> tuple[str, str, str]:
    """鍵ファイル・Key ID・Issuer ID を集める"""
    key_path = os.environ.get("ASC_KEY_PATH")
    key_id = os.environ.get("ASC_KEY_ID")
    issuer_id = os.environ.get("ASC_ISSUER_ID")

    config_path = os.path.join(KEY_DIR, "asc-config.json")
    if os.path.exists(config_path):
        config = json.load(open(config_path))
        key_id = key_id or config.get("keyId")
        issuer_id = issuer_id or config.get("issuerId")
        key_path = key_path or config.get("keyPath")

    if not key_path:
        candidates = sorted(glob.glob(os.path.join(KEY_DIR, "AuthKey_*.p8")))
        if not candidates:
            sys.exit(f"鍵が見つかりません。{KEY_DIR}/AuthKey_<KEYID>.p8 を置いてください。\n"
                     "作り方は files/15_TestFlight準備.md の「クラッシュ報告を見る」を参照。")
        if len(candidates) > 1:
            sys.exit("鍵が複数あります。ASC_KEY_PATH でどれを使うか指定してください:\n  "
                     + "\n  ".join(candidates))
        key_path = candidates[0]

    if not key_id:
        # AuthKey_ABC123XYZ.p8 → ABC123XYZ
        base = os.path.basename(key_path)
        key_id = base.removeprefix("AuthKey_").removesuffix(".p8")

    if not issuer_id:
        sys.exit("Issuer ID が分かりません。次のどちらかで渡してください。\n"
                 f"  1) {config_path} に {{\"issuerId\": \"...\"}} を書く\n"
                 "  2) 環境変数 ASC_ISSUER_ID に入れる")

    return key_path, key_id, issuer_id


def b64url(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def der_to_raw(signature: bytes) -> bytes:
    """openssl が返す DER 署名を、JWT が求める R||S（各32バイト）に直す"""
    if signature[0] != 0x30:
        raise ValueError("DER の並びではありません")
    index = 2 if signature[1] < 0x80 else 3      # 長さが2バイトになることがある

    values = []
    for _ in range(2):
        if signature[index] != 0x02:
            raise ValueError("INTEGER が見つかりません")
        length = signature[index + 1]
        value = signature[index + 2: index + 2 + length]
        values.append(value.lstrip(b"\x00").rjust(32, b"\x00"))
        index += 2 + length
    return values[0] + values[1]


def make_token(key_path: str, key_id: str, issuer_id: str) -> str:
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    payload = {
        "iss": issuer_id,
        "iat": int(time.time()),
        "exp": int(time.time()) + 20 * 60,       # 20分。上限はAppleの規定で20分
        "aud": "appstoreconnect-v1",
    }
    signing_input = (b64url(json.dumps(header, separators=(",", ":")).encode()) + "."
                     + b64url(json.dumps(payload, separators=(",", ":")).encode()))

    result = subprocess.run(["openssl", "dgst", "-sha256", "-sign", key_path],
                            input=signing_input.encode(), capture_output=True)
    if result.returncode != 0:
        sys.exit(f"署名に失敗しました:\n{result.stderr.decode()}")

    return signing_input + "." + b64url(der_to_raw(result.stdout))


# ---------------------------------------------------------------- API 呼び出し

def get(path: str, token: str) -> dict:
    url = path if path.startswith("http") else API + path
    request = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        body = error.read().decode(errors="replace")
        raise SystemExit(f"APIが {error.code} を返しました: {url}\n{body}")


def app_id(token: str) -> str:
    data = get(f"/v1/apps?filter[bundleId]={BUNDLE_ID}", token)
    if not data.get("data"):
        sys.exit(f"{BUNDLE_ID} のAppが見つかりません。鍵の権限（Appのアクセス）を確かめてください。")
    return data["data"][0]["id"]


def crash_submissions(token: str, app: str, limit: int) -> list[dict]:
    # `/v1/betaFeedbackCrashSubmissions` 単体は GET_COLLECTION を許していない（403）。
    # **App からの関連として取りにいく**のが正しい形
    return get(f"/v1/apps/{app}/betaFeedbackCrashSubmissions"
               f"?sort=-createdDate&limit={limit}", token).get("data", [])


def describe(entry: dict) -> str:
    a = entry.get("attributes", {})
    parts = [a.get("createdDate", "日時不明"),
             a.get("deviceModel", "端末不明"),
             f"iOS {a.get('osVersion', '?')}"]
    if a.get("appUptimeInMilliseconds"):
        parts.append(f"起動から {a['appUptimeInMilliseconds'] // 1000} 秒")
    if a.get("comment"):
        parts.append(f"コメント: {a['comment']}")
    return "  ".join(str(p) for p in parts)


def save_log(entry: dict, token: str, directory: str) -> str | None:
    """クラッシュログ本体を保存する。

    本体は **`betaCrashLogs.logText` に文字列で入っている**（ダウンロードURLではない）。
    """
    related = (entry.get("relationships", {}).get("crashLog", {})
                    .get("links", {}).get("related"))
    if not related:
        return None

    log = get(related, token).get("data")
    text = (log or {}).get("attributes", {}).get("logText")
    if not text:
        return None

    os.makedirs(directory, exist_ok=True)
    path = os.path.join(directory, f"{entry['id']}.ips")
    with open(path, "w") as file:
        file.write(text)
    return path


def crashed_frames(path: str, limit: int = 8) -> list[str]:
    """落ちたスレッドのうち、アプリ自身のフレームだけを抜き出す"""
    lines = open(path).read().split("\n")
    try:
        start = next(i for i, line in enumerate(lines) if "Crashed:" in line)
    except StopIteration:
        return []
    frames = [line.strip() for line in lines[start + 1: start + 60]
              if "RailAngyerApp" in line]
    return frames[:limit]


def main() -> None:
    parser = argparse.ArgumentParser(description="TestFlight のクラッシュ報告を取り出す")
    parser.add_argument("--limit", type=int, default=20, help="取得する件数（既定20）")
    parser.add_argument("--save", metavar="DIR", help="クラッシュログ(.ips)の保存先")
    args = parser.parse_args()

    token = make_token(*find_key())
    app = app_id(token)
    entries = crash_submissions(token, app, args.limit)

    if not entries:
        print("クラッシュ報告はまだ届いていません。")
        print("TestFlightの「フィードバックを送信」からの報告と、端末の解析共有の設定が要ります。")
        return

    print(f"{len(entries)} 件のクラッシュ報告:")
    for entry in entries:
        print(" -", describe(entry))
        if args.save:
            path = save_log(entry, token, args.save)
            if not path:
                print("   ログ: （本体は取得できず。端末の解析データを共有してもらう）")
                continue
            print("   ログ:", path)
            for frame in crashed_frames(path):
                print("     ", frame)


if __name__ == "__main__":
    main()

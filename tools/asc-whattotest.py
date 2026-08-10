#!/usr/bin/env python3
"""TestFlight の「テスト内容（What to Test）」を App Store Connect へ登録する。

    python3 tools/asc-whattotest.py 6                     # ビルド6に既定の文面を登録
    python3 tools/asc-whattotest.py 6 --file path/to.txt  # 文面を指定する
    python3 tools/asc-whattotest.py 6 --show              # いま登録されている文面を見る

既定の文面は `RailAngyerApp/TestFlight/ja-JP/WhatToTest.txt`。

**アップロードしただけでは、テスターに「何を試せばいいか」が出ない。**
Xcode からの送信では文面が付かないので、ここで入れる。

App Store Connect が `ja` のローカライズを自動で作っていることがあるため、
無ければ POST、あれば PATCH する（どちらでも同じ結果になるようにしてある）。

鍵の置き場所は `asc-crashes.py` と同じ（`~/private_keys/AuthKey_<KEYID>.p8`）。
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
import sys
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DEFAULT_TEXT = os.path.join(ROOT, "RailAngyerApp", "TestFlight", "ja-JP", "WhatToTest.txt")
LOCALE = "ja"
# App Store Connect の上限。超えると 409 で弾かれるので、送る前に見る
MAX_LENGTH = 4000


def load_asc():
    """鍵の扱いとJWTの組み立ては `asc-crashes.py` のものを使い回す"""
    path = os.path.join(HERE, "asc-crashes.py")
    spec = importlib.util.spec_from_file_location("asc_crashes", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def send(method: str, path: str, token: str, body: dict) -> dict:
    request = urllib.request.Request(
        path if path.startswith("http") else "https://api.appstoreconnect.apple.com" + path,
        data=json.dumps(body).encode(),
        method=method,
        headers={"Authorization": f"Bearer {token}",
                 "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        raise SystemExit(f"APIが {error.code} を返しました: {path}\n"
                         f"{error.read().decode(errors='replace')}")


def find_build(asc, token: str, app: str, version: str) -> str:
    """ビルド番号（`CFBundleVersion`）から、APIのビルドIDを引く。

    このAppは `sort` を許していないので、全件から突き合わせる（数十件なので十分）"""
    data = asc.get(f"/v1/apps/{app}/builds?limit=200", token)
    for build in data.get("data", []):
        if build["attributes"].get("version") == version:
            return build["id"]
    known = ", ".join(sorted(b["attributes"].get("version", "?")
                             for b in data.get("data", [])))
    sys.exit(f"ビルド {version} が見つかりません。届いているのは: {known}\n"
             "アップロード直後は数分かかります。処理が終わってから実行してください。")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("build", help="ビルド番号（例: 6）")
    parser.add_argument("--file", default=DEFAULT_TEXT, help="登録する文面のファイル")
    parser.add_argument("--show", action="store_true", help="登録せず、いまの文面を見るだけ")
    args = parser.parse_args()

    asc = load_asc()
    key_path, key_id, issuer_id = asc.find_key()
    token = asc.make_token(key_path, key_id, issuer_id)
    build_id = find_build(asc, token, asc.app_id(token), args.build)

    existing = asc.get(f"/v1/builds/{build_id}/betaBuildLocalizations", token).get("data", [])
    mine = next((row for row in existing
                 if row["attributes"].get("locale") == LOCALE), None)

    if args.show:
        if not mine:
            print(f"ビルド {args.build} に {LOCALE} のテスト内容はまだありません。")
            return
        print(mine["attributes"].get("whatsNew") or "（空）")
        return

    text = open(args.file, encoding="utf-8").read().strip()
    if not text:
        sys.exit(f"文面が空です: {args.file}")
    if len(text) > MAX_LENGTH:
        sys.exit(f"文面が長すぎます（{len(text)} 文字 / 上限 {MAX_LENGTH}）: {args.file}")

    if mine:
        send("PATCH", f"/v1/betaBuildLocalizations/{mine['id']}", token,
             {"data": {"id": mine["id"], "type": "betaBuildLocalizations",
                       "attributes": {"whatsNew": text}}})
        print(f"ビルド {args.build} の {LOCALE} を書き換えました（{len(text)} 文字）")
    else:
        send("POST", "/v1/betaBuildLocalizations", token,
             {"data": {"type": "betaBuildLocalizations",
                       "attributes": {"locale": LOCALE, "whatsNew": text},
                       "relationships": {"build": {"data": {"type": "builds",
                                                            "id": build_id}}}}})
        print(f"ビルド {args.build} に {LOCALE} を登録しました（{len(text)} 文字）")


if __name__ == "__main__":
    main()

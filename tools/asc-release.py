#!/usr/bin/env python3
"""App Store Connect のリリース項目を、リポジトリの文面から流し込む。

    python3 tools/asc-release.py --show          # いま入っている内容を見る
    python3 tools/asc-release.py --push          # 文面を送る（説明・キーワード・URL）
    python3 tools/asc-release.py --push --build 15   # ビルドも紐づける

**毎回ブラウザで打ち直さないための道具。** 文面の正はリポジトリ側
（`RailAngyerApp/AppStore/ja/*.txt`）に置き、ここから送る。
食い違ったらリポジトリが正しい。

送れるもの / 送れないもの
------------------------
送れる  : 説明、キーワード、宣伝用テキスト、サポートURL、プライバシーURL、
          リリースノート、審査連絡先、年齢制限、ビルドの紐づけ
送れない: **有料Appの契約、口座と税務情報、価格の設定、スクリーンショットの中身、
          「Appのプライバシー」の申告** — これらは人がブラウザで入れる（§`15_TestFlight準備.md`）

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
COPY_DIR = os.path.join(ROOT, "RailAngyerApp", "AppStore", "ja")
LOCALE = "ja"

# App Store Connect 側の上限。超えると 409 で弾かれるので、送る前に見る
LIMITS = {"description": 4000, "keywords": 100, "promotionalText": 170, "whatsNew": 4000}


def load_asc():
    """鍵の扱いとJWTの組み立ては `asc-crashes.py` のものを使い回す"""
    spec = importlib.util.spec_from_file_location(
        "asc_crashes", os.path.join(HERE, "asc-crashes.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def send(method: str, path: str, token: str, body: dict) -> dict:
    request = urllib.request.Request(
        "https://api.appstoreconnect.apple.com" + path,
        data=json.dumps(body).encode(), method=method,
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        raise SystemExit(f"APIが {error.code} を返しました: {method} {path}\n"
                         f"{error.read().decode(errors='replace')}")


def text(name: str) -> str | None:
    """文面を読む。無ければ触らない（消さない）"""
    path = os.path.join(COPY_DIR, f"{name}.txt")
    if not os.path.exists(path):
        return None
    value = open(path, encoding="utf-8").read().strip()
    return value or None


def check_limits(fields: dict) -> None:
    for key, value in fields.items():
        limit = LIMITS.get(key)
        if limit and value and len(value) > limit:
            sys.exit(f"{key} が長すぎます（{len(value)} 文字 / 上限 {limit}）")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--show", action="store_true", help="いまの内容を見るだけ")
    parser.add_argument("--push", action="store_true", help="文面を送る")
    parser.add_argument("--build", help="紐づけるビルド番号（例: 15）")
    args = parser.parse_args()
    if not (args.show or args.push):
        parser.error("--show か --push を指定してください")

    asc = load_asc()
    key_path, key_id, issuer_id = asc.find_key()
    token = asc.make_token(key_path, key_id, issuer_id)
    app = asc.app_id(token)

    versions = asc.get(f"/v1/apps/{app}/appStoreVersions?limit=20", token)["data"]
    if not versions:
        sys.exit("編集できるバージョンがありません。App Store Connect でバージョンを作ってください。")
    version = versions[0]
    version_id = version["id"]
    print(f"バージョン {version['attributes']['versionString']}"
          f"（{version['attributes']['appStoreState']}）")

    # **初回リリースではリリースノートを編集できない**（「新しくなったこと」が無いため）。
    # 送ろうとすると 409 STATE_ERROR で全体が弾かれるので、先に外す
    released = {"READY_FOR_SALE", "PENDING_DEVELOPER_RELEASE", "PROCESSING_FOR_APP_STORE",
                "IN_REVIEW", "WAITING_FOR_REVIEW", "REPLACED_WITH_NEW_VERSION"}
    is_first_release = not any(v["attributes"].get("appStoreState") in released
                               for v in versions[1:])

    info_id = asc.get(f"/v1/apps/{app}/appInfos", token)["data"][0]["id"]
    version_loc = asc.get(f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations",
                          token)["data"]
    version_loc = next((row for row in version_loc
                        if row["attributes"]["locale"] == LOCALE), None)
    if version_loc is None:
        sys.exit(f"{LOCALE} のローカライズがありません。")

    if args.show:
        show(asc, token, version_loc, info_id, version_id)
        return

    fields = {
        "description": text("description"),
        "keywords": text("keywords"),
        "promotionalText": text("promotional"),
        "whatsNew": text("whats-new"),
        "supportUrl": text("support-url"),
        "marketingUrl": text("support-url"),
    }
    fields = {k: v for k, v in fields.items() if v}
    if is_first_release and "whatsNew" in fields:
        del fields["whatsNew"]
        print("  ※ 初回リリースなのでリリースノートは送りません（編集できません）")
    check_limits(fields)

    send("PATCH", f"/v1/appStoreVersionLocalizations/{version_loc['id']}", token,
         {"data": {"id": version_loc["id"], "type": "appStoreVersionLocalizations",
                   "attributes": fields}})
    print("説明・キーワード・URL・リリースノートを送りました:")
    for key, value in fields.items():
        print(f"  {key}: {len(value)} 文字")

    if privacy := text("privacy-url"):
        # プライバシーポリシーのURLは App情報 側（版ではない）
        loc = asc.get(f"/v1/appInfos/{info_id}/appInfoLocalizations", token)["data"]
        loc = next((row for row in loc if row["attributes"]["locale"] == LOCALE), None)
        if loc:
            send("PATCH", f"/v1/appInfoLocalizations/{loc['id']}", token,
                 {"data": {"id": loc["id"], "type": "appInfoLocalizations",
                           "attributes": {"privacyPolicyUrl": privacy}}})
            print(f"  privacyPolicyUrl: {privacy}")

    if args.build:
        attach_build(asc, token, app, version_id, args.build)


def attach_build(asc, token: str, app: str, version_id: str, number: str) -> None:
    builds = asc.get(f"/v1/apps/{app}/builds?limit=200", token)["data"]
    build = next((b for b in builds if b["attributes"].get("version") == number), None)
    if build is None:
        known = ", ".join(sorted(b["attributes"].get("version", "?") for b in builds))
        sys.exit(f"ビルド {number} が見つかりません。届いているのは: {known}")

    send("PATCH", f"/v1/appStoreVersions/{version_id}/relationships/build", token,
         {"data": {"id": build["id"], "type": "builds"}})
    print(f"ビルド {number} を紐づけました")


def show(asc, token: str, version_loc: dict, info_id: str, version_id: str) -> None:
    attributes = version_loc["attributes"]
    print("\n--- いま入っている内容 ---")
    for key in ["description", "keywords", "promotionalText", "whatsNew",
                "supportUrl", "marketingUrl"]:
        value = attributes.get(key)
        head = (value or "（空）").replace("\n", " ")[:60]
        print(f"  {key}: {head}")

    loc = asc.get(f"/v1/appInfos/{info_id}/appInfoLocalizations", token)["data"]
    loc = next((row for row in loc if row["attributes"]["locale"] == LOCALE), None)
    if loc:
        print(f"  privacyPolicyUrl: {loc['attributes'].get('privacyPolicyUrl') or '（空）'}")

    try:
        build = asc.get(f"/v1/appStoreVersions/{version_id}/build", token).get("data")
        print(f"  紐づけたビルド: {build['attributes']['version'] if build else '（無し）'}")
    except SystemExit:
        print("  紐づけたビルド: （取得できず）")


if __name__ == "__main__":
    main()

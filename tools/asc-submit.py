#!/usr/bin/env python3
"""App Store の審査提出まわりを、ブラウザを開かずに進める。

    python3 tools/asc-submit.py --show                 # 申請に足りないものを並べる
    python3 tools/asc-submit.py --screenshots <dir>    # スクリーンショットを入れ替える
    python3 tools/asc-submit.py --submit               # 審査へ出す
    ... --yes                                          # 付けるまでは何も送らない（下記）

**既定は「送らない」。** `--yes` を付けたときだけ実際に書き込む。
App Store の申請は取り消しに手間がかかるので、まず何が送られるかを見せる。

文面（説明・キーワード・URL・リリースノート）とビルドの紐づけは
`asc-release.py` の担当。こちらは**その後**、スクリーンショットと提出を受け持つ。

自動化できないもの（人がブラウザで入れるしかない）
--------------------------------------------------
- **「Appのプライバシー」の申告**。API に口が無い
  （`/v1/apps/{id}/appPrivacyDetails` は 404 `The relationship does not exist`）
- **契約・銀行口座・税務情報**（有料App契約。無料アプリなら不要）
- スクリーンショットの**中身**（アップロードは自動化できる。絵は作る必要がある）

鍵の置き場所は `asc-crashes.py` と同じ（`~/private_keys/AuthKey_<KEYID>.p8`）。
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import sys
import urllib.error
import urllib.request

API = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = "com.non-migi.RailAngyerApp"
PLATFORM = "IOS"

# 6.7インチ（1290×2796）を1組入れれば、App Store Connect が小さい端末ぶんへ縮めて使う。
#
# **`APP_IPHONE_69` は API が受け取らない**（2026-08 時点。POST すると 409 で
# 「有効な値は…」と一覧を返してくる。iPhone では 67 がいちばん大きい）。
# 撮るのは 6.9インチのシミュレータでよく、`shoot-screenshots.sh` が
# 1290×2796 に直してから渡す
DISPLAY_TYPE = "APP_IPHONE_67"
SCREENSHOT_SIZE = (1290, 2796)


def load_asc():
    """JWT の作り方と鍵の探し方は asc-crashes.py に一本化してある"""
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "asc-crashes.py")
    spec = importlib.util.spec_from_file_location("asc", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def request(method: str, path: str, token: str, body: dict | None = None,
            raw: bytes | None = None, headers: dict | None = None,
            authorize: bool = True) -> dict:
    url = path if path.startswith("http") else API + path
    data = raw if raw is not None else (json.dumps(body).encode() if body else None)
    # **絵の実体を置きに行く先には Bearer を付けない。** 置き場は Apple の
    # 署名付きURL（AWS 形式）で、余計な Authorization を足すと署名と食い違って 400 になる
    head = {"Authorization": f"Bearer {token}"} if authorize else {}
    if body is not None:
        head["Content-Type"] = "application/json"
    head.update(headers or {})
    req = urllib.request.Request(url, data=data, headers=head, method=method)
    try:
        with urllib.request.urlopen(req, timeout=120) as response:
            text = response.read().decode()
            return json.loads(text) if text else {}
    except urllib.error.HTTPError as error:
        detail = error.read().decode()
        try:
            first = json.loads(detail)["errors"][0]
            detail = f'{first.get("title", "")} — {first.get("detail", "")}'
        except Exception:
            detail = detail[:400]
        raise SystemExit(f"APIが {error.code} を返しました（{method} {path}）\n{detail}")


def get(path: str, token: str) -> dict:
    return request("GET", path, token)


def app_id(token: str) -> str:
    data = get(f"/v1/apps?filter[bundleId]={BUNDLE_ID}", token).get("data", [])
    if not data:
        raise SystemExit(f"アプリが見つかりません: {BUNDLE_ID}")
    return data[0]["id"]


def editable_version(token: str, app: str) -> dict:
    """いま編集できる（＝まだ出していない）バージョン"""
    versions = get(f"/v1/apps/{app}/appStoreVersions?limit=10", token).get("data", [])
    for version in versions:
        state = version["attributes"].get("appVersionState")
        if state in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED",
                     "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"):
            return version
    if versions:
        return versions[0]
    raise SystemExit("バージョンがありません。App Store Connect で作ってください")


def localizations(token: str, version_id: str) -> list[dict]:
    return get(f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations",
               token).get("data", [])


def screenshot_sets(token: str, localization_id: str) -> list[dict]:
    return get(f"/v1/appStoreVersionLocalizations/{localization_id}/appScreenshotSets",
               token).get("data", [])


def screenshots(token: str, set_id: str) -> list[dict]:
    return get(f"/v1/appScreenshotSets/{set_id}/appScreenshots", token).get("data", [])


# --- 見る ------------------------------------------------------------------

def show(token: str, app: str) -> None:
    version = editable_version(token, app)
    attributes = version["attributes"]
    print(f"アプリ: {BUNDLE_ID}（{app}）")
    print(f"バージョン: {attributes.get('versionString')} / "
          f"状態: {attributes.get('appVersionState')} / "
          f"公開の仕方: {attributes.get('releaseType')}")

    blockers: list[str] = []

    build = get(f"/v1/appStoreVersions/{version['id']}/build", token).get("data")
    latest = get(f"/v1/builds?filter[app]={app}&sort=-version&limit=1",
                 token).get("data", [])
    newest = latest[0]["attributes"].get("version") if latest else None
    if build:
        attached = build["attributes"].get("version")
        print(f"ビルド: {attached}（{build['attributes'].get('uploadedDate')}）"
              f"{'' if attached == newest else f' ← 最新は {newest}'}")
        # **古いビルドのまま出すのがいちばん怖い。** 出したあとで気づいても、
        # 審査を取り下げて出し直すことになる
        if newest and attached != newest:
            blockers.append(f"ビルドを {newest} に付け替える"
                            f"（asc-release.py --push --build {newest}）")
    else:
        print(f"ビルド: **未紐づけ**（最新は {newest}）")
        blockers.append(f"ビルドを紐づける（asc-release.py --push --build {newest}）")

    for localization in localizations(token, version["id"]):
        locale = localization["attributes"]["locale"]
        has_description = bool(localization["attributes"].get("description"))
        print(f"文面[{locale}]: 説明{'あり' if has_description else '**なし**'}")
        if not has_description:
            blockers.append(f"{locale} の説明を入れる（asc-release.py --push）")

        found = False
        for shot_set in screenshot_sets(token, localization["id"]):
            kind = shot_set["attributes"]["screenshotDisplayType"]
            count = len(screenshots(token, shot_set["id"]))
            print(f"  スクリーンショット[{kind}]: {count}枚")
            if kind == DISPLAY_TYPE and count > 0:
                found = True
        if not found:
            print(f"  スクリーンショット[{DISPLAY_TYPE}]: **なし**")
            blockers.append(f"{locale} に {DISPLAY_TYPE}（1320×2868）を1枚以上入れる"
                            "（--screenshots <dir>）")

    info = get(f"/v1/apps/{app}/appInfos", token).get("data", [])
    if info:
        rating = get(f"/v1/appInfos/{info[0]['id']}/ageRatingDeclaration",
                     token).get("data")
        answered = sum(1 for value in (rating or {}).get("attributes", {}).values()
                       if value not in (None, ""))
        print(f"年齢レーティング: {answered}項目に回答済み")
        if answered == 0:
            blockers.append("年齢レーティングに回答する（asc-release.py が扱える）")

    submissions = get(f"/v1/reviewSubmissions?filter[app]={app}&limit=5",
                      token).get("data", [])
    if submissions:
        for submission in submissions:
            print(f"審査提出: {submission['attributes'].get('state')}"
                  f"（{submission['id']}）")
    else:
        print("審査提出: まだ無し")

    print("\n--- 人がブラウザで入れるもの（APIに口が無い）---")
    print("・「Appのプライバシー」の申告")
    print("・契約／銀行口座／税務情報（無料アプリなら不要）")

    if blockers:
        print("\n--- 出す前に足りないもの ---")
        for line in blockers:
            print(f"・{line}")
    else:
        print("\n足りないものは見つかりませんでした。--submit で出せます")


# --- スクリーンショット ------------------------------------------------------

def ensure_set(token: str, localization_id: str, apply: bool) -> str | None:
    for shot_set in screenshot_sets(token, localization_id):
        if shot_set["attributes"]["screenshotDisplayType"] == DISPLAY_TYPE:
            return shot_set["id"]
    if not apply:
        print(f"  （作る）スクリーンショットの枠 {DISPLAY_TYPE}")
        return None
    body = {"data": {"type": "appScreenshotSets",
                     "attributes": {"screenshotDisplayType": DISPLAY_TYPE},
                     "relationships": {"appStoreVersionLocalization": {
                         "data": {"type": "appStoreVersionLocalizations",
                                  "id": localization_id}}}}}
    return request("POST", "/v1/appScreenshotSets", token, body)["data"]["id"]


def upload_screenshots(token: str, app: str, directory: str, apply: bool) -> None:
    files = sorted(f for f in os.listdir(directory)
                   if f.lower().endswith((".png", ".jpg", ".jpeg")))
    if not files:
        raise SystemExit(f"画像がありません: {directory}")
    if len(files) > 10:
        raise SystemExit(f"1つの枠に入れられるのは10枚までです（{len(files)}枚あります）")

    version = editable_version(token, app)
    for localization in localizations(token, version["id"]):
        locale = localization["attributes"]["locale"]
        print(f"[{locale}] {len(files)}枚")
        set_id = ensure_set(token, localization["id"], apply)

        if set_id:
            for existing in screenshots(token, set_id):
                name = existing["attributes"].get("fileName")
                if apply:
                    request("DELETE", f"/v1/appScreenshots/{existing['id']}", token)
                print(f"  消す: {name}")

        for name in files:
            path = os.path.join(directory, name)
            payload = open(path, "rb").read()
            print(f"  入れる: {name}（{len(payload) // 1024}KB）")
            if not apply or not set_id:
                continue

            reserved = request("POST", "/v1/appScreenshots", token, {
                "data": {"type": "appScreenshots",
                         "attributes": {"fileName": name, "fileSize": len(payload)},
                         "relationships": {"appScreenshotSet": {
                             "data": {"type": "appScreenshotSets", "id": set_id}}}}})
            shot_id = reserved["data"]["id"]
            for operation in reserved["data"]["attributes"]["uploadOperations"]:
                offset = operation["offset"]
                chunk = payload[offset:offset + operation["length"]]
                headers = {h["name"]: h["value"] for h in operation.get("requestHeaders", [])}
                request(operation["method"], operation["url"], token,
                        raw=chunk, headers=headers, authorize=False)
            request("PATCH", f"/v1/appScreenshots/{shot_id}", token, {
                "data": {"type": "appScreenshots", "id": shot_id,
                         "attributes": {"uploaded": True,
                                        "sourceFileChecksum":
                                            hashlib.md5(payload).hexdigest()}}})

    if not apply:
        print("\n（--yes を付けると実際に入れ替えます）")


# --- 審査へ出す --------------------------------------------------------------

def submit(token: str, app: str, apply: bool) -> None:
    version = editable_version(token, app)
    attributes = version["attributes"]
    print(f"出すもの: バージョン {attributes.get('versionString')}"
          f"（{attributes.get('appVersionState')}）")

    existing = get(f"/v1/reviewSubmissions?filter[app]={app}"
                   "&filter[state]=READY_FOR_REVIEW,WAITING_FOR_REVIEW,IN_REVIEW",
                   token).get("data", [])
    if existing:
        state = existing[0]["attributes"].get("state")
        raise SystemExit(f"すでに審査に出ています（{state}）。二重に出せません")

    if not apply:
        print("1. 提出の入れ物を作る（POST /v1/reviewSubmissions）")
        print("2. このバージョンを中身として足す（POST /v1/reviewSubmissionItems）")
        print("3. 提出する（PATCH submitted=true）")
        print("\n（--yes を付けると実際に出します）")
        return

    submission = request("POST", "/v1/reviewSubmissions", token, {
        "data": {"type": "reviewSubmissions",
                 "attributes": {"platform": PLATFORM},
                 "relationships": {"app": {"data": {"type": "apps", "id": app}}}}})
    submission_id = submission["data"]["id"]
    print(f"1. 入れ物を作りました: {submission_id}")

    request("POST", "/v1/reviewSubmissionItems", token, {
        "data": {"type": "reviewSubmissionItems",
                 "relationships": {
                     "reviewSubmission": {"data": {"type": "reviewSubmissions",
                                                   "id": submission_id}},
                     "appStoreVersion": {"data": {"type": "appStoreVersions",
                                                  "id": version["id"]}}}}})
    print("2. バージョンを足しました")

    done = request("PATCH", f"/v1/reviewSubmissions/{submission_id}", token, {
        "data": {"type": "reviewSubmissions", "id": submission_id,
                 "attributes": {"submitted": True}}})
    print(f"3. 出しました: {done['data']['attributes'].get('state')}")


def main() -> None:
    parser = argparse.ArgumentParser(description="App Store の審査提出まわり")
    parser.add_argument("--show", action="store_true", help="足りないものを並べる")
    parser.add_argument("--screenshots", metavar="DIR", help="スクリーンショットを入れ替える")
    parser.add_argument("--submit", action="store_true", help="審査へ出す")
    parser.add_argument("--yes", action="store_true",
                        help="実際に送る（付けないあいだは何も書き込まない）")
    args = parser.parse_args()

    asc = load_asc()
    token = asc.make_token(*asc.find_key())
    app = app_id(token)

    if args.screenshots:
        upload_screenshots(token, app, args.screenshots, args.yes)
    elif args.submit:
        submit(token, app, args.yes)
    else:
        show(token, app)


if __name__ == "__main__":
    main()

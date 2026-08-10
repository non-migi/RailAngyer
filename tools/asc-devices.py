#!/usr/bin/env python3
"""端末（UDID）を Apple Developer に登録する。

    python3 tools/asc-devices.py --list
    python3 tools/asc-devices.py --add 00008030-XXXXXXXXXXXXXXXX --name "カンノさんのiPhone"

**Ad Hoc 配布は、動かしてよい端末をアプリに埋め込んで署名する。**
ここで登録したあと、アーカイブから作り直さないと相手の端末では動かない。

> ⚠️ **枠は年100台。消しても戻らない**（契約の更新時まで）。
> 試しに登録するのは避けること。

鍵の置き場所は `asc-crashes.py` と同じ（`~/private_keys/AuthKey_<KEYID>.p8`）。
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
import re
import sys
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))

# 現行のUDIDは「8桁-16桁」。古い端末は40桁の16進
UDID = re.compile(r"^([0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}|[0-9a-fA-F]{40})$")


def load_asc():
    spec = importlib.util.spec_from_file_location(
        "asc_crashes", os.path.join(HERE, "asc-crashes.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def post(path: str, token: str, body: dict) -> dict:
    request = urllib.request.Request(
        "https://api.appstoreconnect.apple.com" + path,
        data=json.dumps(body).encode(), method="POST",
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        raise SystemExit(f"APIが {error.code} を返しました\n"
                         f"{error.read().decode(errors='replace')}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--list", action="store_true", help="登録済みの端末を見る")
    parser.add_argument("--add", help="登録するUDID")
    parser.add_argument("--name", default="", help="端末の名前（誰のものか分かるように）")
    args = parser.parse_args()
    if not (args.list or args.add):
        parser.error("--list か --add を指定してください")

    asc = load_asc()
    key_path, key_id, issuer_id = asc.find_key()
    token = asc.make_token(key_path, key_id, issuer_id)

    devices = asc.get("/v1/devices?limit=200", token)["data"]
    enabled = [d for d in devices if d["attributes"].get("status") == "ENABLED"]

    if args.list:
        print(f"登録済み {len(devices)}台（有効 {len(enabled)}台 / 上限100台）")
        for d in devices:
            a = d["attributes"]
            print(f'  {a.get("udid")}  {a.get("deviceClass"):8s} '
                  f'{a.get("status"):9s} {a.get("name")}')
        return

    udid = args.add.strip()
    if not UDID.match(udid):
        sys.exit(f"UDIDの形が違います: {udid}\n"
                 "  いまの端末は「00008030-001A2B3C0D4E5F26」のような形です")

    if any(d["attributes"].get("udid", "").lower() == udid.lower() for d in devices):
        print(f"すでに登録されています: {udid}")
        return

    if len(enabled) >= 100:
        sys.exit("端末の枠（100台）がいっぱいです。**消しても枠は戻りません**"
                 "（契約の更新時に戻ります）")

    name = args.name or f"tester-{udid[-6:]}"
    post("/v1/devices", token,
         {"data": {"type": "devices",
                   "attributes": {"name": name, "platform": "IOS", "udid": udid}}})
    print(f"登録しました: {name}  {udid}")
    print(f"  → 有効 {len(enabled) + 1}台 / 100台")
    print("  **アーカイブから作り直さないと、この端末では動きません**")


if __name__ == "__main__":
    main()

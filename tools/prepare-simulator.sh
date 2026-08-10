#!/bin/bash
# UIテストを走らせる前に、シミュレータへ位置情報の許可を与える。
#
# 新しいシミュレータ（Xcode更新でランタイムが入れ替わったときなど）では権限が未設定で、
# 許可ダイアログが操作を塞ぐため、位置情報を使うテストが落ちる。
# ダイアログをテスト内で閉じる方法は取りこぼしがあったので、事前に付与する方式にしている。
#
#   使い方:  tools/prepare-simulator.sh [デバイス名]
#   例:      tools/prepare-simulator.sh "iPhone 17 Pro"
#
# 同名のデバイスが複数のランタイムに存在することがあるため、
# **最も新しい iOS ランタイムのもの**を選ぶ（Xcode が既定で使うのがそれのため）。

set -euo pipefail

DEVICE_NAME="${1:-iPhone 17 Pro}"
BUNDLE_ID="com.non-migi.RailAngyerApp"

read -r UDID RUNTIME <<<"$(xcrun simctl list devices available --json | python3 -c '
import json, sys, re

name = sys.argv[1]
data = json.load(sys.stdin)

def version(runtime_id):
    m = re.search(r"iOS-(\d+)-(\d+)", runtime_id)
    return (int(m.group(1)), int(m.group(2))) if m else (0, 0)

best = None
for runtime_id, devices in data["devices"].items():
    if "iOS" not in runtime_id:
        continue
    for device in devices:
        if device["name"] == name:
            key = version(runtime_id)
            if best is None or key > best[0]:
                best = (key, device["udid"], runtime_id)

if best is None:
    sys.exit(1)
print(best[1], best[2])
' "$DEVICE_NAME")" || {
  echo "デバイスが見つかりません: $DEVICE_NAME" >&2
  echo "利用できるデバイス:" >&2
  xcrun simctl list devices available | grep iPhone >&2
  exit 1
}

echo "デバイス: $DEVICE_NAME"
echo "  UDID    : $UDID"
echo "  ランタイム: ${RUNTIME##*SimRuntime.}"

# 初回起動の処理が終わる前にアプリを起動すると preflight で弾かれるため、
# 起動を待ってから進める
if ! xcrun simctl list devices | grep -q "$UDID (Booted)"; then
  echo "起動しています…"
  xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
fi
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true

# **両方を付与する。** 消したばかり（`simctl erase` 直後）のシミュレータでは
# location-always だけでは測位が始まらず、自動到着のテストが落ちる。
# アプリが実際に使うのは requestWhenInUseAuthorization → requestAlwaysAuthorization の順で、
# その1段目にあたる `location` が要る。
xcrun simctl privacy "$UDID" grant location "$BUNDLE_ID"
xcrun simctl privacy "$UDID" grant location-always "$BUNDLE_ID"
echo "位置情報（使用中・常に許可の両方）を付与しました"

cat <<MSG

続けてテストを走らせる場合:

  xcodebuild -project RailAngyerApp/RailAngyerApp.xcodeproj -scheme RailAngyerApp \\
    -destination "platform=iOS Simulator,id=$UDID" test
MSG

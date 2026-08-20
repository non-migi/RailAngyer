#!/bin/bash
# App Store 用のスクリーンショットを撮って取り出す。
#
#   tools/shoot-screenshots.sh [出力先] [シミュレータ名]
#   （既定: /tmp/railangyer-shots / "iPhone 17 Pro Max"）
#
# **6.9インチの端末で撮ること。** App Store Connect は 1320×2868 を求め、
# 1ピクセルでも違うと弾く。1組入れれば小さい端末ぶんへは自動で縮められる。
#
# 撮ったあとは:
#   python3 tools/asc-submit.py --screenshots /tmp/railangyer-shots        # 中身を見せるだけ
#   python3 tools/asc-submit.py --screenshots /tmp/railangyer-shots --yes  # 実際に入れる
set -euo pipefail

OUT="${1:-/tmp/railangyer-shots}"
DEVICE="${2:-iPhone 17 Pro Max}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE="$(mktemp -d)/shots.xcresult"

echo "撮る端末: $DEVICE"
xcrun simctl boot "$DEVICE" 2>/dev/null || true
# **位置情報を許しておく。** 無いと画面に「位置情報が使えません」の赤い断りが出て、
# そのままストアに並ぶ絵になってしまう
xcrun simctl privacy "$DEVICE" grant location com.non-migi.RailAngyerApp 2>/dev/null || true
xcrun simctl privacy "$DEVICE" grant location-always com.non-migi.RailAngyerApp 2>/dev/null || true

xcodebuild -project "$ROOT/RailAngyerApp/RailAngyerApp.xcodeproj" \
  -scheme RailAngyerApp \
  -destination "platform=iOS Simulator,name=$DEVICE" \
  -only-testing:RailAngyerAppUITests/StoreScreenshotTests \
  -resultBundlePath "$BUNDLE" \
  test >/dev/null

rm -rf "$OUT" && mkdir -p "$OUT"
xcrun xcresulttool export attachments --path "$BUNDLE" --output-path "$OUT" >/dev/null

# **取り出したときの名前は当てにしない。** 実行のたびに
# `01-home_0_<UUID>.png.png` になったり、ただの UUID になったりする。
# `manifest.json` にテスト側で付けた名前（`01-home` 等）が入っているので、そこから引く。
# App Store Connect は**ファイル名の順**に並べるため、頭の番号を残すのが要点
python3 - "$OUT" <<'PY'
import json, os, re, shutil, sys
out = sys.argv[1]
manifest = os.path.join(out, "manifest.json")
renamed = 0
if os.path.exists(manifest):
    for entry in json.load(open(manifest)):
        for attachment in entry.get("attachments", []):
            label = attachment.get("suggestedHumanReadableName") or ""
            path = os.path.join(out, attachment.get("exportedFileName", ""))
            matched = re.match(r"^(\d+-[a-z]+)", label)
            if matched and os.path.exists(path):
                shutil.move(path, os.path.join(out, f"{matched.group(1)}.png"))
                renamed += 1
if not renamed:  # 名前が拾えなければ、せめて並びだけは決めておく
    for index, name in enumerate(sorted(os.listdir(out)), start=1):
        if name.lower().endswith(".png"):
            shutil.move(os.path.join(out, name),
                        os.path.join(out, f"{index:02d}-shot.png"))
PY
rm -f "$OUT/manifest.json"
# 取り出しで出る png 以外（動画・ログ）は捨てる
find "$OUT" -type f ! -name "*.png" -delete 2>/dev/null || true

# **App Store Connect が受け取る大きさへ直す。**
# API が受け付ける iPhone の最大は 6.7インチ（1290×2796）で、6.9インチの
# 1320×2868 のままでは弾かれる（`asc-submit.py` の DISPLAY_TYPE のコメント参照）。
# 縦横比はほぼ同じ（0.4603 と 0.4614）なので、見た目は変わらない
for f in "$OUT"/*.png; do
  [ -e "$f" ] || continue
  sips --resampleHeightWidth 2796 1290 "$f" >/dev/null
done

echo "--- 撮れた絵 ---"
for f in "$OUT"/*.png; do
  [ -e "$f" ] || { echo "（撮れていません）"; exit 1; }
  echo "$(basename "$f")  $(sips -g pixelWidth -g pixelHeight "$f" | awk '/pixel/{printf "%s ", $2}')"
done

#!/bin/bash
# App Store 用のスクリーンショットを、対応している言語ぶん撮って取り出す。
#
#   tools/shoot-screenshots.sh [出力先] [シミュレータ名]
#   LOCALES="ja en" tools/shoot-screenshots.sh        # 言語を絞るとき
#   （既定: /tmp/railangyer-shots / "iPhone 17 Pro Max" / 9言語ぜんぶ）
#
# 出来上がりは `<出力先>/<言語>/01-home.png …` の形。そのまま
#   python3 tools/asc-submit.py --screenshots /tmp/railangyer-shots        # 下見
#   python3 tools/asc-submit.py --screenshots /tmp/railangyer-shots --yes  # 実際に入れる
#
# **6.9インチの端末で撮り、1290×2796 に直してから出す。**
# App Store Connect が受け取る iPhone の最大は 6.7インチで、1ピクセルでも違うと弾く。
# 1組入れれば小さい端末ぶんへは自動で縮められる。
set -euo pipefail

OUT="${1:-/tmp/railangyer-shots}"
DEVICE="${2:-iPhone 17 Pro Max}"
LOCALES="${LOCALES:-ja en de es fr hi ko ru zh-Hans}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "撮る端末: $DEVICE"
xcrun simctl boot "$DEVICE" 2>/dev/null || true
# **位置情報を許しておく。** 無いと画面に「位置情報が使えません」の赤い断りが出て、
# そのままストアに並ぶ絵になってしまう
xcrun simctl privacy "$DEVICE" grant location com.non-migi.RailAngyerApp 2>/dev/null || true
xcrun simctl privacy "$DEVICE" grant location-always com.non-migi.RailAngyerApp 2>/dev/null || true

rm -rf "$OUT"

for LOCALE in $LOCALES; do
  echo "--- $LOCALE ---"
  BUNDLE="$(mktemp -d)/shots.xcresult"
  DEST="$OUT/$LOCALE"
  mkdir -p "$DEST"

  # **最初の言語のときだけ、動いているところを録っておく。**
  # App Store の「Appプレビュー」に使える素材で、撮影と同じ操作をそのまま映せる
  if [ "$LOCALE" = "$(echo $LOCALES | awk '{print $1}')" ]; then
    xcrun simctl io "$DEVICE" recordVideo --codec h264 --force "$OUT/preview-$LOCALE.mov" \
      >/dev/null 2>&1 &
    RECORDER=$!
  else
    RECORDER=""
  fi

  # **言語はアプリの設定で決まる**（端末の設定ではなく `AppLanguage`）。
  # `TEST_RUNNER_` を付けた環境変数は、頭を落としてテスト側へ届く
  TEST_RUNNER_SHOT_LOCALE="$LOCALE" \
  xcodebuild -project "$ROOT/RailAngyerApp/RailAngyerApp.xcodeproj" \
    -scheme RailAngyerApp \
    -destination "platform=iOS Simulator,name=$DEVICE" \
    -only-testing:RailAngyerAppUITests/StoreScreenshotTests \
    -resultBundlePath "$BUNDLE" \
    test >/dev/null

  if [ -n "$RECORDER" ]; then
    kill -INT "$RECORDER" 2>/dev/null || true
    wait "$RECORDER" 2>/dev/null || true
    echo "  動画: $OUT/preview-$LOCALE.mov"
  fi

  xcrun xcresulttool export attachments --path "$BUNDLE" --output-path "$DEST" >/dev/null

  # **取り出したときの名前は当てにしない。** 実行のたびに
  # `01-home_0_<UUID>.png.png` になったり、ただの UUID になったりする。
  # `manifest.json` にテスト側で付けた名前（`01-home` 等）が入っているので、そこから引く。
  # App Store Connect は**ファイル名の順**に並べるため、頭の番号を残すのが要点
  python3 - "$DEST" <<'PY'
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
  rm -f "$DEST/manifest.json"
  find "$DEST" -type f ! -name "*.png" -delete 2>/dev/null || true

  # App Store Connect が受け取る大きさへ直す（上のコメント参照）
  for f in "$DEST"/*.png; do
    [ -e "$f" ] || continue
    sips --resampleHeightWidth 2796 1290 "$f" >/dev/null
  done

  COUNT=$(find "$DEST" -name "*.png" | wc -l | tr -d ' ')
  echo "  $COUNT 枚"
  [ "$COUNT" -gt 0 ] || { echo "  **撮れていません**"; exit 1; }
done

echo "--- できあがり ---"
for dir in "$OUT"/*/; do
  echo "$(basename "$dir"): $(ls "$dir" | tr '\n' ' ')"
done

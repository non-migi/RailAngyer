#!/bin/bash
# 録った動画を、App Store の「Appプレビュー」に出せる形へ直す。
#
#   tools/make-preview.sh [元の動画] [出力先] [切り出す秒数]
#   （既定: /tmp/railangyer-shots/preview-ja.mov / 同じ場所の preview-appstore.mp4 / 28秒）
#
# **App Store のプレビューには決まりがある**（弾かれるのはたいていここ）:
#   ・長さは 15〜30秒。1秒でも外れると受け取ってもらえない
#   ・6.7インチ向けは 886×1920 か 1080×1920（縦）
#   ・H.264 / AAC
#
# 録りっぱなしの動画は端末の大きさ（1290×2796）で分数も長いので、
# **真ん中あたりを切り出して**縮める。頭は起動直後で何も起きていないことが多い。
set -euo pipefail

SRC="${1:-/tmp/railangyer-shots/preview-ja.mov}"
OUT="${2:-$(dirname "$SRC")/preview-appstore.mp4}"
SECONDS_WANTED="${3:-28}"

command -v ffmpeg >/dev/null || { echo "ffmpeg がありません（brew install ffmpeg）"; exit 1; }
[ -f "$SRC" ] || { echo "元の動画がありません: $SRC"; exit 1; }

DURATION=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$SRC" | cut -d. -f1)
echo "元: ${SRC}（${DURATION}秒）"

# 真ん中から欲しい長さぶんを取る。短ければ頭から
if [ "$DURATION" -gt "$SECONDS_WANTED" ]; then
  START=$(( (DURATION - SECONDS_WANTED) / 2 ))
else
  START=0
  SECONDS_WANTED="$DURATION"
fi

# **音は入れない。** 無音のプレビューは許されるが、
# 音の無いトラックがあると弾かれることがあるので、音声そのものを落とす
ffmpeg -y -loglevel error \
  -ss "$START" -i "$SRC" -t "$SECONDS_WANTED" \
  -vf "scale=886:1920:force_original_aspect_ratio=decrease,pad=886:1920:(ow-iw)/2:(oh-ih)/2:color=white" \
  -c:v libx264 -profile:v high -pix_fmt yuv420p -r 30 -b:v 6M \
  -an "$OUT"

SIZE=$(ffprobe -v error -show_entries stream=width,height -of csv=p=0:s=x "$OUT" | head -1)
LENGTH=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT" | cut -d. -f1)
echo "できあがり: ${OUT}"
echo "  大きさ ${SIZE} / 長さ ${LENGTH}秒 / $(du -h "$OUT" | cut -f1)"
[ "$LENGTH" -ge 15 ] && [ "$LENGTH" -le 30 ] || {
  echo "  ⚠️ 15〜30秒に収まっていません。App Store は受け取りません"; exit 1; }

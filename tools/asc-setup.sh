#!/bin/zsh
# App Store Connect API の設定を仕上げる。
#
#   ./tools/asc-setup.sh <Issuer ID の UUID>
#
# 鍵（AuthKey_*.p8）は ~/private_keys に置いてある前提。
# Issuer ID は App Store Connect ＞ ユーザーとアクセス ＞ 各種統合 ＞
# App Store Connect API のページ上部にある UUID で、チームで1つだけ。
# **鍵ファイルには入っていないので、ここだけは人が持ってくる必要がある。**
set -e

ISSUER="$1"
KEY_DIR="$HOME/private_keys"
CONFIG="$KEY_DIR/asc-config.json"

if [[ -z "$ISSUER" ]]; then
  echo "使い方: $0 <Issuer ID の UUID>"
  echo "例:     $0 69a6de70-1234-47e3-e053-5b8c7c11a4d1"
  exit 1
fi

if [[ ! "$ISSUER" =~ ^[0-9a-fA-F-]{36}$ ]]; then
  echo "Issuer ID は36文字のUUIDです。貼り間違いがないか確かめてください: $ISSUER"
  exit 1
fi

key=$(ls "$KEY_DIR"/AuthKey_*.p8 2>/dev/null | head -1)
if [[ -z "$key" ]]; then
  echo "鍵がありません。$KEY_DIR/AuthKey_<キーID>.p8 を置いてください。"
  exit 1
fi

printf '{ "issuerId": "%s" }\n' "$ISSUER" > "$CONFIG"
chmod 600 "$CONFIG"
echo "設定を書きました: $CONFIG（鍵: $(basename "$key")）"

echo "--- 疎通を確かめます ---"
python3 "$(dirname "$0")/asc-crashes.py"

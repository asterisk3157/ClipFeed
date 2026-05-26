#!/bin/bash
# icon.svg から AppIcon.icns を生成する。
# SVG 描画は macOS 標準の QuickLook(WebKit) を使うため追加インストール不要。
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SVG="$DIR/icon.svg"
TMP="$DIR/.icontmp"
ISET="$DIR/ClipFeed.iconset"

command -v magick   >/dev/null || { echo "❌ ImageMagick(magick) が必要です: brew install imagemagick"; exit 1; }
command -v iconutil >/dev/null || { echo "❌ iconutil が必要です(Xcode CLT)"; exit 1; }

/bin/rm -rf "$TMP" "$ISET"
mkdir -p "$TMP" "$ISET"

# 1024px のマスターを QuickLook で描画（グラデーション・枠線も正しく出る）
qlmanage -t -s 1024 -o "$TMP" "$SVG" >/dev/null 2>&1
MASTER="$TMP/icon.svg.png"
[ -f "$MASTER" ] || { echo "❌ QuickLook での描画に失敗"; exit 1; }

gen () { magick "$MASTER" -resize "${1}x${1}" "$ISET/$2"; }
gen 16   icon_16x16.png
gen 32   icon_16x16@2x.png
gen 32   icon_32x32.png
gen 64   icon_32x32@2x.png
gen 128  icon_128x128.png
gen 256  icon_128x128@2x.png
gen 256  icon_256x256.png
gen 512  icon_256x256@2x.png
gen 512  icon_512x512.png
gen 1024 icon_512x512@2x.png

iconutil -c icns "$ISET" -o "$DIR/AppIcon.icns"
/bin/rm -rf "$TMP" "$ISET"
echo "✅ Built: $DIR/AppIcon.icns"

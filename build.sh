#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$DIR/ClipFeed.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>ClipFeed</string>
    <key>CFBundleDisplayName</key>     <string>ClipFeed</string>
    <key>CFBundleIdentifier</key>      <string>com.github.asterisk3157.clipfeed</string>
    <key>CFBundleExecutable</key>      <string>ClipFeed</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>CFBundleIconFile</key>        <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSHumanReadableCopyright</key><string>ClipFeed</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>  <true/>
    </dict>
</dict>
</plist>
PLIST

swiftc -O \
    -o "$APP/Contents/MacOS/ClipFeed" \
    "$DIR/Sources/main.swift" \
    -framework Cocoa \
    -framework WebKit

# HTML→Markdown 変換に使う turndown 一式を同梱（自己完結のため）
cp "$DIR/vendor/turndown.js" "$APP/Contents/Resources/"
cp "$DIR/vendor/turndown-plugin-gfm.js" "$APP/Contents/Resources/"

# アプリアイコン（無ければ make-icon.sh で生成するよう促す）
if [ -f "$DIR/AppIcon.icns" ]; then
    cp "$DIR/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
else
    echo "⚠️  AppIcon.icns が無いためアイコンなしでビルドします（./make-icon.sh で生成できます）"
fi

# アドホック署名（Apple Silicon で TCC 周りが安定する）
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "✅ Built: $APP"

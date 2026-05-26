---
name: ClipFeed
tagline: コピーした内容をワンクリックでクリーンなMarkdownにして、AIにファイルで渡せるmacOSメニューバーアプリ
category: app
status: released
url:
repo: https://github.com/asterisk3157/ClipFeed
tech: [Swift, AppKit, WebKit, ServiceManagement, turndown]
released_at: 2026-05-27
---

## これは何
Web などでコピーしたリッチテキストを、ワンクリックで「画像を除いたクリーンな Markdown」または
「完全な HTML」に変換し、`~/Downloads` に保存したうえで、そのファイルをそのままクリップボードに
載せ直す macOS メニューバーアプリ。TextEdit を開かずに、AI へ "ファイルで" コンテキストを渡せる。

## 主な機能
- クリップボードの HTML → クリーンな Markdown 変換（同梱 turndown を WKWebView で実行。画像・base64・余計な生HTMLを除去）
- 完全 HTML として保存するモード（構造を一切落としたくないとき）
- 生成ファイルをクリップボードに再配置（Claude デスクトップは添付・ターミナルはパス入力）
- メニューから「ログイン時に起動」を ON/OFF

## 魅力 / こだわり
- ワンクリック完結。エディタを開く手間ゼロ
- 画像除去で実測 約43% 軽量化 → AI のトークン節約
- 表・見出し・リストの構造は保持
- 追加インストール不要の自己完結（約450KB）。アプリアイコンは SVG から自前生成

## スクリーンショット
（メニューバーアイコン / メニュー）

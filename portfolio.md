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
Web などでコピーしたリッチテキストを、ワンクリックで「画像を除いたクリーンな Markdown」「完全な HTML」
「1枚の PDF」「1枚の高解像度画像」に変換し、`~/Downloads` に保存したうえで、そのファイルをそのまま
クリップボードに載せ直す macOS メニューバーアプリ。TextEdit を開かずに、AI へ "ファイルで" コンテキストを渡せる。

## 主な機能
- クリップボードの HTML → クリーンな Markdown 変換（同梱 turndown を WKWebView で実行。画像・base64・余計な生HTMLを除去）
- 完全 HTML として保存するモード（構造を一切落としたくないとき）
- **1枚の PDF として保存**（WKWebView でレンダリング。文字はベクターのままで解像度非依存）
- **1枚の高解像度画像(PNG)として保存**（retina 倍率に依存しない固定解像度）
- 生成ファイルをクリップボードに再配置（Claude デスクトップは添付・ターミナルはパス入力）
- メニューから「ログイン時に起動」を ON/OFF

## 魅力 / こだわり
- ワンクリック完結。エディタを開く手間ゼロ
- 画像除去で実測 約43% 軽量化 → AI のトークン節約
- 表・見出し・リストの構造は保持
- PDF / 画像化では lazy 画像を確実に読み込み、コンテンツ実寸幅でキャプチャして右側の見切れを防止
- 追加インストール不要の自己完結（約450KB）。アプリアイコンは SVG から自前生成

## スクリーンショット
（メニューバーアイコン / メニュー）

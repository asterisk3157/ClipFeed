import Cocoa
import WebKit
import ServiceManagement

// ClipFeed
// クリップボードのリッチ内容(HTML)を Markdown(.md) / HTML に変換し、~/Downloads に保存して、
// そのファイルをクリップボードに載せ直す macOS メニューバー常駐アプリ。
//   - HTML→Markdown は同梱の turndown.js を WKWebView 上で実行（pandoc 等の外部依存なし・自己完結）
//   - public.file-url : Claude デスクトップアプリ等が「ファイル添付」として受け取る
//   - 絶対パス(文字列): ターミナル(Claude Code 等) に貼ると パスがそのまま入る

// MARK: - HTML → Markdown 変換（WKWebView + turndown）

final class MarkdownConverter: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private var ready = false
    private var queue: [(String, (String?) -> Void)] = []

    override init() {
        webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        super.init()
        webView.navigationDelegate = self
        webView.loadHTMLString(
            "<!DOCTYPE html><html><head><meta charset=\"utf-8\"></head><body></body></html>",
            baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !ready else { return }
        let turndown = Self.resource("turndown") ?? ""
        let gfm = Self.resource("turndown-plugin-gfm") ?? ""
        let bootstrap = turndown + "\n" + gfm + "\n" + """
        window.__clipfeedConvert = function(html) {
          var ts = new TurndownService({
            headingStyle: 'atx',
            bulletListMarker: '-',
            codeBlockStyle: 'fenced',
            emDelimiter: '*',
            hr: '---'
          });
          ts.remove(['script', 'style', 'noscript']);
          if (window.turndownPluginGfm) { ts.use(window.turndownPluginGfm.gfm); }
          return ts.turndown(html);
        };
        true;
        """
        webView.evaluateJavaScript(bootstrap) { [weak self] _, _ in
            guard let self = self else { return }
            self.ready = true
            let pending = self.queue
            self.queue.removeAll()
            for (html, cb) in pending { self.run(html, cb) }
        }
    }

    /// HTML を Markdown に変換（WKWebView 準備前に呼ばれたらキューに積む）
    func convert(_ html: String, completion: @escaping (String?) -> Void) {
        if ready { run(html, completion) } else { queue.append((html, completion)) }
    }

    private func run(_ html: String, _ completion: @escaping (String?) -> Void) {
        // HTML を JS の文字列リテラルとして安全に渡す（JSON エンコード）
        guard let data = try? JSONSerialization.data(withJSONObject: html, options: .fragmentsAllowed),
              let literal = String(data: data, encoding: .utf8) else {
            completion(nil); return
        }
        webView.evaluateJavaScript("window.__clipfeedConvert(\(literal));") { result, _ in
            completion(result as? String)
        }
    }

    /// .app では Contents/Resources から turndown 等を読む
    private static func resource(_ name: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "js") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

// MARK: - メニューバー常駐アプリ

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var lastItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var feedbackSound: NSSound?
    private var converter: MarkdownConverter!
    private let idleSymbol = "doc.on.clipboard"

    func applicationDidFinishLaunching(_ notification: Notification) {
        converter = MarkdownConverter()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setIcon(idleSymbol)

        let menu = NSMenu()
        menu.delegate = self

        let toMarkdown = NSMenuItem(
            title: "クリップボードを .md に変換",
            action: #selector(saveAsMarkdown), keyEquivalent: "")
        toMarkdown.target = self
        menu.addItem(toMarkdown)

        let toHTML = NSMenuItem(
            title: "クリップボードを .html で保存",
            action: #selector(saveAsHTML), keyEquivalent: "")
        toHTML.target = self
        menu.addItem(toHTML)

        menu.addItem(.separator())

        lastItem = NSMenuItem(title: "（まだ保存していません）", action: nil, keyEquivalent: "")
        lastItem.isEnabled = false
        menu.addItem(lastItem)

        menu.addItem(.separator())

        loginItem = NSMenuItem(
            title: "ログイン時に起動",
            action: #selector(toggleLoginItem), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)

        let quit = NSMenuItem(title: "終了", action: #selector(quitAction), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu

        if let url = URL(string: "file:///System/Library/Sounds/Glass.aiff") {
            feedbackSound = NSSound(contentsOf: url, byReference: true)
        }
        updateLoginItemState()
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateLoginItemState()
    }

    // MARK: - Actions

    private enum OutputMode { case markdown, html }

    @objc private func saveAsMarkdown() { process(mode: .markdown) }
    @objc private func saveAsHTML() { process(mode: .html) }

    private func process(mode: OutputMode) {
        let pb = NSPasteboard.general
        let html = pb.string(forType: .html)
        let plain = pb.string(forType: .string)

        switch mode {
        case .markdown:
            if let html, !html.isEmpty {
                converter.convert(html) { [weak self] md in
                    guard let self = self else { return }
                    guard let md = md, !md.isEmpty else {
                        self.showError("HTML→Markdown 変換に失敗しました。")
                        return
                    }
                    self.finish(content: self.cleanMarkdown(md), ext: "md")
                }
            } else if let plain, !plain.isEmpty {
                finish(content: plain, ext: "md")
            } else {
                showError("クリップボードにテキストがありません。\n先に Web などでコピーしてから実行してください。")
            }

        case .html:
            if let html, !html.isEmpty {
                finish(content: wrapHTMLDocument(html), ext: "html")
            } else if let plain, !plain.isEmpty {
                finish(content: wrapHTMLDocument("<pre>\(escapeHTML(plain))</pre>"), ext: "html")
            } else {
                showError("クリップボードにテキストがありません。\n先に Web などでコピーしてから実行してください。")
            }
        }
    }

    private func finish(content: String, ext: String) {
        do {
            let fileURL = try writeFile(content, ext: ext)
            placeFileOnPasteboard(fileURL)
            flashSuccess(fileName: fileURL.lastPathComponent)
        } catch {
            showError("ファイルの保存に失敗しました。\n\(error.localizedDescription)")
        }
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }

    // MARK: - Login Item (ログイン時起動)

    @objc private func toggleLoginItem() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            SMAppService.openSystemSettingsLoginItems()
            showError("ログイン項目の切り替えに失敗しました。\nシステム設定のログイン項目で許可してください。\n\n\(error.localizedDescription)")
        }
        updateLoginItemState()
    }

    private func updateLoginItemState() {
        guard loginItem != nil else { return }
        loginItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
    }

    // MARK: - Markdown cleanup（画像除去のみ）

    private func cleanMarkdown(_ md: String) -> String {
        var s = md
        // インライン画像 ![alt](url) を除去（base64 データURIもこれで消える）
        s = s.replacingOccurrences(
            of: #"!\[[^\]]*\]\([^)]*\)"#, with: "", options: .regularExpression)
        // 画像だけだったリンクが空リンク [](url) として残るので除去
        s = s.replacingOccurrences(
            of: #"\[\]\([^)]*\)"#, with: "", options: .regularExpression)
        // 各行末尾の空白を除去
        s = s.replacingOccurrences(
            of: #"(?m)[ \t]+$"#, with: "", options: .regularExpression)
        // 画像の後ろにあった改行マーカー「\」だけが孤立行として残るので除去
        s = s.replacingOccurrences(
            of: #"(?m)^[ \t]*\\[ \t]*$"#, with: "", options: .regularExpression)
        // 3行以上の連続空行を1つにまとめる
        s = s.replacingOccurrences(
            of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - HTML wrapping（完全保存）

    private func wrapHTMLDocument(_ fragment: String) -> String {
        var body = fragment
        body = body.replacingOccurrences(of: "<!--StartFragment-->", with: "")
        body = body.replacingOccurrences(of: "<!--EndFragment-->", with: "")
        return """
        <!DOCTYPE html>
        <html lang="ja">
        <head><meta charset="utf-8"></head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    private func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: - File & Pasteboard

    private func writeFile(_ content: String, ext: String) throws -> URL {
        let downloads = try FileManager.default.url(
            for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd-HHmmss"
        let url = downloads.appendingPathComponent("clip-\(fmt.string(from: Date())).\(ext)")
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func placeFileOnPasteboard(_ url: URL) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)   // public.file-url
        item.setString(url.path, forType: .string)              // POSIX パス
        pb.writeObjects([item])
    }

    // MARK: - Feedback

    private func setIcon(_ symbol: String) {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "ClipFeed")
        image?.isTemplate = true
        button.image = image
    }

    private func flashSuccess(fileName: String) {
        feedbackSound?.play()
        lastItem.title = "保存: \(fileName)"
        setIcon("checkmark.circle.fill")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self else { return }
            self.setIcon(self.idleSymbol)
        }
    }

    private func showError(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "ClipFeed"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}

// MARK: - ヘッドレス変換（CLI / 動作確認用）: `ClipFeed --convert <file.html>`

func runHeadlessConvert(path: String) {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let converter = MarkdownConverter()

    guard let html = try? String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8) else {
        FileHandle.standardError.write(Data("読み込み失敗: \(path)\n".utf8))
        exit(1)
    }
    converter.convert(html) { md in
        if let md = md {
            FileHandle.standardOutput.write(Data((md + "\n").utf8))
            exit(0)
        } else {
            FileHandle.standardError.write(Data("変換失敗\n".utf8))
            exit(1)
        }
    }
    app.run()
}

// MARK: - エントリポイント

let arguments = CommandLine.arguments
if arguments.count >= 3, arguments[1] == "--convert" {
    runHeadlessConvert(path: arguments[2])
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)   // Dock アイコンを出さない（メニューバー常駐）
    app.run()
}

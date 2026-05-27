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

// MARK: - 描画用 HTML テンプレート（きれいな既定スタイルを注入）

enum RenderTemplate {
    /// クリップボードの HTML 断片を、読みやすい既定 CSS 付きの完全な HTML 文書に包む。
    /// サイト側の CSS は付いてこないため、ここで最低限のタイポグラフィを与えて「資料1枚」として整える。
    static func styledDocument(bodyHTML: String) -> String {
        var body = bodyHTML
        body = body.replacingOccurrences(of: "<!--StartFragment-->", with: "")
        body = body.replacingOccurrences(of: "<!--EndFragment-->", with: "")
        return """
        <!DOCTYPE html>
        <html lang="ja">
        <head>
        <meta charset="utf-8">
        <style>
        :root { color-scheme: light; }
        html, body { background: #ffffff; }
        body {
          font-family: -apple-system, "Helvetica Neue", "Hiragino Sans", "Yu Gothic", sans-serif;
          font-size: 15px; line-height: 1.75; color: #1a1a1a;
          margin: 0; padding: 28px 32px;
          -webkit-font-smoothing: antialiased; word-wrap: break-word; overflow-wrap: break-word;
        }
        /* レイアウト幅はコピー HTML 側の指定を尊重し、実寸を測ってその幅でキャプチャする
           （max-width 等で squish しない＝右側の見切れ防止）。画像のみ列内に収める。 */
        h1, h2, h3, h4 { line-height: 1.3; margin: 1.5em 0 .5em; font-weight: 700; }
        h1 { font-size: 1.85em; border-bottom: 1px solid #ececec; padding-bottom: .3em; }
        h2 { font-size: 1.45em; } h3 { font-size: 1.2em; } h4 { font-size: 1.05em; }
        p { margin: .65em 0; }
        a { color: #0a66c2; text-decoration: none; }
        img { max-width: 100%; height: auto; border-radius: 6px; }
        ul, ol { padding-left: 1.6em; margin: .6em 0; }
        li { margin: .25em 0; }
        table { border-collapse: collapse; width: 100%; margin: 1.1em 0; font-size: .92em; }
        th, td { border: 1px solid #d8d8d8; padding: 7px 11px; text-align: left; vertical-align: top; }
        th { background: #f5f6f7; font-weight: 600; }
        pre { background: #f6f8fa; padding: 13px 15px; border-radius: 8px; overflow-x: auto;
              font-size: .88em; line-height: 1.55; }
        code { font-family: "SF Mono", Menlo, Consolas, monospace; background: #f0f1f2;
               padding: .12em .35em; border-radius: 4px; font-size: .9em; }
        pre code { background: none; padding: 0; }
        blockquote { border-left: 3px solid #dcdcdc; margin: 1em 0; padding: .25em 1.1em; color: #555; }
        hr { border: none; border-top: 1px solid #e4e4e4; margin: 1.6em 0; }
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }
}

// MARK: - PDF / 画像レンダラー（WKWebView を非表示で描画して 1 枚に書き出す）

final class PageRenderer: NSObject, WKNavigationDelegate {
    enum Mode { case pdf, image }
    enum RenderError: LocalizedError {
        case measure, snapshot, encode, timeout
        var errorDescription: String? {
            switch self {
            case .measure: return "コンテンツの寸法測定に失敗しました。"
            case .snapshot: return "スナップショットの取得に失敗しました。"
            case .encode: return "画像のエンコードに失敗しました。"
            case .timeout: return "描画がタイムアウトしました（画像の読み込みに時間がかかっている可能性があります）。"
            }
        }
    }

    private let mode: Mode
    private let completion: (Result<(Data, String), Error>) -> Void
    private var webView: WKWebView!
    private var window: NSWindow!
    private var finished = false

    /// 初期ビューポート幅(pt)。コンテンツの実寸を測る基準＝最小キャプチャ幅。
    private let baseWidth: CGFloat = 1000
    /// キャプチャ幅の上限(pt)。自己クリップされない巨大要素があっても暴走させない安全弁。
    private let maxWidth: CGFloat = 2600
    /// 実際にキャプチャする幅(pt)。コンテンツの実寸(scrollWidth)を測って決める＝右側の見切れ防止。
    private var captureWidth: CGFloat = 1000
    /// 画像(PNG)の解像度倍率（pt あたりのピクセル数）。2 で高精細。ディスプレイの retina 倍率に依存しない。
    private let imageScale: CGFloat = 2.0
    /// 画像読み込みを待つ上限(秒)。全部読めればそれより早く進む。遅い/壊れた画像はここで打ち切り。
    private let imageWaitSeconds: Double = 15.0

    init(mode: Mode, completion: @escaping (Result<(Data, String), Error>) -> Void) {
        self.mode = mode
        self.completion = completion
        super.init()
    }

    /// 完全な HTML 文書を読み込んで描画を開始する（メインスレッドで呼ぶこと）。
    func load(html: String) {
        captureWidth = baseWidth
        let frame = NSRect(x: 0, y: 0, width: baseWidth, height: 600)
        webView = WKWebView(frame: frame, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = self
        // 画面外の不可視ウィンドウに載せて、非表示でも確実にレンダリングさせる
        window = NSWindow(contentRect: NSRect(x: -30000, y: -30000, width: baseWidth, height: 600),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = webView
        window.orderFrontRegardless()

        // セーフティ・ウォッチドッグ（画像待ちのソフトタイムアウトを十分に超える値）
        DispatchQueue.main.asyncAfter(deadline: .now() + imageWaitSeconds + 25) { [weak self] in
            self?.fail(RenderError.timeout)
        }
        webView.loadHTMLString(html, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        prepareAndMeasure()
    }

    /// フェーズ1: lazy 画像を即時読み込みへ切り替え、コンテンツの実寸(幅・高さ)を測る。
    /// scrollWidth は「自己クリップされたカルーセル等」を含まない実コンテンツ幅なので、
    /// これをキャプチャ幅に採用すると右側を取りこぼさず、かつ暴走もしない。
    private func prepareAndMeasure() {
        let js = """
        document.querySelectorAll('img').forEach(img => {
          try {
            if (img.loading === 'lazy') img.loading = 'eager';
            const ds = img.getAttribute('data-src');
            if (ds && img.src !== ds) img.src = ds;
            const dss = img.getAttribute('data-srcset');
            if (dss && !img.srcset) img.srcset = dss;
          } catch (e) {}
        });
        const d = document.documentElement, b = document.body;
        return {
          w: Math.ceil(Math.max(d.scrollWidth, b ? b.scrollWidth : 0)),
          h: Math.ceil(Math.max(d.scrollHeight, b ? b.scrollHeight : 0))
        };
        """
        webView.callAsyncJavaScript(js, arguments: [:], in: nil, in: .page) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let value):
                let dict = value as? [String: Any]
                let w0 = (dict?["w"] as? NSNumber)?.doubleValue ?? Double(self.baseWidth)
                let h0 = (dict?["h"] as? NSNumber)?.doubleValue ?? 600
                // 実寸の幅でキャプチャ幅を決定（baseWidth 〜 maxWidth でクランプ）
                self.captureWidth = min(max(CGFloat(w0), self.baseWidth), self.maxWidth)
                // ビューポートを実幅×全高へ拡大 → lazy 画像を発火 & 実幅でレイアウト確定
                let size = NSSize(width: self.captureWidth, height: max(CGFloat(h0), 600))
                self.webView.frame = CGRect(origin: .zero, size: size)
                self.window.setContentSize(size)
                self.webView.layoutSubtreeIfNeeded()
                self.awaitImagesAndCapture()
            case .failure(let error):
                self.fail(error)
            }
        }
    }

    /// フェーズ2: 画像の読み込みを「ソフトタイムアウト付き」で待ち、最終的な全高を測ってキャプチャ。
    /// 全画像が読めればそれより早く進み、遅い/壊れた画像があっても打ち切って描画する。
    private func awaitImagesAndCapture() {
        let js = """
        const imgs = Array.from(document.images);
        const waitAll = Promise.all(imgs.map(img =>
          (img.complete && img.naturalWidth > 0) ? 0
          : new Promise(r => {
              const done = () => r(0);
              img.addEventListener('load', done, { once: true });
              img.addEventListener('error', done, { once: true });
            })
        ));
        const softCap = new Promise(r => setTimeout(r, maxWaitMs));
        await Promise.race([waitAll, softCap]);
        await new Promise(r => setTimeout(r, 120));
        const d = document.documentElement, b = document.body;
        return {
          w: Math.ceil(Math.max(d.scrollWidth, b ? b.scrollWidth : 0)),
          h: Math.ceil(Math.max(d.scrollHeight, b ? b.scrollHeight : 0))
        };
        """
        let args: [String: Any] = ["maxWaitMs": imageWaitSeconds * 1000]
        webView.callAsyncJavaScript(js, arguments: args, in: nil, in: .page) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let value):
                guard let dict = value as? [String: Any],
                      let h = (dict["h"] as? NSNumber)?.doubleValue, h > 0 else {
                    self.fail(RenderError.measure); return
                }
                // 画像読込で横にはみ出した分があれば幅も追従（見切れ防止）
                if let w = (dict["w"] as? NSNumber)?.doubleValue {
                    self.captureWidth = min(max(CGFloat(w), self.captureWidth), self.maxWidth)
                }
                self.capture(height: CGFloat(h))
            case .failure(let error):
                self.fail(error)
            }
        }
    }

    private func capture(height: CGFloat) {
        let rect = CGRect(x: 0, y: 0, width: captureWidth, height: max(height, 1))
        webView.frame = rect
        window.setContentSize(rect.size)
        webView.layoutSubtreeIfNeeded()

        // レイアウト確定後にキャプチャ
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self = self, !self.finished else { return }
            switch self.mode {
            case .pdf:
                let cfg = WKPDFConfiguration()
                cfg.rect = rect
                self.webView.createPDF(configuration: cfg) { [weak self] res in
                    switch res {
                    case .success(let data): self?.succeed(data, "pdf")
                    case .failure(let e): self?.fail(e)
                    }
                }
            case .image:
                let snap = WKSnapshotConfiguration()
                snap.rect = rect
                // 最終ピクセル幅 = snapshotWidth(pt) × backingScaleFactor。
                // ディスプレイの retina 倍率で割っておき、狙った解像度に正規化する。
                let backing = self.window.backingScaleFactor > 0 ? self.window.backingScaleFactor : 1
                let targetPixels = self.captureWidth * self.imageScale
                snap.snapshotWidth = NSNumber(value: Double(targetPixels / backing))
                self.webView.takeSnapshot(with: snap) { [weak self] image, error in
                    guard let self = self else { return }
                    guard let image = image else { self.fail(error ?? RenderError.snapshot); return }
                    guard let data = Self.pngData(from: image) else { self.fail(RenderError.encode); return }
                    self.succeed(data, "png")
                }
            }
        }
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private func succeed(_ data: Data, _ ext: String) {
        guard !finished else { return }
        finished = true
        cleanup()
        completion(.success((data, ext)))
    }

    private func fail(_ error: Error) {
        guard !finished else { return }
        finished = true
        cleanup()
        completion(.failure(error))
    }

    private func cleanup() {
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
        webView = nil
    }
}

// MARK: - メニューバー常駐アプリ

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var lastItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var feedbackSound: NSSound?
    private var converter: MarkdownConverter!
    private var activeRenderer: PageRenderer?
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

        let toPDF = NSMenuItem(
            title: "クリップボードを 1枚の PDF で保存",
            action: #selector(saveAsPDF), keyEquivalent: "")
        toPDF.target = self
        menu.addItem(toPDF)

        let toImage = NSMenuItem(
            title: "クリップボードを 1枚の画像(PNG) で保存",
            action: #selector(saveAsImage), keyEquivalent: "")
        toImage.target = self
        menu.addItem(toImage)

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
    @objc private func saveAsPDF() { renderClip(mode: .pdf) }
    @objc private func saveAsImage() { renderClip(mode: .image) }

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

    /// クリップボードの HTML（無ければプレーンテキスト）を 1 枚の PDF / 画像に描画して保存する。
    private func renderClip(mode: PageRenderer.Mode) {
        let pb = NSPasteboard.general
        let html = pb.string(forType: .html)
        let plain = pb.string(forType: .string)

        let fragment: String
        if let html, !html.isEmpty {
            fragment = html
        } else if let plain, !plain.isEmpty {
            fragment = "<pre>\(escapeHTML(plain))</pre>"
        } else {
            showError("クリップボードにテキストがありません。\n先に Web などでコピーしてから実行してください。")
            return
        }

        setIcon("hourglass")   // 描画中（数百ms〜画像読み込み分）
        let document = RenderTemplate.styledDocument(bodyHTML: fragment)
        let label = (mode == .pdf) ? "PDF" : "画像"
        let renderer = PageRenderer(mode: mode) { [weak self] result in
            guard let self = self else { return }
            self.activeRenderer = nil
            switch result {
            case .success(let (data, ext)):
                self.finish(data: data, ext: ext)
            case .failure(let error):
                self.setIcon(self.idleSymbol)
                self.showError("\(label)の生成に失敗しました。\n\(error.localizedDescription)")
            }
        }
        activeRenderer = renderer   // 完了まで保持
        renderer.load(html: document)
    }

    private func finish(data: Data, ext: String) {
        do {
            let fileURL = try writeFileData(data, ext: ext)
            placeFileOnPasteboard(fileURL)
            flashSuccess(fileName: fileURL.lastPathComponent)
        } catch {
            setIcon(idleSymbol)
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

    private func writeFileData(_ data: Data, ext: String) throws -> URL {
        let downloads = try FileManager.default.url(
            for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd-HHmmss"
        let url = downloads.appendingPathComponent("clip-\(fmt.string(from: Date())).\(ext)")
        try data.write(to: url, options: .atomic)
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

// MARK: - ヘッドレス描画（動作確認用）: `ClipFeed --render <in.html> <out.pdf|out.png>`

func runHeadlessRender(input: String, output: String) {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    guard let html = try? String(contentsOf: URL(fileURLWithPath: input), encoding: .utf8) else {
        FileHandle.standardError.write(Data("読み込み失敗: \(input)\n".utf8))
        exit(1)
    }
    let mode: PageRenderer.Mode = output.lowercased().hasSuffix(".png") ? .image : .pdf
    let document = RenderTemplate.styledDocument(bodyHTML: html)

    var renderer: PageRenderer?
    renderer = PageRenderer(mode: mode) { result in
        switch result {
        case .success(let (data, _)):
            do {
                try data.write(to: URL(fileURLWithPath: output), options: .atomic)
                FileHandle.standardOutput.write(Data("OK: \(data.count) bytes -> \(output)\n".utf8))
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("書き込み失敗: \(error)\n".utf8))
                exit(1)
            }
        case .failure(let error):
            FileHandle.standardError.write(Data("描画失敗: \(error)\n".utf8))
            exit(1)
        }
    }
    renderer?.load(html: document)
    withExtendedLifetime(renderer) { app.run() }
}

// MARK: - エントリポイント

let arguments = CommandLine.arguments
if arguments.count >= 3, arguments[1] == "--convert" {
    runHeadlessConvert(path: arguments[2])
} else if arguments.count >= 4, arguments[1] == "--render" {
    runHeadlessRender(input: arguments[2], output: arguments[3])
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)   // Dock アイコンを出さない（メニューバー常駐）
    app.run()
}

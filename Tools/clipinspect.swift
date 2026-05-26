import Cocoa

// clipinspect: いまクリップボードに入っている内容を診断する（型一覧＋生HTMLのノイズ統計）。
// HTML→Markdown 変換は ClipFeed 本体が担当（`ClipFeed --convert <file.html>`）。
// ここは「何が載っているか / どんなノイズを含むか」を確認するための補助ツール。

let pb = NSPasteboard.general

print("=== クリップボードに存在する型 ===")
for t in pb.types ?? [] { print("  - \(t.rawValue)") }

func count(_ haystack: String, _ needle: String) -> Int {
    guard !needle.isEmpty else { return 0 }
    return haystack.components(separatedBy: needle).count - 1
}

func report(_ label: String, _ text: String, needles: [String]) {
    print("---- \(label) ----")
    var clean = true
    for n in needles {
        let c = count(text, n)
        if c > 0 { print("  ⚠️ \(n) : \(c)"); clean = false }
    }
    if clean { print("  ✅ ノイズ検出なし") }
}

if let html = pb.string(forType: .html), !html.isEmpty {
    print("\n=== 生HTMLの統計 ===")
    print("  バイト数: \(html.utf8.count)")
    report("生HTMLに含まれるノイズ", html,
           needles: ["style=", "class=", "data-", "data:image", "<script", "<!--",
                     "<div", "<span", "<img", "utm_", "fbclid", "gclid"])
    print("\nヒント: 変換結果は `ClipFeed --convert <file.html>` で確認できます。")
} else if let s = pb.string(forType: .string) {
    print("\n(public.html なし = リッチコピーされていない)")
    print("プレーンテキスト長: \(s.count) 文字")
} else {
    print("\n(テキスト / HTML がクリップボードにありません)")
}

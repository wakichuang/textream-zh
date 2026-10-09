import AppKit
import SwiftUI

// 驗證：切字結果、每一行實際寬度是否超出容器（超出＝原版會把字縮成「…」）、畫出 PNG
let label = CommandLine.arguments[1]
let outDir = CommandLine.arguments[2]

let issueSample = "那一年他 36 歲，搬到新的城市，而且換過三份工作。"
let longSample = """
「卡片盒筆記」這個方法，我從 2019 年開始用，到現在已經寫了 5,000 多張卡片。
很多人問我：用 Notion 還是 Heptabase 比較好？我的答案是——工具不重要，重要的是你有沒有「自己的觀點」。
第一，先寫下你讀到的東西；第二，用自己的話重寫一次；第三，把它跟舊的卡片連起來……
Claude、ChatGPT 這類 AI 工具，可以幫你做 80% 的機械工（轉錄、搜尋、排版），但剩下 20% 的思考，一定要自己來。
《原子習慣》的作者 James Clear 說過：「你不會提升到目標的高度，而是會跌落到系統的水準。」
"""

let fonts: [(String, NSFont)] = [
    ("sans", NSFont.systemFont(ofSize: 20, weight: .semibold)),
    ("serif", NSFont(descriptor: NSFont.systemFont(ofSize: 20, weight: .semibold).fontDescriptor.withDesign(.serif)!, size: 20)!),
    ("mono", NSFont.monospacedSystemFont(ofSize: 20, weight: .semibold)),
    ("sans32", NSFont.systemFont(ofSize: 32, weight: .semibold)),
]

// 跟 wordView 一樣的畫法：Text(displayText).fixedSize().padding(.trailing, -trailingTrim)
@MainActor func actualWidth(_ item: WordItem, _ f: NSFont, cache: inout [String: CGFloat]) -> CGFloat {
    let s = item.displayText
    if let w = cache[s] { return w }
    let w = NSHostingView(rootView: Text(s).font(Font(f)).fixedSize()
        .padding(.trailing, -item.trailingTrim)).fittingSize.width
    cache[s] = w
    return w
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    let words = splitTextIntoWords(longSample)
    print("[\(label)] 切字（前 60 個）：" + words.prefix(60).map { WordFlowLayout.isAnnotationWord($0) ? "〔\($0)〕" : $0 }.joined(separator: "|"))
    print("[\(label)] 被當成標註的字：\(words.filter { WordFlowLayout.isAnnotationWord($0) })")
    print("[\(label)] 段落起點：\(paragraphBreakWordIndices(in: longSample).sorted())  總字數：\(words.count)")

    for (name, f) in fonts {
        var cache: [String: CGFloat] = [:]
        var overflowLines = 0, totalLines = 0, overflowWidths = Set<Int>()
        var maxOver: CGFloat = 0
        for sample in [issueSample, longSample] {
            let ws = splitTextIntoWords(sample)
            let breaks = paragraphBreakWordIndices(in: sample)
            for width in stride(from: 200, through: 800, by: 1) {
                let layout = WordFlowLayout(words: ws, highlightedCharCount: 0, font: f,
                                            paragraphBreakBeforeWordIndices: breaks,
                                            containerWidth: CGFloat(width))
                for line in layout.buildLines(items: layout.buildItems()) {
                    totalLines += 1
                    let real = line.reduce(0) { $0 + actualWidth($1, f, cache: &cache) }
                    if real > CGFloat(width) + 0.01, line.count > 1 {
                        overflowLines += 1
                        overflowWidths.insert(width)
                        maxOver = max(maxOver, real - CGFloat(width))
                    }
                }
            }
        }
        print(String(format: "[%@] %-6@ 寬度 200～800 共 %d 行，超出容器的行 %d（%d 種寬度會出事），最多超出 %.1f pt",
                     label, name as NSString, totalLines, overflowLines, overflowWidths.count, maxOver))
    }

    // 畫圖：issue 的範例在 sans 20pt、寬 540 時原版會出事
    for (file, sample, width) in [("issue", issueSample, 540.0), ("long", longSample, 520.0)] {
        let f = fonts[0].1
        let view = WordFlowLayout(words: splitTextIntoWords(sample), highlightedCharCount: 12, font: f,
                                  paragraphBreakBeforeWordIndices: paragraphBreakWordIndices(in: sample),
                                  containerWidth: width)
            .frame(width: width)
            .padding(16)
            .background(Color.black)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        if let img = renderer.nsImage, let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
            try! png.write(to: URL(fileURLWithPath: "\(outDir)/\(label)-\(file).png"))
        }
    }

    // ── 捲動位置（issue #1）：每個字的位置只跟它在第幾行有關，而且跟畫出來的一致 ──
    var scrollFailures = 0
    func scrollCheck(_ name: String, _ ok: Bool, _ detail: String) {
        if !ok { scrollFailures += 1 }
        print("[\(label)] \(ok ? "✅" : "❌") \(name)：\(detail)")
    }
    final class Box { var positions: [Int: CGFloat] = [:] }
    let scrollText = (0..<12).map { _ in longSample }.joined(separator: "\n\n")
    let scrollWords = splitTextIntoWords(scrollText)
    let scrollBreaks = paragraphBreakWordIndices(in: scrollText)
    func render(_ f: NSFont, offset: CGFloat, viewport: CGFloat, highlighted: Int = 0) -> (positions: [Int: CGFloat], height: CGFloat) {
        let box = Box()
        let view = WordFlowLayout(words: scrollWords, highlightedCharCount: highlighted, font: f,
                                  paragraphBreakBeforeWordIndices: scrollBreaks, containerWidth: 476,
                                  scrollOffset: offset, viewportHeight: viewport)
            .frame(width: 476)
            .onPreferenceChange(WordYPreferenceKey.self) { box.positions = $0 }
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 476, height: 100_000)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        return (box.positions, host.fittingSize.height)
    }
    // 加上 24pt（瓦基用的「特大」）：這個字級實際行高跟估計值差 1 pt，拿掉固定行高時抓得到
    for (name, f) in fonts + [("sans24", NSFont.systemFont(ofSize: 24, weight: .semibold))] {
        let rowHeight = ceil(f.ascender - f.descender + f.leading)
        // 不省略任何一行：實際排出來的總高度，要等於算出來的最後一行底部
        let full = render(f, offset: 0, viewport: 0)
        let modelBottom = (full.positions.values.max() ?? 0) + rowHeight / 2
        scrollCheck("\(name) 畫出來的高度＝算出來的", abs(full.height - modelBottom) < 0.5,
                    "實際 \(full.height)，算出來 \(modelBottom)（\(scrollWords.count) 個字）")
        // 不同捲動位置（上方省略的行數不同），同一個字的位置要一樣
        var worst: CGFloat = 0
        var compared = 0
        for base in stride(from: -600.0, through: -6000.0, by: -900.0) {
            let a = render(f, offset: base, viewport: 331).positions
            for up in [rowHeight + 8, (rowHeight + 8) * 3, 400] {
                let b = render(f, offset: base + up, viewport: 331).positions
                for k in Set(a.keys).intersection(b.keys) { worst = max(worst, abs(a[k]! - b[k]!)); compared += 1 }
            }
        }
        scrollCheck("\(name) 往上捲之後同一個字的位置不變", worst == 0 && compared > 0, "比了 \(compared) 次，最多差 \(worst) pt")
        // 從講稿中間開始播放：目前那個字還沒排版時回報的位置，要等於捲過去之後的位置
        let target = scrollWords.count * 2 / 3
        let highlighted = scrollWords.prefix(target).reduce(0) { $0 + $1.count + 1 }
        let fromTop = render(f, offset: 0, viewport: 331, highlighted: highlighted).positions[target]
        let there = render(f, offset: -((fromTop ?? 0) - 50), viewport: 331, highlighted: highlighted).positions[target]
        scrollCheck("\(name) 還沒排版的起點位置＝捲過去之後的位置", fromTop != nil && fromTop == there,
                    "還沒排版 \(fromTop ?? -1)，捲過去 \(there ?? -1)")
    }
    print("[\(label)] 捲動位置檢查：\(scrollFailures == 0 ? "全部通過" : "有 \(scrollFailures) 條沒過")")
    if scrollFailures > 0 { exit(1) }
}

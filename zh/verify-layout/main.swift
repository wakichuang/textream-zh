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
}

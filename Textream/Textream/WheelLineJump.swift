//
//  WheelLineJump.swift
//  Textream
//
//  繁中改版：語音追蹤模式的滾輪逐行跳轉（移植 Textream for Windows 第 5.4 步）。
//  滾一格就從目前那一行往前或往後跳一行，直接改「目前位置」，跟點字跳轉走同一條路
//  （SpeechRecognizer.jumpTo）；聆聽中、暫停中都可以用，接著講就從新位置往下比對。
//  這裡只放純計算，方便 zh/verify-scroll 不開 Xcode 就能測。
//

import AppKit

enum WheelLineJump {
    /// 把滾動量換成「往後跳幾行」（負數＝往前）。
    /// 觸控板（精確捲動）累積滿一行高才算一行；一般滑鼠滾輪每一格至少一行。
    /// 方向跟系統捲動設定一致：內容往下移（deltaY 為正）＝看前面＝往前跳。
    struct Accumulator {
        private(set) var pending: CGFloat = 0

        mutating func add(deltaY: CGFloat, precise: Bool, lineHeight: CGFloat) -> Int {
            guard deltaY != 0 else { return 0 }
            if !precise {
                pending = 0
                let lines = max(1, Int(abs(deltaY).rounded()))
                return deltaY > 0 ? -lines : lines
            }
            guard lineHeight > 0 else { return 0 }
            pending += deltaY // 用 pt 累積，不先除行高，避免 0.9999 行被截成 0
            let lines = Int(pending / lineHeight) // 往零截斷，剩下的留給下一次
            pending -= CGFloat(lines) * lineHeight
            return -lines
        }
    }

    /// 一行的高度，跟 WordFlowLayout 排版用的行高一樣（字高＋行距）。
    static func lineHeight(for font: NSFont) -> CGFloat {
        let rowHeight = ceil(font.ascender - font.descender + font.leading)
        let lineSpacing: CGFloat = rowHeight / font.pointSize > 1.5 ? 2 : 8
        return rowHeight + lineSpacing
    }

    /// 從 fromWord 所在那一行往後（正）或往前（負）數 lines 行，回傳那一行第一個字。
    /// positions 是畫面量到的每個字的垂直中心，只有看得到附近的字（遠的被省略），
    /// 超出量得到的範圍就停在最遠那一行，下一格再繼續；不會跳過最後一行（跳到結尾會被當成讀完）。
    static func targetWord(positions: [Int: CGFloat], fromWord: Int, lines: Int) -> Int? {
        guard !positions.isEmpty else { return nil }
        // 同一行的字垂直中心一樣，由上到下排成一行一行，每行記第一個字
        var rows: [(y: CGFloat, first: Int)] = []
        for (word, y) in positions.sorted(by: { $0.value < $1.value }) {
            if let last = rows.last, abs(last.y - y) <= 2 {
                rows[rows.count - 1].first = min(last.first, word)
            } else {
                rows.append((y: y, first: word))
            }
        }
        // fromWord 所在的行：第一個字不超過 fromWord 的最後一行
        let current = rows.lastIndex { $0.first <= fromWord } ?? 0
        let target = max(0, min(rows.count - 1, current + lines))
        return rows[target].first
    }

    /// 第 index 個字在講稿裡的字元位置（每個字後面算一個空白，跟 WordItem.charOffset 一樣）。
    static func charOffset(ofWord index: Int, in words: [String]) -> Int {
        words.prefix(max(0, index)).reduce(0) { $0 + $1.count + 1 }
    }
}

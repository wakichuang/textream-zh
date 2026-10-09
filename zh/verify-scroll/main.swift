import AppKit

// 滾輪逐行跳轉回歸檢查（WheelLineJump.swift）。任何一條沒過，結束碼為 1。
var failed = 0
func check<T: Equatable>(_ name: String, _ actual: T, _ expected: T) {
    let ok = actual == expected
    if !ok { failed += 1 }
    print("\(ok ? "✅" : "❌") \(name)：得到 \(actual)，應為 \(expected)")
}

// 四行講稿：每行第一個字 0、5、10、15，行高 30（第三行前面有段落分隔，間距大一點）
let fourLines: [Int: CGFloat] = {
    var p: [Int: CGFloat] = [:]
    for w in 0...4 { p[w] = 10 }
    for w in 5...9 { p[w] = 40 }
    for w in 10...14 { p[w] = 84 }
    for w in 15...17 { p[w] = 114 }
    return p
}()

print("— 跳到哪一行 —")
check("從第二行往後一格", WheelLineJump.targetWord(positions: fourLines, fromWord: 7, lines: 1), 10)
check("從第二行往後兩格", WheelLineJump.targetWord(positions: fourLines, fromWord: 7, lines: 2), 15)
check("往後超過最後一行，停在最後一行開頭（不跳到結尾）", WheelLineJump.targetWord(positions: fourLines, fromWord: 7, lines: 9), 15)
check("從第二行往前一格", WheelLineJump.targetWord(positions: fourLines, fromWord: 7, lines: -1), 0)
check("往前超過開頭，停在第一行", WheelLineJump.targetWord(positions: fourLines, fromWord: 7, lines: -9), 0)
check("從第三行中間往前一格，到第二行開頭", WheelLineJump.targetWord(positions: fourLines, fromWord: 12, lines: -1), 5)
check("從行首往後一格", WheelLineJump.targetWord(positions: fourLines, fromWord: 10, lines: 1), 15)

var culled = fourLines
for w in 0...4 { culled[w] = nil }
check("上面被省略的行量不到，停在量得到的最遠那行", WheelLineJump.targetWord(positions: culled, fromWord: 12, lines: -5), 5)

var jitter = fourLines
jitter[7] = 40.4
check("同一行的字中心差一點點仍算同一行，往前一格到上一行開頭", WheelLineJump.targetWord(positions: jitter, fromWord: 7, lines: -1), 0)
check("沒有量到任何字", WheelLineJump.targetWord(positions: [:], fromWord: 0, lines: 1), nil)

print("— 滾動量換成行數 —")
var mouse = WheelLineJump.Accumulator()
check("滑鼠滾輪往下一格（內容往上）＝往後一行", mouse.add(deltaY: -1, precise: false, lineHeight: 30), 1)
check("滑鼠滾輪往上一格＝往前一行", mouse.add(deltaY: 1, precise: false, lineHeight: 30), -1)
check("滑鼠滾輪加速三格＝三行", mouse.add(deltaY: -3, precise: false, lineHeight: 30), 3)
check("滑鼠滾輪很小的量也至少一行", mouse.add(deltaY: -0.2, precise: false, lineHeight: 30), 1)
check("沒有動", mouse.add(deltaY: 0, precise: false, lineHeight: 30), 0)

var pad = WheelLineJump.Accumulator()
check("觸控板滑 10 pt，還不到一行", pad.add(deltaY: -10, precise: true, lineHeight: 30), 0)
check("觸控板再滑 10 pt，還不到一行", pad.add(deltaY: -10, precise: true, lineHeight: 30), 0)
check("觸控板累積滿 30 pt，往後一行", pad.add(deltaY: -10, precise: true, lineHeight: 30), 1)
check("觸控板一口氣滑 100 pt，往後三行", pad.add(deltaY: -100, precise: true, lineHeight: 30), 3)
check("觸控板往回滑 40 pt（抵掉剩下的 10 pt 之後），往前一行", pad.add(deltaY: 40, precise: true, lineHeight: 30), -1)

print("— 字元位置與連續滾動 —")
check("第 0 個字", WheelLineJump.charOffset(ofWord: 0, in: ["一", "二", "ab"]), 0)
check("第 2 個字（前面每字加一個空白）", WheelLineJump.charOffset(ofWord: 2, in: ["一", "二", "ab"]), 4)
// 連續轉三格：每格從上一格跳到的那行接著數
var at = 2
var steps: [Int] = []
var wheel = WheelLineJump.Accumulator()
for _ in 0..<3 {
    let lines = wheel.add(deltaY: -1, precise: false, lineHeight: 30)
    if let t = WheelLineJump.targetWord(positions: fourLines, fromWord: at, lines: lines) { at = t; steps.append(t) }
}
check("連續往下轉三格", steps, [5, 10, 15])

check("行高與排版一致（系統字 20pt）",
      WheelLineJump.lineHeight(for: .systemFont(ofSize: 20, weight: .semibold)),
      ceil({ let f = NSFont.systemFont(ofSize: 20, weight: .semibold); return f.ascender - f.descender + f.leading }()) + 8)

print(failed == 0 ? "全部通過" : "有 \(failed) 條沒過")
exit(failed == 0 ? 0 : 1)

import Foundation

// 編輯模式與播放模式的位置互換（EditorPlaybackPosition.swift）回歸檢查。任何一條沒過，結束碼為 1。
var failed = 0
func check<T: Equatable>(_ name: String, _ actual: T, _ expected: T) {
    let ok = actual == expected
    if !ok { failed += 1 }
    print("\(ok ? "✅" : "❌") \(name)：得到 \(actual)，應為 \(expected)")
}

/// 編輯器裡某段文字開頭的游標位置（UTF-16）。
func caret(before marker: String, in text: String) -> Int {
    (text as NSString).range(of: marker).location
}
/// 講稿裡某段文字開頭的位置（講稿的字之間有空白）。
func scriptStart(of marker: String, words: [String]) -> Int {
    let script = words.joined(separator: " ")
    let compact = marker.filter { !$0.isWhitespace }
    // 從頭找：第一個「去掉空白之後以 marker 開頭」的位置
    var index = script.startIndex
    while index < script.endIndex {
        if script[index...].filter({ !$0.isWhitespace }).hasPrefix(compact), !script[index].isWhitespace {
            return script.distance(from: script.startIndex, to: index)
        }
        index = script.index(after: index)
    }
    return -1
}

// 編輯器原文：前面有空行（播放時會被修剪）、中英混排、全形標點、段落之間空一行
let editor = "\n\n卡片盒筆記的核心，是用自己的話重寫。\n\n我用 Heptabase 寫了 5,000 張卡片。\n「每一張」卡片只寫一個觀點。\n"
let words = splitTextIntoWords(editor.trimmingCharacters(in: .whitespacesAndNewlines))
let script = words.joined(separator: " ")
print("切字：" + words.joined(separator: "|"))

print("— 編輯器游標 → 播放起點 —")
check("游標在最前面", EditorPlaybackPosition.scriptOffset(editorText: editor, caretUTF16: 0, words: words), 0)
check("游標在第二段開頭", EditorPlaybackPosition.scriptOffset(editorText: editor, caretUTF16: caret(before: "我用", in: editor), words: words),
      scriptStart(of: "我用", words: words))
check("游標在中文字中間（「自己」的「己」前面）", EditorPlaybackPosition.scriptOffset(editorText: editor, caretUTF16: caret(before: "己的話", in: editor), words: words),
      scriptStart(of: "己的話", words: words))
check("游標在英文單字中間，從那個單字開頭開始", EditorPlaybackPosition.scriptOffset(editorText: editor, caretUTF16: caret(before: "tabase", in: editor), words: words),
      scriptStart(of: "Heptabase", words: words))
check("游標在數字中間，從那個數字開頭開始", EditorPlaybackPosition.scriptOffset(editorText: editor, caretUTF16: caret(before: "000 張", in: editor), words: words),
      scriptStart(of: "5,000", words: words))
check("游標在黏住的標點前面（「核心，」），從「心」開始", EditorPlaybackPosition.scriptOffset(editorText: editor, caretUTF16: caret(before: "，是用", in: editor), words: words),
      scriptStart(of: "心，", words: words))
check("游標在開括號前面，從「「每」開始", EditorPlaybackPosition.scriptOffset(editorText: editor, caretUTF16: caret(before: "「每", in: editor), words: words),
      scriptStart(of: "「每", words: words))
check("游標在最後面（剛打完字），從頭開始", EditorPlaybackPosition.scriptOffset(editorText: editor, caretUTF16: (editor as NSString).length, words: words), 0)
check("游標在最後一個字之後、換行之前，從頭開始", EditorPlaybackPosition.scriptOffset(editorText: editor, caretUTF16: (editor as NSString).length - 1, words: words), 0)
check("游標超出範圍，從頭開始", EditorPlaybackPosition.scriptOffset(editorText: editor, caretUTF16: 9_999, words: words), 0)

print("— 播放停下 → 編輯器游標 —")
let afterCore = scriptStart(of: "是用", words: words)
check("停在「是用」前面，游標放在編輯器的「是用」前面",
      EditorPlaybackPosition.editorCaret(editorText: editor, scriptOffset: afterCore, words: words), caret(before: "是用", in: editor))
// 念完第一段最後一個字（位置在「寫。」這個字的結尾），游標跳過換行，放在下一段開頭
let endOfFirst = scriptStart(of: "寫。", words: words) + "寫。".count
check("念完一段，游標放在下一段開頭（跳過換行）",
      EditorPlaybackPosition.editorCaret(editorText: editor, scriptOffset: endOfFirst, words: words), caret(before: "我用", in: editor))
check("停在最前面，游標放在第一個字前面（跳過前面的空行）",
      EditorPlaybackPosition.editorCaret(editorText: editor, scriptOffset: 0, words: words), caret(before: "卡片盒", in: editor))
check("整篇念完，游標放在最後面",
      EditorPlaybackPosition.editorCaret(editorText: editor, scriptOffset: script.count, words: words), (editor as NSString).length)

print("— 來回換算 —")
// 每個字的開頭：停下 → 游標 → 再按播放，要從同一個字開始
var offset = 0
var roundTripFailures: [String] = []
for word in words {
    let back = EditorPlaybackPosition.scriptOffset(
        editorText: editor,
        caretUTF16: EditorPlaybackPosition.editorCaret(editorText: editor, scriptOffset: offset, words: words),
        words: words)
    if back != offset { roundTripFailures.append("\(word)（\(offset)→\(back)）") }
    offset += word.count + 1
}
check("每個字停下再按播放都從同一個字開始（\(words.count) 個字）", roundTripFailures, [])

// 表情符號與組合字元：UTF-16 長度跟字數不同
let emoji = "第一句👍很好。\n第二句。"
let emojiWords = splitTextIntoWords(emoji)
check("表情符號後面的字（UTF-16 位置）", EditorPlaybackPosition.scriptOffset(editorText: emoji, caretUTF16: caret(before: "很好", in: emoji), words: emojiWords),
      scriptStart(of: "很好", words: emojiWords))
check("表情符號後面的字（反過來）", EditorPlaybackPosition.editorCaret(editorText: emoji, scriptOffset: scriptStart(of: "很好", words: emojiWords), words: emojiWords),
      caret(before: "很好", in: emoji))

print(failed == 0 ? "全部通過" : "有 \(failed) 條沒過")
exit(failed == 0 ? 0 : 1)

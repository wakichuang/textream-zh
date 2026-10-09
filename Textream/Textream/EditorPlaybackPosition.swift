//
//  EditorPlaybackPosition.swift
//  Textream
//
//  繁中改版：編輯模式與播放模式的位置互換。
//  按播放時從編輯器游標所在的字開始；停止播放時，把游標放回停下的地方，下次再按播放就接著講。
//  切字（splitTextIntoWords）只用空白切開、把標點黏上去，非空白字元的順序完全不變，
//  所以兩邊用「前面有幾個非空白字元」換算。這裡只放純計算，方便 zh/verify-position 測試。
//

import Foundation

enum EditorPlaybackPosition {
    /// 編輯器游標（UTF-16 位置）→ 開始播放的講稿位置（words 以一個空白連接），對齊到游標所在那個字的開頭。
    /// 游標在最後一個字之後（例如剛打完字、或上次已經念完），從頭開始。
    static func scriptOffset(editorText: String, caretUTF16: Int, words: [String]) -> Int {
        let text = editorText as NSString
        let caret = max(0, min(caretUTF16, text.length))
        let before = text.substring(to: caret).reduce(0) { $0 + ($1.isWhitespace ? 0 : 1) }
        var seen = 0
        var offset = 0
        for word in words {
            if before < seen + word.count { return offset }
            seen += word.count
            offset += word.count + 1
        }
        return 0
    }

    /// 播放停下的講稿位置 → 編輯器游標（UTF-16 位置），放在下一個還沒念的字前面。
    static func editorCaret(editorText: String, scriptOffset: Int, words: [String]) -> Int {
        let script = words.joined(separator: " ")
        let read = script.prefix(max(0, scriptOffset)).reduce(0) { $0 + ($1.isWhitespace ? 0 : 1) }
        var seen = 0
        var utf16 = 0
        for character in editorText {
            if !character.isWhitespace {
                if seen == read { return utf16 }
                seen += 1
            }
            utf16 += character.utf16.count
        }
        return utf16
    }
}

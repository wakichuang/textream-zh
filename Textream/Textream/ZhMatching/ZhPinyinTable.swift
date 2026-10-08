//
//  ZhPinyinTable.swift
//  Textream（繁中改版）
//
//  Ported from Textream for Windows (PinyinTable.cs).
//

import Foundation

/// Han character → every toneless pinyin reading, from `unihan-pinyin.tsv`
/// (generated from Unicode Unihan; see zh/THIRD_PARTY_NOTICES.md).
/// Matching compares reading sets, so homophones (已／以), simplified output
/// (閱／阅) and polyphones (行 = hang / heng / xing) all count as the same character.
final class ZhPinyinTable {
    private let readings: [UInt32: [String]]

    /// The table bundled with the app, loaded on first use (~44,000 characters).
    static let shared: ZhPinyinTable = {
        if let url = Bundle.main.url(forResource: "unihan-pinyin", withExtension: "tsv"),
           let table = ZhPinyinTable(contentsOf: url) {
            return table
        }
        return ZhPinyinTable(tsv: "")
    }()

    /// Each line is `字<TAB>reading reading…`; lines starting with `#` are comments.
    init(tsv: String) {
        var readings: [UInt32: [String]] = [:]
        var syllables: [Substring: String] = [:] // share one String per syllable
        for line in tsv.split(separator: "\n", omittingEmptySubsequences: true) {
            guard line.first != "#",
                  let tab = line.firstIndex(of: "\t"),
                  let scalar = line.unicodeScalars.first else { continue }
            readings[scalar.value] = line[line.index(after: tab)...]
                .split(separator: " ", omittingEmptySubsequences: true)
                .map { syllable in
                    if let shared = syllables[syllable] { return shared }
                    let value = String(syllable)
                    syllables[syllable] = value
                    return value
                }
        }
        self.readings = readings
    }

    convenience init?(contentsOf url: URL) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        self.init(tsv: text)
    }

    var count: Int { readings.count }

    /// Comparison keys for one character: every reading of a Han character, or the
    /// character itself when the table has no entry (kana, rare characters).
    func soundKeys(of character: String) -> [String] {
        if let scalar = character.unicodeScalars.first, let keys = readings[scalar.value] {
            return keys
        }
        return [character]
    }
}

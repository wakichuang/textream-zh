"""從 SpeechRecognizer.swift 抽出原版的比對函式，包成 LegacyMatcher（測試對照組）。

用法：python3 make_legacy.py <SpeechRecognizer.swift> <輸出.swift>
抽的是 charLevelMatch 到檔尾的 normalize（原版比對的全部），一字不改；
matchCharacters 的合併與投票邏輯在下面的 match() 照原版重寫一次。
"""
import sys

source = open(sys.argv[1], encoding='utf-8').read().split('\n')
start = next(i for i, l in enumerate(source) if l.startswith('    private func charLevelMatch(spoken: String) -> Int {'))
end = max(i for i, l in enumerate(source) if l == '}')  # class 的右括號
body = '\n'.join(source[start:end])

out = '''import Foundation

/// 原版比對（從 SpeechRecognizer.swift 抽出），測試對照組。
final class LegacyMatcher {
    let sourceText: String
    var matchStartOffset = 0
    var recognizedCharCount = 0
    var recentMatchPositions: [Int] = []
    let annotationRanges: [Range<Int>]

    init(words: [String]) {
        sourceText = words.joined(separator: " ")
        annotationRanges = SpeechTextAlignment.annotationRanges(in: sourceText)
        recognizedCharCount = advancePastAnnotations(from: 0)
        matchStartOffset = recognizedCharCount
    }

    func advancePastAnnotations(from offset: Int) -> Int {
        SpeechTextAlignment.advancePastAnnotations(in: sourceText, ranges: annotationRanges, from: offset)
    }

    /// 原版 matchCharacters 去掉跳轉防護之後的部分。
    func match(_ spoken: String) {
        guard !spoken.isEmpty else { return }
        let charResult = charLevelMatch(spoken: spoken)
        let wordResult = wordLevelMatch(spoken: spoken)
        let best = SpeechTextAlignment.bestOffset(characterResult: charResult, wordResult: wordResult)
        let rawCandidate = min(matchStartOffset + best, sourceText.count)
        let candidate = advancePastAnnotations(from: rawCandidate)
        guard candidate > recognizedCharCount else { return }
        recentMatchPositions.append(candidate)
        if recentMatchPositions.count > 3 { recentMatchPositions.removeFirst() }
        let confirmed = recentMatchPositions.filter { abs($0 - candidate) <= 10 }.count >= 2
        if SpeechTextAlignment.shouldCommit(characterResult: charResult, wordResult: wordResult,
                                            current: recognizedCharCount, rawCandidate: rawCandidate,
                                            candidate: candidate, confirmed: confirmed) {
            recognizedCharCount = candidate
        }
    }

''' + body + '\n}\n'
open(sys.argv[2], 'w', encoding='utf-8').write(out)

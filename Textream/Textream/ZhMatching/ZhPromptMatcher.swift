//
//  ZhPromptMatcher.swift
//  Textream（繁中改版）
//
//  Ported from Textream for Windows (PromptMatcher.cs, MatchUnit.cs), which
//  itself ports Textream iOS's PromptMatcher: character level + word level,
//  merge, 2-of-3 vote, never move backward.
//

import Foundation

/// Maps the speech transcript onto the script and reports how far the speaker
/// has read, as a character offset into `text` (the script's words joined by
/// single spaces — the same `sourceText` SpeechRecognizer uses).
///
/// Differences from the original matcher:
/// - "Equal" for Chinese compares reading sets (homophones, simplified output,
///   polyphones); numbers are normalized to Arabic digits; Latin words use
///   NFKC + lowercase + the original fuzzy match.
/// - Anti-drag: after a skip or a dropped unit, matches only count once they
///   are consecutive, so stray homophones in an ad-lib don't pull the highlight.
/// - Anchor: when the speaker skips a subheading, a sentence or rewords and
///   comes back, search up to `anchorLookAhead` units ahead for the run being
///   read right now and jump there.
final class ZhPromptMatcher {
    /// On a mismatch, how many units to look ahead on either side.
    static let maxSkip = 5
    /// Anchor: how far ahead to search (readable units) — about a minute and a
    /// half of reading, enough to cover a skipped subheading or a paragraph or two.
    static let anchorLookAhead = 400
    /// Anchor: consecutive units needed to jump; more the further the jump
    /// (see `runNeededToJump`).
    static let anchorBaseRun = 5
    /// Anchor: the run must end within the last few units of the transcript —
    /// that is what "being read right now" means. The last unit or two of a
    /// partial result often still changes.
    static let anchorTailSlack = 2

    /// Follow state; SpeechRecognizer keeps these as its own properties.
    struct State {
        /// Highlight position. Only moves forward (except explicit jumps).
        var recognized = 0
        /// Where in the script this run of transcript starts being matched.
        var matchStart = 0
        var recentPositions: [Int] = []
        /// Transcript already accounted for (after a tap jump or an anchor jump);
        /// only what follows it is matched.
        var anchorPrefix = ""
    }

    let text: String
    let characterCount: Int
    private let pinyin: ZhPinyinTable
    private let annotationRanges: [Range<Int>]
    private let units: [ZhMatchUnit]
    private let slots: [Slot]

    init(words: [String], pinyin: ZhPinyinTable = .shared) {
        self.pinyin = pinyin
        text = words.joined(separator: " ")
        characterCount = text.count
        annotationRanges = SpeechTextAlignment.annotationRanges(in: text)
        units = ZhMatchUnit.fromScript(words: words, pinyin: pinyin)
        slots = units.flatMap { unit in
            unit.isAnnotation
                ? [Slot(isSkip: true, character: nil, start: unit.start)]
                : unit.characters.map { Slot(isSkip: false, character: $0, start: $0.start) }
        }
    }

    func advancePastAnnotations(from offset: Int) -> Int {
        SpeechTextAlignment.advancePastAnnotations(in: text, ranges: annotationRanges, from: offset)
    }

    /// Mac entry point. `fullTranscript` is everything the current recognition
    /// task has heard (Apple's recognizer keeps one growing transcript for up to
    /// about a minute, unlike sherpa-onnx which restarts every sentence).
    /// After an anchor jump the transcript so far is set aside and matching
    /// restarts from the new position — the equivalent of Windows'
    /// `RestartFromCurrentProgress` at a sentence end.
    func follow(fullTranscript: String, state: inout State) {
        var spoken = fullTranscript
        if !state.anchorPrefix.isEmpty {
            // Trim by the common prefix that survived the recognizer's revisions,
            // but never less than the anchor length minus a small slack — a
            // revision very early in the transcript would otherwise leak the
            // whole earlier transcript back into matching.
            let common = zip(state.anchorPrefix, fullTranscript).prefix(while: { $0 == $1 }).count
            let trimLength = min(fullTranscript.count, max(common, state.anchorPrefix.count - 24))
            spoken = String(fullTranscript.dropFirst(trimLength))
        }
        guard !spoken.isEmpty else { return }

        if match(spoken, state: &state) {
            state.matchStart = state.recognized
            state.anchorPrefix = fullTranscript
        }
    }

    /// The speaker paused and started talking again: the next words begin a new
    /// sentence, matched from the current position. sherpa-onnx does this itself
    /// at every endpoint; Apple's recognizer keeps one transcript, so
    /// SpeechRecognizer calls this when voice activity resumes after silence.
    /// Without it, the drift from a long ad-lib accumulates across sentences
    /// and a stray common phrase can confirm a far jump (ZH-20).
    func sentenceBreak(fullTranscript: String, state: inout State) {
        guard !fullTranscript.isEmpty else { return }
        state.matchStart = state.recognized
        state.recentPositions = []
        state.anchorPrefix = fullTranscript
    }

    /// Windows' `Match`: `transcript` is everything heard since matching last
    /// restarted at `state.matchStart`. Returns true when the anchor jumped.
    @discardableResult
    func match(_ transcript: String, state: inout State) -> Bool {
        guard !transcript.isEmpty, state.matchStart < characterCount else { return false }

        let spokenUnits = ZhMatchUnit.fromTranscript(transcript, pinyin: pinyin)
        let spokenCharacters = spokenUnits.flatMap(\.characters)
        let matchStart = state.matchStart

        let firstSlot = slots.firstIndex { $0.start >= matchStart } ?? -1
        let characterEnd = Self.scan(
            source: slots, first: firstSlot, spoken: spokenCharacters,
            isSkip: { $0.isSkip },
            matches: { slot, spoken in Self.charactersMatch(slot.character!, spoken) },
            runNeeded: { $0.character?.isHan == true ? 2 : 3 }
        )
        let characterResult = progress(end: characterEnd, first: firstSlot, count: slots.count,
                                       matchStart: matchStart) { slots[$0].start }

        let firstUnit = units.firstIndex { $0.start >= matchStart } ?? -1
        let wordEnd = Self.scan(
            source: units, first: firstUnit, spoken: spokenUnits,
            isSkip: { $0.isAnnotation },
            matches: Self.unitsMatch,
            runNeeded: { _ in 2 }
        )
        let wordResult = progress(end: wordEnd, first: firstUnit, count: units.count,
                                  matchStart: matchStart) { units[$0].start }

        let best = SpeechTextAlignment.bestOffset(characterResult: characterResult, wordResult: wordResult)
        let rawCandidate = min(matchStart + best, characterCount)
        let candidate = advancePastAnnotations(from: rawCandidate)
        if candidate > state.recognized {
            state.recentPositions.append(candidate)
            if state.recentPositions.count > 3 {
                state.recentPositions.removeFirst()
            }
            let confirmed = state.recentPositions.filter { abs($0 - candidate) <= 10 }.count >= 2
            if SpeechTextAlignment.shouldCommit(
                characterResult: characterResult,
                wordResult: wordResult,
                current: state.recognized,
                rawCandidate: rawCandidate,
                candidate: candidate,
                confirmed: confirmed
            ) {
                state.recognized = candidate
            }
        }

        if let anchor = findAnchor(firstUnit: firstUnit, spoken: spokenUnits, recognized: state.recognized),
           anchor > state.recognized {
            state.recognized = anchor
            state.recentPositions = []
            return true
        }
        return false
    }

    // MARK: - Scan

    /// Shared by both levels: walk the script from `first` and the transcript
    /// from its start together while they match. On a mismatch, look ahead in
    /// the transcript (the recognizer added units), then in the script (the
    /// speaker skipped a few), otherwise drop this transcript unit.
    ///
    /// Returns the script index read up to (exclusive). The very first unit of a
    /// transcript matching the next script unit counts at once (plain reading);
    /// otherwise `runNeeded` consecutive direct matches are required, and any
    /// skip or drop breaks the run. This is the anti-drag rule: stray homophones
    /// in an ad-lib do match the script, but rarely several in a row.
    private static func scan<Source, Spoken>(
        source: [Source],
        first: Int,
        spoken: [Spoken],
        isSkip: (Source) -> Bool,
        matches: (Source, Spoken) -> Bool,
        runNeeded: (Source) -> Int
    ) -> Int {
        guard first >= 0 else { return first }
        var si = first
        var pi = 0
        var confirmedEnd = first
        var tentative = false // matched units after confirmedEnd that don't count yet
        var run = 0
        var atStart = true // nothing matched, skipped or dropped yet

        while si < source.count && pi < spoken.count {
            if isSkip(source[si]) {
                si += 1
                if !tentative {
                    confirmedEnd = si
                }
                continue
            }
            if matches(source[si], spoken[pi]) {
                run += 1
                if atStart || run >= runNeeded(source[si]) {
                    confirmedEnd = si + 1
                    tentative = false
                } else {
                    tentative = true
                }
                atStart = false
                si += 1
                pi += 1
                continue
            }

            atStart = false
            run = 0
            var found = false
            let maxSpokenSkip = min(maxSkip, spoken.count - pi - 1)
            if maxSpokenSkip >= 1 {
                for skip in 1...maxSpokenSkip where matches(source[si], spoken[pi + skip]) {
                    pi += skip
                    found = true
                    break
                }
            }
            if found { continue }

            let maxSourceSkip = min(maxSkip, source.count - si - 1)
            if maxSourceSkip >= 1 {
                for skip in 1...maxSourceSkip where !isSkip(source[si + skip]) && matches(source[si + skip], spoken[pi]) {
                    si += skip
                    found = true
                    break
                }
            }
            if !found {
                pi += 1
            }
        }

        if !tentative {
            while confirmedEnd < source.count && isSkip(source[confirmedEnd]) {
                confirmedEnd += 1
            }
        }
        return confirmedEnd
    }

    // MARK: - Anchor

    /// Search from this run's start to `anchorLookAhead` readable units past the
    /// current position for the longest run matching the end of the transcript
    /// (longest common substring). Long enough → return the position after it;
    /// ties go to the nearest. Searching from the run's start lets a growing
    /// partial result keep finding the same run.
    private func findAnchor(firstUnit: Int, spoken: [ZhMatchUnit], recognized: Int) -> Int? {
        guard firstUnit >= 0, spoken.count >= Self.anchorBaseRun else { return nil }

        let currentUnit = units.firstIndex { $0.start >= recognized } ?? -1
        var readable: [Int] = []
        var readableBeforeCurrent = 0
        for i in firstUnit..<units.count {
            if units[i].isAnnotation { continue }
            if currentUnit >= 0 && i < currentUnit {
                readableBeforeCurrent += 1
            } else if readable.count - readableBeforeCurrent >= Self.anchorLookAhead {
                break
            }
            readable.append(i)
        }

        // run[j]: length of the match ending at the current script unit and at
        // transcript unit j, updated row by row.
        var run = [Int](repeating: 0, count: spoken.count + 1)
        var bestLength = 0
        var bestEnd = -1
        for (i, unitIndex) in readable.enumerated() {
            let unit = units[unitIndex]
            for j in stride(from: spoken.count, through: 1, by: -1) {
                run[j] = Self.unitsMatch(unit, spoken[j - 1]) ? run[j - 1] + 1 : 0
                if j < spoken.count - Self.anchorTailSlack || run[j] <= bestLength {
                    continue
                }
                let distance = max(0, i - run[j] + 1 - readableBeforeCurrent)
                if run[j] >= Self.runNeededToJump(distance) {
                    bestLength = run[j]
                    bestEnd = unitIndex
                }
            }
        }
        guard bestEnd >= 0 else { return nil }

        var next = bestEnd + 1
        while next < units.count && units[next].isAnnotation {
            next += 1
        }
        return next < units.count ? units[next].start : characterCount
    }

    /// Jumping `distance` readable units ahead needs this many consecutive
    /// matches: 5, plus one more for every 50 units. (Windows started at one per
    /// 100 and was lured 200 characters ahead by a common phrase — test ZH-23.)
    static func runNeededToJump(_ distance: Int) -> Int {
        anchorBaseRun + distance / 50
    }

    // MARK: - Helpers

    /// Scan end → characters advanced from the match start: the start of the
    /// next slot, or the end of the script when everything was read.
    private func progress(end: Int, first: Int, count: Int, matchStart: Int, startOf: (Int) -> Int) -> Int {
        guard first >= 0, end > first else { return 0 }
        let position = end < count ? startOf(end) : characterCount
        return max(0, position - matchStart)
    }

    private static func unitsMatch(_ source: ZhMatchUnit, _ spoken: ZhMatchUnit) -> Bool {
        guard source.kind == spoken.kind else { return false }
        switch source.kind {
        case .han: return soundsOverlap(source.sounds, spoken.sounds)
        case .word: return source.key == spoken.key || isFuzzyMatch(source.key, spoken.key)
        case .number: return source.key == spoken.key
        }
    }

    private static func charactersMatch(_ source: ZhMatchChar, _ spoken: ZhMatchChar) -> Bool {
        source.isHan == spoken.isHan
            && (source.isHan ? soundsOverlap(source.sounds, spoken.sounds) : source.key == spoken.key)
    }

    private static func soundsOverlap(_ first: [String], _ second: [String]) -> Bool {
        first.contains { second.contains($0) }
    }

    /// Fuzzy match for Latin words, as in the original: shared prefix, long
    /// common prefix, or small edit distance.
    static func isFuzzyMatch(_ a: String, _ b: String) -> Bool {
        if a.isEmpty || b.isEmpty { return false }
        if a == b { return true }
        let shorter = min(a.count, b.count)
        if shorter >= 3 && (a.hasPrefix(b) || b.hasPrefix(a)) { return true }
        let shared = zip(a, b).prefix(while: { $0 == $1 }).count
        if shorter >= 3 && shared >= max(3, shorter * 3 / 5) { return true }
        let distance = editDistance(Array(a), Array(b))
        if shorter <= 2 { return false }
        if shorter <= 4 { return distance <= 1 }
        if shorter <= 8 { return distance <= 2 }
        return distance <= max(a.count, b.count) / 3
    }

    private static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var row = Array(0...b.count)
        for i in 1...a.count {
            var previous = row[0]
            row[0] = i
            for j in 1...b.count {
                let temporary = row[j]
                row[j] = a[i - 1] == b[j - 1] ? previous : min(previous, row[j], row[j - 1]) + 1
                previous = temporary
            }
        }
        return row[b.count]
    }

    /// One character-level slot: a character, or a whole annotation (skipped).
    private struct Slot {
        let isSkip: Bool
        let character: ZhMatchChar?
        let start: Int
    }
}

// MARK: - Match units

enum ZhMatchUnitKind {
    /// One CJK character; compared by reading set.
    case han
    /// A Latin (space-separated) word; NFKC + lowercase letters and digits, fuzzy.
    case word
    /// A number normalized to Arabic digits; must be equal.
    case number
}

/// One character-level slot. `start` / `end` are its place in the script. For
/// numbers only the last digit's `end` reaches the end of the number — the
/// others stay at its start, so hearing 二零 doesn't count 2026 as half read.
struct ZhMatchChar {
    let isHan: Bool
    let key: String
    let sounds: [String]
    let start: Int
    let end: Int
}

/// One word-level unit. Script and transcript take the same path: split →
/// normalize numbers → units; each unit remembers its range in the script.
struct ZhMatchUnit {
    let kind: ZhMatchUnitKind
    let key: String
    let sounds: [String]
    let start: Int
    let end: Int
    let isAnnotation: Bool
    let characters: [ZhMatchChar]

    /// `words` are the display words (`splitTextIntoWords`); positions are in
    /// `words.joined(separator: " ")`.
    static func fromScript(words: [String], pinyin: ZhPinyinTable) -> [ZhMatchUnit] {
        var starts: [Int] = []
        starts.reserveCapacity(words.count)
        var offset = 0
        for word in words {
            starts.append(offset)
            offset += word.count + 1
        }
        let annotationFlags = SpeechTextAlignment.annotationFlags(for: words)

        return ZhNumbers.normalize(words).map { normalized in
            let first = normalized.start
            let last = normalized.start + normalized.count - 1
            let unit = create(normalized.text, start: starts[first], end: starts[last] + words[last].count, pinyin: pinyin)
            // Punctuation, emoji and other words without letters or digits are skipped like annotations.
            return annotationFlags[first] || unit.key.isEmpty ? unit.asAnnotation() : unit
        }
    }

    /// Transcript units have no script position (ranges start at 0); words
    /// without letters or digits (punctuation) are dropped.
    static func fromTranscript(_ transcript: String, pinyin: ZhPinyinTable) -> [ZhMatchUnit] {
        ZhNumbers.normalize(splitTextIntoWords(transcript))
            .map { create($0.text, start: 0, end: $0.text.count, pinyin: pinyin) }
            .filter { !$0.key.isEmpty }
    }

    private static func create(_ text: String, start: Int, end: Int, pinyin: ZhPinyinTable) -> ZhMatchUnit {
        if isNumber(text) {
            let digits = Array(text)
            let characters = digits.indices.map { i in
                ZhMatchChar(isHan: false, key: String(digits[i]), sounds: [], start: start,
                            end: i == digits.count - 1 ? end : start)
            }
            return ZhMatchUnit(kind: .number, key: text, sounds: [], start: start, end: end,
                               isAnnotation: false, characters: characters)
        }

        // Mac words carry attached punctuation (`歲，`, `「我`): a word whose only
        // letter is one CJK character is that character, ranging over the whole word.
        let readable = text.filter { $0.isLetter || $0.isNumber }
        if readable.count == 1, let scalar = readable.unicodeScalars.first, scalar.isCJK {
            let folded = String(readable).precomposedStringWithCompatibilityMapping // U+F900 compatibility ideographs
            let sounds = pinyin.soundKeys(of: folded)
            return ZhMatchUnit(kind: .han, key: folded, sounds: sounds, start: start, end: end, isAnnotation: false,
                               characters: [ZhMatchChar(isHan: true, key: folded, sounds: sounds, start: start, end: end)])
        }

        // Latin word: each character NFKC-folded (ＡＩ → AI) and lowercased,
        // letters and digits only; positions follow the script's characters.
        var characters: [ZhMatchChar] = []
        for (i, character) in text.enumerated() {
            let folded = String(character).precomposedStringWithCompatibilityMapping.lowercased()
            guard folded.contains(where: { $0.isLetter || $0.isNumber }) else { continue }
            for piece in folded {
                characters.append(ZhMatchChar(isHan: false, key: String(piece), sounds: [],
                                              start: start + i, end: start + i + 1))
            }
        }
        return ZhMatchUnit(kind: .word, key: characters.map(\.key).joined(), sounds: [], start: start, end: end,
                           isAnnotation: false, characters: characters)
    }

    /// Normalized numbers only contain 0–9 and a decimal point.
    private static func isNumber(_ text: String) -> Bool {
        text.contains(where: { $0.isASCII && $0.isNumber })
            && text.allSatisfy { ($0.isASCII && $0.isNumber) || $0 == "." }
    }

    func asAnnotation() -> ZhMatchUnit {
        ZhMatchUnit(kind: kind, key: key, sounds: sounds, start: start, end: end, isAnnotation: true, characters: characters)
    }
}

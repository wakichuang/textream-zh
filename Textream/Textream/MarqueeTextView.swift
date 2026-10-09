//
//  MarqueeTextView.swift
//  Textream
//
//  Created by Fatih Kadir Akın on 8.02.2026.
//

import SwiftUI

private let paragraphDividerExtraSpacing: CGFloat = 14
private let paragraphDividerDotSize: CGFloat = 3
private let paragraphDividerDotSpacing: CGFloat = 5
private let paragraphDividerDotOpacity: Double = 0.16

// MARK: - CJK-aware word splitting

extension Unicode.Scalar {
    var isCJK: Bool {
        let v = value
        return (v >= 0x4E00 && v <= 0x9FFF)    // CJK Unified Ideographs
            || (v >= 0x3400 && v <= 0x4DBF)    // CJK Extension A
            || (v >= 0x20000 && v <= 0x2A6DF)  // CJK Extension B
            || (v >= 0xF900 && v <= 0xFAFF)    // CJK Compatibility Ideographs
            || (v >= 0x3040 && v <= 0x309F)    // Hiragana
            || (v >= 0x30A0 && v <= 0x30FF)    // Katakana
            || (v >= 0xAC00 && v <= 0xD7AF)    // Hangul Syllables
    }
}

extension Character {
    /// Full-width / CJK punctuation that should never be grouped with a
    /// neighbouring Latin run (e.g. `，` `。` `「` `」` `、` `……` `——`).
    var isCJKPunctuation: Bool {
        guard isPunctuation, let v = unicodeScalars.first?.value else { return false }
        return (v >= 0x3000 && v <= 0x303F)    // CJK Symbols and Punctuation
            || (v >= 0xFE10 && v <= 0xFE1F)    // Vertical Forms
            || (v >= 0xFE30 && v <= 0xFE4F)    // CJK Compatibility Forms
            || (v >= 0xFF00 && v <= 0xFFEF)    // Halfwidth and Fullwidth Forms
            || (v >= 0x2010 && v <= 0x2027)    // Dashes, quotes, ellipsis
    }

    /// Han ideographs and kana, which are written without spaces between them.
    var isSpacelessCJK: Bool {
        guard let scalar = unicodeScalars.first, scalar.isCJK else { return false }
        return !(scalar.value >= 0xAC00 && scalar.value <= 0xD7AF)
    }

    /// Opening brackets and quotes (`「` `（` `《` `“` `(`) belong to the word after them.
    var isOpeningPunctuation: Bool {
        guard let category = unicodeScalars.first?.properties.generalCategory else { return false }
        return category == .openPunctuation || category == .initialPunctuation
    }
}

/// Splits text into display-ready words. CJK characters (Chinese, Japanese, Korean)
/// are split into individual characters so the flow layout can wrap them properly.
/// Punctuation never stands alone: a standalone punctuation mark would be treated
/// as an annotation (italic, dimmed) and its width is mis-measured, so it is
/// attached to the neighbouring word (`歲，`, `「我`, `作。」`).
func splitTextIntoWords(_ text: String) -> [String] {
    // Attach punctuation within a line only, so that
    // `paragraphBreakWordIndices` (which counts words line by line) stays in sync.
    text.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline })
        .flatMap { attachPunctuation(splitLineIntoWords(String($0))) }
}

private func splitLineIntoWords(_ line: String) -> [String] {
    let tokens = line
        .split(omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace })
        .map { String($0) }

    var result: [String] = []
    for token in tokens {
        guard token.unicodeScalars.contains(where: { $0.isCJK }) else {
            result.append(token)
            continue
        }
        // Token contains CJK characters — split each CJK char individually;
        // consecutive non-CJK chars (e.g. Latin letters, digits) stay grouped,
        // and CJK punctuation becomes its own unit to be attached afterwards.
        var buffer = ""
        for char in token {
            if char.unicodeScalars.first.map({ $0.isCJK }) == true || char.isCJKPunctuation {
                if !buffer.isEmpty {
                    result.append(buffer)
                    buffer = ""
                }
                result.append(String(char))
            } else {
                buffer.append(char)
            }
        }
        if !buffer.isEmpty {
            result.append(buffer)
        }
    }
    return result
}

/// Merges punctuation-only words into their neighbour: opening marks into the
/// next word, everything else into the previous one.
private func attachPunctuation(_ words: [String]) -> [String] {
    var result: [String] = []
    var pendingOpening = ""
    for word in words {
        let isPunctuationOnly = word.allSatisfy(\.isPunctuation)
        if isPunctuationOnly && word.allSatisfy(\.isOpeningPunctuation) {
            pendingOpening += word
        } else if isPunctuationOnly && pendingOpening.isEmpty && !result.isEmpty {
            result[result.count - 1] += word
        } else {
            result.append(pendingOpening + word)
            pendingOpening = ""
        }
    }
    if !pendingOpening.isEmpty {
        if result.isEmpty {
            result.append(pendingOpening)
        } else {
            result[result.count - 1] += pendingOpening
        }
    }
    return result
}

/// The visible separator after a word. Chinese and Japanese are written without
/// spaces, and full-width punctuation already carries its own spacing, so no
/// space is shown there; a space is kept around Latin words, digits and Hangul
/// (Korean separates words with spaces). Display only — char offsets still
/// count one space per word.
func displaySeparator(after word: String, before next: String?) -> String {
    // A Text that ends in full-width punctuation gets its trailing half trimmed,
    // which makes `，` look detached from its own character and glued to the
    // next one. A hair space keeps the punctuation at its full width.
    if word.last?.isCJKPunctuation == true { return "\u{200A}" }
    guard let last = word.last, let next, let first = next.first else { return " " }
    if first.isCJKPunctuation { return "" }
    if last.isSpacelessCJK && first.isSpacelessCJK { return "" }
    return " "
}

/// Core Text squeezes the blank half of a leading full-width opening mark
/// (`「自`, `《原`) by drawing the glyph at a negative x, but still reports the
/// unsqueezed width, which leaves a visible gap after the word. Returns how
/// much to trim from the trailing edge so the next character sits flush.
func leadingPunctuationTrim(of word: String, font: NSFont) -> CGFloat {
    guard word.first?.isCJKPunctuation == true else { return 0 }
    let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: word, attributes: [.font: font])
    )
    guard let run = (CTLineGetGlyphRuns(line) as? [CTRun])?.first,
          CTRunGetGlyphCount(run) > 0 else { return 0 }
    var position = CGPoint.zero
    CTRunGetPositions(run, CFRange(location: 0, length: 1), &position)
    return max(0, -position.x)
}

/// Returns the word indices that begin a new paragraph. Consecutive and
/// whitespace-only lines collapse into a single visual separator.
func paragraphBreakWordIndices(in text: String) -> Set<Int> {
    let normalizedLineEndings = text
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
    let lines = normalizedLineEndings.split(
        separator: "\n",
        omittingEmptySubsequences: false
    )

    var result = Set<Int>()
    var wordCount = 0
    var hasContent = false
    var hasPendingBreak = false

    for (index, line) in lines.enumerated() {
        let lineWords = splitTextIntoWords(String(line))
        if !lineWords.isEmpty {
            if hasContent && hasPendingBreak {
                result.insert(wordCount)
            }
            wordCount += lineWords.count
            hasContent = true
            hasPendingBreak = false
        }

        if index < lines.count - 1, hasContent {
            hasPendingBreak = true
        }
    }

    return result
}

// MARK: - Data

struct WordItem: Identifiable {
    let id: Int
    let word: String
    let charOffset: Int // char offset of this word in the full text (counting spaces)
    let isAnnotation: Bool // true for [bracket] words and emoji-only words
    let displayText: String // word plus the visible separator after it
    var trailingTrim: CGFloat = 0 // see leadingPunctuationTrim(of:font:)
}

// MARK: - Preference key to report word Y positions

struct WordYPreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// MARK: - Teleprompter

struct SpeechScrollView: View {
    let words: [String]
    let highlightedCharCount: Int
    var font: NSFont = .systemFont(ofSize: 18, weight: .semibold)
    var highlightColor: Color = .white
    var cueColor: Color = .white
    var cueUnreadOpacity: Double = 0.2
    var cueReadOpacity: Double = 0.5
    var onWordTap: ((Int) -> Void)? = nil
    /// Called when user starts/stops manual scrolling in smooth mode.
    /// Bool: true = scrolling started (pause timer), false = scrolling ended (resume timer).
    /// Double: new word progress to resume from (only meaningful when false).
    var onManualScroll: ((Bool, Double) -> Void)? = nil
    var smoothScroll: Bool = false
    /// Continuous word progress (e.g. 3.7 = 70% through 4th word). Drives scroll in smooth mode.
    var smoothWordProgress: Double = 0

    var isListening: Bool = true
    var readingPosition: ReadingPosition = .centered
    /// Optional preview-only transition. Live overlays keep their existing behavior.
    var readingPositionTransitionDuration: Double? = nil
    var paragraphBreakBeforeWordIndices: Set<Int> = []
    @State private var scrollOffset: CGFloat = 0
    @State private var manualOffset: CGFloat = 0
    @State private var wordYPositions: [Int: CGFloat] = [:]
    @State private var containerHeight: CGFloat = 0
    @State private var isUserScrolling: Bool = false
    @State private var stableTopLineCenter: CGFloat?
    @State private var stableLineAdvance: CGFloat?
    @State private var allowsNextBackwardTrackingUpdate = false
    @State private var hasAppliedTrackingTarget = false
    @State private var anchoredLayoutWidth: CGFloat = 0
    @State private var anchoredParagraphBreakBeforeWordIndices: Set<Int> = []
    @State private var isAnimatingReadingPositionChange = false
    @State private var readingPositionAnimationGeneration = 0
    // 繁中改版：滾輪逐行跳轉（WheelLineJump.swift）
    @State private var wheelLines = WheelLineJump.Accumulator()
    @State private var lastWheelJumpWord = 0
    @State private var lastWheelJumpAt: Date?
    @State private var didInitialSeek = false

    private var readingPositionTransitionAnimation: Animation? {
        guard let duration = readingPositionTransitionDuration, duration > 0 else {
            return nil
        }
        return .smooth(duration: duration, extraBounce: 0)
    }

    private var scrollOffsetAnimation: Animation? {
        if isAnimatingReadingPositionChange {
            return readingPositionTransitionAnimation
        }
        return smoothScroll ? .linear(duration: 0.06) : .easeOut(duration: 0.5)
    }

    var body: some View {
        GeometryReader { geo in
            WordFlowLayout(
                words: words,
                highlightedCharCount: highlightedCharCount,
                font: font,
                highlightColor: highlightColor,
                cueColor: cueColor,
                cueUnreadOpacity: cueUnreadOpacity,
                cueReadOpacity: cueReadOpacity,
                highlightWords: !smoothScroll,
                paragraphBreakBeforeWordIndices: paragraphBreakBeforeWordIndices,
                containerWidth: geo.size.width,
                onWordTap: { charOffset in
                    let tappedWordIndex = wordIndex(at: charOffset)
                    manualOffset = 0
                    if charOffset < highlightedCharCount {
                        allowsNextBackwardTrackingUpdate = true
                    }
                    onWordTap?(charOffset)
                    // Reposition from the tapped word itself instead of waiting
                    // for the parent progress update. That update can arrive
                    // after a stale recalculation has consumed the one-time
                    // backward allowance.
                    repositionTracking(toWordIndex: tappedWordIndex)
                },
                scrollOffset: scrollOffset + manualOffset,
                viewportHeight: geo.size.height
            )
            .onPreferenceChange(WordYPreferenceKey.self) { positions in
                let wasEmpty = wordYPositions.isEmpty
                let widthChanged = abs(anchoredLayoutWidth - geo.size.width) > 0.5
                let paragraphLayoutChanged = anchoredParagraphBreakBeforeWordIndices
                    != paragraphBreakBeforeWordIndices
                if widthChanged || paragraphLayoutChanged {
                    hasAppliedTrackingTarget = false
                }
                captureStableLineMetrics(from: positions)
                wordYPositions = positions
                // Re-anchor after a page switch or any live layout reflow. Keep
                // the stable vertical metrics during width changes: the visible
                // preference values may be culled from the middle of the text.
                if (wasEmpty || widthChanged || paragraphLayoutChanged),
                   !positions.isEmpty {
                    anchoredLayoutWidth = geo.size.width
                    anchoredParagraphBreakBeforeWordIndices = paragraphBreakBeforeWordIndices
                    recalculateTracking(containerHeight: containerHeight)
                }
                // 繁中改版：從講稿中間開始播放（編輯器游標），一量到起點那個字就直接捲過去
                if !didInitialSeek, !smoothScroll, highlightedCharCount > 0,
                   positions[activeWordIndex()] != nil {
                    didInitialSeek = true
                    repositionTracking(toWordIndex: activeWordIndex())
                }
            }
            .offset(y: scrollOffset + manualOffset)
            .animation(scrollOffsetAnimation, value: scrollOffset)
            .animation(.easeOut(duration: 0.15), value: manualOffset)
            .onChange(of: geo.size.height) { _, newHeight in
                containerHeight = newHeight
                hasAppliedTrackingTarget = false
                if highlightedCharCount == 0 && smoothWordProgress == 0 {
                    scrollOffset = initialScrollOffset(containerHeight: newHeight)
                } else if isListening {
                    recalculateTracking(containerHeight: newHeight)
                }
            }
            .onChange(of: highlightedCharCount) { _, _ in
                if isListening && !smoothScroll {
                    manualOffset = 0
                    recalculateTracking(containerHeight: containerHeight)
                }
            }
            .onChange(of: smoothWordProgress) { _, _ in
                if isListening && smoothScroll {
                    manualOffset = 0
                    recalculateTracking(containerHeight: containerHeight)
                }
            }
            .onChange(of: isListening) { _, listening in
                if listening {
                    manualOffset = 0
                    recalculateTracking(containerHeight: containerHeight)
                }
            }
            .onChange(of: words) { _, _ in
                scrollOffset = initialScrollOffset(containerHeight: containerHeight)
                didInitialSeek = false
                manualOffset = 0
                wordYPositions = [:]
                stableTopLineCenter = nil
                stableLineAdvance = nil
                allowsNextBackwardTrackingUpdate = false
                hasAppliedTrackingTarget = false
                anchoredLayoutWidth = 0
                anchoredParagraphBreakBeforeWordIndices = []
            }
            .onChange(of: readingPosition) { _, _ in
                manualOffset = 0
                stableTopLineCenter = nil
                stableLineAdvance = nil
                allowsNextBackwardTrackingUpdate = false
                hasAppliedTrackingTarget = false

                if let transitionDuration = readingPositionTransitionDuration {
                    captureStableLineMetrics(from: wordYPositions)
                    readingPositionAnimationGeneration &+= 1
                    let generation = readingPositionAnimationGeneration
                    isAnimatingReadingPositionChange = transitionDuration > 0

                    if let animation = readingPositionTransitionAnimation {
                        withAnimation(animation) {
                            recalculateTracking(containerHeight: containerHeight)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + transitionDuration) {
                            guard generation == readingPositionAnimationGeneration else { return }
                            isAnimatingReadingPositionChange = false
                        }
                    } else {
                        recalculateTracking(containerHeight: containerHeight)
                    }
                } else {
                    scrollOffset = initialScrollOffset(containerHeight: containerHeight)
                    DispatchQueue.main.async {
                        recalculateTracking(containerHeight: containerHeight)
                    }
                }
            }
            .onAppear {
                containerHeight = geo.size.height
                // 繁中改版：從講稿中間開始播放時，已經捲到起點就不要再設回開頭
                if !didInitialSeek {
                    scrollOffset = initialScrollOffset(containerHeight: containerHeight)
                }
            }
            .overlay(
                ScrollWheelView(
                    onScroll: { delta in
                        // 繁中改版：語音追蹤模式改由 onWheel 逐行跳轉，這裡只剩計時模式的平滑拖動
                        let canScroll = smoothScroll && isListening
                        guard canScroll else { return }

                        // Pause timer when user starts scrolling in smooth mode
                        if smoothScroll && !isUserScrolling {
                            isUserScrolling = true
                            onManualScroll?(true, 0)
                        }

                        let maxY = wordYPositions.values.max() ?? 0
                        let containerHeight = geo.size.height
                        let maxUp = containerHeight * 0.5
                        let maxDown = max(0, maxY - containerHeight * 0.5)

                        let newOffset = manualOffset + delta
                        let upperBound = maxUp
                        let lowerBound = -maxDown

                        if newOffset > upperBound {
                            let over = newOffset - upperBound
                            manualOffset = upperBound + over * 0.2
                        } else if newOffset < lowerBound {
                            let over = lowerBound - newOffset
                            manualOffset = lowerBound - over * 0.2
                        } else {
                            manualOffset = newOffset
                        }
                    },
                    onScrollEnd: {
                        if smoothScroll && isUserScrolling {
                            // Find the word at the active tracking anchor.
                            let newProgress = wordProgressAtCurrentOffset()
                            withAnimation(.easeOut(duration: 0.15)) {
                                manualOffset = 0
                            }
                            isUserScrolling = false
                            allowsNextBackwardTrackingUpdate = true
                            onManualScroll?(false, newProgress)
                        } else {
                            let maxY = wordYPositions.values.max() ?? 0
                            let containerHeight = geo.size.height
                            let upperBound = containerHeight * 0.5
                            let lowerBound = -max(0, maxY - containerHeight * 0.5)

                            if manualOffset > upperBound || manualOffset < lowerBound {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    manualOffset = min(upperBound, max(lowerBound, manualOffset))
                                }
                            }
                        }
                    },
                    onWheel: { deltaY, precise in
                        // 繁中改版：語音追蹤模式滾一格跳一行，聆聽中、暫停中都可以
                        guard !smoothScroll else { return }
                        let lines = wheelLines.add(
                            deltaY: deltaY,
                            precise: precise,
                            lineHeight: WheelLineJump.lineHeight(for: font)
                        )
                        guard lines != 0 else { return }
                        // 連續滾動時，從上一格跳到的那一行接著數，不等辨識結果回來
                        let now = Date()
                        let continuing = lastWheelJumpAt.map { now.timeIntervalSince($0) < 0.6 } ?? false
                        let base = continuing ? lastWheelJumpWord : activeWordIndex()
                        guard let target = WheelLineJump.targetWord(
                            positions: wordYPositions, fromWord: base, lines: lines
                        ), target != base else { return }
                        lastWheelJumpWord = target
                        lastWheelJumpAt = now
                        wheelJump(toWordIndex: target)
                    }
                )
            )
        }
        .clipped()
        .mask(
            LinearGradient(
                stops: readingPosition == .nearTop
                    ? [
                        .init(color: .white, location: 0),
                        .init(color: .white, location: 0.05),
                        .init(color: .white, location: 0.95),
                        .init(color: .clear, location: 1.0)
                    ]
                    : [
                        .init(color: .clear, location: 0),
                        .init(color: .white, location: 0.05),
                        .init(color: .white, location: 0.95),
                        .init(color: .clear, location: 1.0)
                    ],
                startPoint: .top,
                endPoint: .bottom
            )
            .animation(readingPositionTransitionAnimation, value: readingPosition)
        )
    }

    private func initialScrollOffset(containerHeight: CGFloat) -> CGFloat {
        switch readingPosition {
        case .centered:
            let lineHeight = font.pointSize * 1.4
            return containerHeight * 0.5 - lineHeight * 0.5
        case .nearTop:
            return 0
        }
    }

    private func recalculateTracking(containerHeight: CGFloat) {
        if readingPosition == .nearTop {
            recalcTopWithPreviousLine()
            return
        }

        let center = containerHeight * 0.5

        if smoothScroll {
            // Classic/silence-paused: anchor active word near the bottom, scrolling up
            let bottomAnchor = containerHeight - 20
            let wordIdx = Int(smoothWordProgress)
            let fraction = smoothWordProgress - Double(wordIdx)
            let clampedIdx = max(0, min(wordIdx, words.count - 1))
            guard let wordY = wordYPositions[clampedIdx] else { return }
            let nextY = wordYPositions[clampedIdx + 1] ?? wordY
            let interpolatedY = wordY + (nextY - wordY) * CGFloat(fraction)
            applyTrackingTarget(bottomAnchor - interpolatedY)
        } else {
            // Word-tracking/voice-activated: active word at vertical center
            let wordIdx = activeWordIndex()
            if let wordY = wordYPositions[wordIdx] {
                let target = center - wordY
                applyTrackingTarget(target)
            }
        }
    }

    private func recalcTopWithPreviousLine() {
        if smoothScroll {
            let wordIdx = Int(smoothWordProgress)
            let fraction = smoothWordProgress - Double(wordIdx)
            let clampedIdx = max(0, min(wordIdx, words.count - 1))
            guard let wordY = wordYPositions[clampedIdx] else { return }
            let nextY = wordYPositions[clampedIdx + 1] ?? wordY
            let interpolatedY = wordY + (nextY - wordY) * CGFloat(fraction)
            let target = min(interpolatedY, topReadingAnchor) - interpolatedY
            applyTrackingTarget(target)
        } else {
            let wordIdx = activeWordIndex()
            guard let wordY = wordYPositions[wordIdx] else { return }
            let target = min(wordY, topReadingAnchor) - wordY
            applyTrackingTarget(target)
        }
    }

    private func repositionTracking(toWordIndex wordIndex: Int) {
        guard let wordY = wordYPositions[wordIndex] else { return }

        let target: CGFloat
        switch readingPosition {
        case .centered:
            target = containerHeight * 0.5 - wordY
        case .nearTop:
            target = min(wordY, topReadingAnchor) - wordY
        }

        applyTrackingTarget(target, force: true)
    }

    /// 繁中改版：滾輪跳轉跟點字跳轉走同一條路（onWordTap → SpeechRecognizer.jumpTo）。
    private func wheelJump(toWordIndex wordIndex: Int) {
        let charOffset = WheelLineJump.charOffset(ofWord: wordIndex, in: words)
        manualOffset = 0
        if charOffset < highlightedCharCount {
            allowsNextBackwardTrackingUpdate = true
        }
        onWordTap?(charOffset)
        repositionTracking(toWordIndex: wordIndex)
    }

    private var topReadingAnchor: CGFloat {
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let fallbackAdvance = lineHeight + (lineHeight / font.pointSize > 1.5 ? 2 : 8)

        // The live notch briefly returns to offset zero before measuring Near Top,
        // so it always captures the document's first two rows. The animated
        // preview cannot do that without visibly jumping through the beginning.
        // Use the equivalent row geometry directly instead of treating the
        // first currently rendered (and possibly culled) row as line zero.
        if readingPositionTransitionDuration != nil {
            return lineHeight * 0.5 + fallbackAdvance
        }

        return (stableTopLineCenter ?? lineHeight * 0.5)
            + (stableLineAdvance ?? fallbackAdvance)
    }

    /// Capture the actual row geometry once, before visibility culling changes
    /// which word frames participate in the preference dictionary.
    private func captureStableLineMetrics(from positions: [Int: CGFloat]) {
        guard readingPosition == .nearTop,
              stableTopLineCenter == nil || stableLineAdvance == nil else { return }

        let positionedWords = positions.sorted { $0.value < $1.value }
        let measuredLines = positionedWords.reduce(into: [(y: CGFloat, wordIDs: [Int])]()) { result, entry in
            if let lastIndex = result.indices.last,
               abs(result[lastIndex].y - entry.value) <= 0.5 {
                result[lastIndex].wordIDs.append(entry.key)
            } else {
                result.append((y: entry.value, wordIDs: [entry.key]))
            }
        }
        guard let firstLineY = measuredLines.first?.y else { return }
        if stableTopLineCenter == nil {
            stableTopLineCenter = firstLineY
        }
        if stableLineAdvance == nil, measuredLines.count > 1 {
            for index in 1..<measuredLines.count {
                let firstWordID = measuredLines[index].wordIDs.min() ?? -1
                guard !paragraphBreakBeforeWordIndices.contains(firstWordID) else { continue }
                stableLineAdvance = measuredLines[index].y - measuredLines[index - 1].y
                break
            }
        }
    }

    /// Normal reading progress may only move the text upward. Brief backward
    /// corrections from speech recognition must not produce a down/up bounce.
    /// Explicit taps and manual scrolling opt into one backward reposition.
    private func applyTrackingTarget(_ target: CGFloat, force: Bool = false) {
        if !hasAppliedTrackingTarget
            || target < scrollOffset - 1
            || allowsNextBackwardTrackingUpdate
            || force {
            scrollOffset = target
        }
        hasAppliedTrackingTarget = true
        allowsNextBackwardTrackingUpdate = false
    }

    private func wordIndex(at charOffset: Int) -> Int {
        var offset = 0
        for (index, word) in words.enumerated() {
            let end = offset + word.count
            if charOffset <= end { return index }
            offset = end + 1
        }
        return max(0, words.count - 1)
    }

    /// Find the word progress at the current visual position (scrollOffset + manualOffset)
    private func wordProgressAtCurrentOffset() -> Double {
        let trackingY: CGFloat
        switch readingPosition {
        case .centered:
            trackingY = containerHeight * 0.5
        case .nearTop:
            trackingY = topReadingAnchor
        }
        let targetY = trackingY - (scrollOffset + manualOffset)

        // Find the closest word and interpolate
        let sorted = wordYPositions.sorted { $0.key < $1.key }
        guard !sorted.isEmpty else { return smoothWordProgress }

        for i in 0..<sorted.count {
            let (wordIdx, wordY) = sorted[i]
            if i + 1 < sorted.count {
                let (_, nextY) = sorted[i + 1]
                if targetY >= wordY && targetY <= nextY {
                    let frac = (nextY - wordY) > 0 ? Double(targetY - wordY) / Double(nextY - wordY) : 0
                    return Double(wordIdx) + frac
                }
            } else if targetY >= wordY {
                return Double(wordIdx)
            }
        }
        // If scrolled above all words, return 0
        if targetY < (sorted.first?.value ?? 0) {
            return 0
        }
        return Double(words.count)
    }

    private func activeWordIndex() -> Int {
        var offset = 0
        for (i, word) in words.enumerated() {
            let end = offset + word.count
            if highlightedCharCount <= end { return i }
            offset = end + 1
        }
        return max(0, words.count - 1)
    }

    /// Returns (wordIndex, fractionThroughWord) for smooth interpolation
    private func activeWordFraction() -> (Int, Double) {
        var offset = 0
        for (i, word) in words.enumerated() {
            let end = offset + word.count
            if highlightedCharCount <= end {
                let wordLen = max(1, word.count)
                let into = highlightedCharCount - offset
                return (i, Double(into) / Double(wordLen))
            }
            offset = end + 1
        }
        return (max(0, words.count - 1), 1.0)
    }
}

// MARK: - Word Flow Layout

struct WordFlowLayout: View {
    let words: [String]
    let highlightedCharCount: Int
    let font: NSFont
    var highlightColor: Color = .white
    var cueColor: Color = .white
    var cueUnreadOpacity: Double = 0.2
    var cueReadOpacity: Double = 0.5
    var highlightWords: Bool = true
    var paragraphBreakBeforeWordIndices: Set<Int> = []
    let containerWidth: CGFloat
    var onWordTap: ((Int) -> Void)? = nil
    var scrollOffset: CGFloat = 0
    var viewportHeight: CGFloat = 0

    // Compute line spacing based on font metrics — fonts with large built-in
    // line height (e.g. OpenDyslexic) need less extra spacing
    private var lineSpacing: CGFloat {
        let intrinsicHeight = font.ascender - font.descender + font.leading
        let ratio = intrinsicHeight / font.pointSize
        // System fonts: ratio ~1.2, OpenDyslexic: ratio ~1.7+
        return ratio > 1.5 ? 2 : 8
    }

    // Simple layout cache to avoid re-measuring words on every highlight update
    private static var _cacheKey: String = ""
    private static var _cachedItems: [WordItem] = []
    private static var _cachedLines: [[WordItem]] = []
    private static var _cachedParagraphPrefixCounts: [Int] = []

    private func cachedLayout() -> ([WordItem], [[WordItem]], [Int]) {
        let paragraphKey = paragraphBreakBeforeWordIndices.sorted()
            .map(String.init)
            .joined(separator: ",")
        let key = "\(words.count)|\(words.first ?? "")|\(words.last ?? "")|"
            + "\(font.fontName)|\(font.pointSize)|\(Int(containerWidth))|\(paragraphKey)"
        if key == Self._cacheKey {
            return (Self._cachedItems, Self._cachedLines, Self._cachedParagraphPrefixCounts)
        }
        let items = buildItems()
        let lines = buildLines(items: items)
        var paragraphPrefixCounts = [0]
        for line in lines {
            let beginsParagraph = line.first.map {
                paragraphBreakBeforeWordIndices.contains($0.id)
            } ?? false
            paragraphPrefixCounts.append(
                paragraphPrefixCounts[paragraphPrefixCounts.count - 1] + (beginsParagraph ? 1 : 0)
            )
        }
        Self._cacheKey = key
        Self._cachedItems = items
        Self._cachedLines = lines
        Self._cachedParagraphPrefixCounts = paragraphPrefixCounts
        return (items, lines, paragraphPrefixCounts)
    }

    // Find the index of the next word to read (first non-fully-lit, non-annotation word)
    private func nextWordIndex(items: [WordItem]) -> Int {
        for item in items {
            if item.isAnnotation { continue }
            let charsIntoWord = highlightedCharCount - item.charOffset
            let litCount = max(0, min(item.word.count, charsIntoWord))
            let letterCount = max(1, item.word.filter { $0.isLetter || $0.isNumber }.count)
            if litCount < letterCount {
                return item.id
            }
        }
        return -1
    }

    private func isRightToLeft(items: [WordItem]) -> Bool {
        for item in items where !item.isAnnotation {
            switch textBaseDirection(in: item.word) {
            case .rightToLeft:
                return true
            case .leftToRight:
                return false
            case .natural:
                continue
            }
        }
        return false
    }

    var body: some View {
        let (items, lines, paragraphPrefixCounts) = cachedLayout()
        let nextIdx = nextWordIndex(items: items)
        let totalLines = lines.count
        let rtl = isRightToLeft(items: items)

        // Estimate line height for visibility culling using actual font metrics
        let rowHeight = ceil(font.ascender - font.descender + font.leading)
        let lineH = rowHeight + lineSpacing
        let lineTop: (Int) -> CGFloat = { lineIndex in
            CGFloat(lineIndex) * lineH
                + CGFloat(paragraphPrefixCounts[lineIndex]) * paragraphDividerExtraSpacing
        }
        let lineRowHeight: (Int) -> CGFloat = { lineIndex in
            let beginsParagraph = paragraphPrefixCounts[lineIndex + 1]
                > paragraphPrefixCounts[lineIndex]
            return rowHeight + (beginsParagraph ? paragraphDividerExtraSpacing : 0)
        }
        let totalContentHeight = max(0, lineTop(totalLines) - lineSpacing)

        // Determine visible range of lines
        let canCull = viewportHeight > 0 && totalLines > 0
        let buffer: CGFloat = 400
        let startLine: Int = {
            guard canCull else { return 0 }
            let visibleMinY = -scrollOffset - buffer
            var candidate = max(0, min(totalLines, Int(floor(max(0, visibleMinY) / lineH))))
            while candidate > 0, lineTop(candidate) > visibleMinY {
                candidate -= 1
            }
            while candidate < totalLines,
                  lineTop(candidate) + lineRowHeight(candidate) < visibleMinY {
                candidate += 1
            }
            return candidate
        }()
        let endLine: Int = {
            guard canCull else { return totalLines }
            let visibleMaxY = viewportHeight - scrollOffset + buffer
            var candidate = max(startLine, min(totalLines, Int(ceil(max(0, visibleMaxY) / lineH))))
            while candidate > startLine, lineTop(candidate) > visibleMaxY {
                candidate -= 1
            }
            while candidate < totalLines, lineTop(candidate) < visibleMaxY {
                candidate += 1
            }
            return max(startLine, candidate)
        }()

        // For RTL scripts (Arabic, Hebrew, Persian, Urdu), flip the layout direction
        // so words within each line flow right-to-left instead of left-to-right.
        VStack(alignment: rtl ? .trailing : .leading, spacing: lineSpacing) {
            if startLine > 0 {
                Color.clear.frame(
                    height: max(0, lineTop(startLine) - lineSpacing)
                )
            }

            ForEach(startLine..<endLine, id: \.self) { lineIdx in
                let beginsParagraph = paragraphPrefixCounts[lineIdx + 1]
                    > paragraphPrefixCounts[lineIdx]
                HStack(spacing: 0) {
                    ForEach(lines[lineIdx], id: \.id) { item in
                        wordView(for: item, isNextWord: item.id == nextIdx)
                            .id(item.id)
                    }
                }
                // 繁中改版：每一行固定成估計的行高。上方被省略的行是用估計值撐開的，
                // 實際行高不一樣的話，同一個字的位置會隨「省略了幾行」浮動，往上捲會被拉回去
                .frame(height: rowHeight)
                .frame(maxWidth: .infinity, alignment: rtl ? .trailing : .leading)
                .padding(.top, beginsParagraph ? paragraphDividerExtraSpacing : 0)
                .overlay(alignment: .top) {
                    if beginsParagraph {
                        HStack(spacing: paragraphDividerDotSpacing) {
                            ForEach(0..<3, id: \.self) { _ in
                                Circle()
                                    .fill(Color.white.opacity(paragraphDividerDotOpacity))
                                    .frame(
                                        width: paragraphDividerDotSize,
                                        height: paragraphDividerDotSize
                                    )
                            }
                        }
                            .offset(
                                y: (
                                    paragraphDividerExtraSpacing
                                        - lineSpacing
                                        - paragraphDividerDotSize
                                ) * 0.5
                            )
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
            }

            if endLine < totalLines {
                Color.clear.frame(
                    height: max(0, totalContentHeight - lineTop(endLine))
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: rtl ? .trailing : .leading)
        .background(
            // 繁中改版：每個字的位置用行號算出來回報（見 computedWordYPositions）
            Color.clear.preference(
                key: WordYPreferenceKey.self,
                value: computedWordYPositions(lines: lines, visible: startLine..<endLine,
                                              lineTop: lineTop, rowHeight: rowHeight,
                                              paragraphPrefixCounts: paragraphPrefixCounts)
            )
        )
        .coordinateSpace(name: "flowLayout")
    }

    /// 繁中改版：每個字的垂直中心直接用行號算出來（每一行固定行高），不在畫面排版完才量。
    /// 量出來的位置會隨捲動動畫、上方省略了幾行浮動，往上捲會被追蹤拉回去；算出來的只跟它在第幾行有關。
    /// 回報排版範圍內的字，加上目前那個字（跟 SpeechScrollView.activeWordIndex 同一個）——
    /// 從講稿中間開始播放時它可能還沒排版，畫面要靠它才捲得過去。
    private func computedWordYPositions(lines: [[WordItem]], visible: Range<Int>,
                                        lineTop: (Int) -> CGFloat, rowHeight: CGFloat,
                                        paragraphPrefixCounts: [Int]) -> [Int: CGFloat] {
        func midY(_ lineIndex: Int) -> CGFloat {
            let beginsParagraph = paragraphPrefixCounts[lineIndex + 1] > paragraphPrefixCounts[lineIndex]
            return lineTop(lineIndex) + (beginsParagraph ? paragraphDividerExtraSpacing : 0) + rowHeight / 2
        }
        var positions: [Int: CGFloat] = [:]
        for lineIndex in visible {
            let y = midY(lineIndex)
            for item in lines[lineIndex] { positions[item.id] = y }
        }
        if highlightedCharCount > 0 {
            for (lineIndex, line) in lines.enumerated() {
                guard let item = line.first(where: { highlightedCharCount <= $0.charOffset + $0.word.count }) else {
                    continue
                }
                positions[item.id] = midY(lineIndex)
                break
            }
        }
        return positions
    }

    private func wordView(for item: WordItem, isNextWord: Bool) -> some View {
        let wordLen = item.word.count
        let charsIntoWord = highlightedCharCount - item.charOffset
        let litCount = max(0, min(wordLen, charsIntoWord))
        let letterCount = max(1, item.word.filter { $0.isLetter || $0.isNumber }.count)
        let isFullyLit = litCount >= letterCount
        let isCurrentWord = isNextWord || (charsIntoWord >= 0 && !isFullyLit)

        // When highlighting is off (classic/silence-paused), use uniform color
        if !highlightWords {
            let uniformColor: Color = item.isAnnotation
                ? cueColor.opacity(cueUnreadOpacity)
                : highlightColor

            return Text(item.displayText)
                .font(item.isAnnotation ? Font(font).italic() : Font(font))
                .foregroundStyle(uniformColor)
                // Never let SwiftUI truncate script text to "…".
                .fixedSize()
                .padding(.trailing, -item.trailingTrim)
                .contentShape(Rectangle())
                .onTapGesture {
                    onWordTap?(item.charOffset)
                }
        }

        // Annotations: italic, dimmed with cue color
        if item.isAnnotation {
            let annotationColor: Color = isFullyLit
                ? cueColor.opacity(cueReadOpacity)
                : cueColor.opacity(cueUnreadOpacity)

            return Text(item.displayText)
                .font(Font(font).italic())
                .foregroundStyle(annotationColor)
                // Never let SwiftUI truncate script text to "…".
                .fixedSize()
                .padding(.trailing, -item.trailingTrim)
                .contentShape(Rectangle())
                .onTapGesture {
                    onWordTap?(item.charOffset)
                }
        }

        // Dim color: highlight color variant for current word, full for unread
        let dimColor: Color = isCurrentWord
            ? highlightColor.opacity(0.6)
            : highlightColor

        // Base color for the whole word
        let wordColor: Color = isFullyLit ? highlightColor.opacity(0.3) : dimColor

        return Text(item.displayText)
            .font(Font(font))
            .foregroundStyle(wordColor)
            .underline(isCurrentWord, color: wordColor)
            // Never let SwiftUI truncate script text to "…".
            .fixedSize()
            .padding(.trailing, -item.trailingTrim)
            .contentShape(Rectangle())
            .onTapGesture {
                onWordTap?(item.charOffset)
            }
    }

    private func buildItems() -> [WordItem] {
        var items: [WordItem] = []
        var offset = 0
        let annotationFlags = SpeechTextAlignment.annotationFlags(for: words)
        for (i, word) in words.enumerated() {
            let isAnnotation = annotationFlags[i] || Self.isAnnotationWord(word)
            let next = i + 1 < words.count ? words[i + 1] : nil
            items.append(WordItem(
                id: i,
                word: word,
                charOffset: offset,
                isAnnotation: isAnnotation,
                displayText: word + displaySeparator(after: word, before: next),
                trailingTrim: leadingPunctuationTrim(of: word, font: font)
            ))
            offset += word.count + 1 // +1 for space
        }
        return items
    }

    static func isAnnotationWord(_ word: String) -> Bool {
        // Words inside square brackets like [smile]
        if word.hasPrefix("[") && word.hasSuffix("]") { return true }
        // Emoji-only words (no letters or numbers)
        let stripped = word.filter { $0.isLetter || $0.isNumber }
        if stripped.isEmpty { return true }
        return false
    }

    private func buildLines(items: [WordItem]) -> [[WordItem]] {
        var lines: [[WordItem]] = [[]]
        var currentLineWidth: CGFloat = 0

        for item in items {
            if paragraphBreakBeforeWordIndices.contains(item.id),
               !lines[lines.count - 1].isEmpty {
                lines.append([])
                currentLineWidth = 0
            }
            // Measure exactly what wordView renders (`displayText` as one string):
            // measuring the word and the space separately under-counts full-width
            // punctuation by ~10pt. SwiftUI rounds each Text up to whole points,
            // so round up too — otherwise the line overflows and SwiftUI
            // truncates a word to "…".
            let measured = (item.displayText as NSString).size(withAttributes: [.font: font]).width
            let wordWidth = ceil(ceil(measured) - item.trailingTrim)
            if currentLineWidth + wordWidth > containerWidth && !lines[lines.count - 1].isEmpty {
                lines.append([])
                currentLineWidth = 0
            }
            lines[lines.count - 1].append(item)
            currentLineWidth += wordWidth
        }
        return lines
    }
}

// MARK: - Elapsed Time

struct ElapsedTimeView: View {
    let fontSize: CGFloat

    @State private var startDate = Date()

    var body: some View {
        TimelineView(.periodic(from: startDate, by: 1)) { context in
            let elapsed = context.date.timeIntervalSince(startDate)
            let minutes = Int(elapsed) / 60
            let seconds = Int(elapsed) % 60
            Text(String(format: "%02d:%02d", minutes, seconds))
                .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}

// MARK: - Audio Waveform + Progress

struct AudioWaveformProgressView: View {
    let levels: [CGFloat]
    let progress: Double // 0.0 to 1.0

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                let barProgress = Double(index) / Double(max(1, levels.count - 1))
                let isLit = barProgress <= progress

                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isLit
                          ? Color.yellow.opacity(0.9)
                          : Color.white.opacity(0.15)
                    )
                    .frame(width: 3, height: max(3, level * 28))
                    .animation(.easeOut(duration: 0.08), value: level)
            }
        }
    }
}

// Keep the old one for backward compat
struct AudioWaveformView: View {
    let levels: [CGFloat]
    var color: Color = .white

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color.opacity(0.4 + Double(level) * 0.6))
                    .frame(width: 3, height: max(3, level * 28 + 3))
                    .animation(.easeOut(duration: 0.08), value: level)
            }
        }
    }
}

// MARK: - Scroll Wheel Handler

struct ScrollWheelView: NSViewRepresentable {
    var onScroll: (CGFloat) -> Void
    var onScrollEnd: (() -> Void)?
    /// 繁中改版：原始滾動量與是否為精確捲動（觸控板），給語音追蹤的逐行跳轉用。
    var onWheel: ((CGFloat, Bool) -> Void)?

    init(onScroll: @escaping (CGFloat) -> Void, onScrollEnd: (() -> Void)? = nil,
         onWheel: ((CGFloat, Bool) -> Void)? = nil) {
        self.onScroll = onScroll
        self.onScrollEnd = onScrollEnd
        self.onWheel = onWheel
    }

    func makeNSView(context: Context) -> ScrollWheelNSView {
        let view = ScrollWheelNSView()
        view.onScroll = onScroll
        view.onScrollEnd = onScrollEnd
        view.onWheel = onWheel
        return view
    }

    func updateNSView(_ nsView: ScrollWheelNSView, context: Context) {
        nsView.onScroll = onScroll
        nsView.onScrollEnd = onScrollEnd
        nsView.onWheel = onWheel
    }
}

class ScrollWheelNSView: NSView {
    var onScroll: ((CGFloat) -> Void)?
    var onScrollEnd: (() -> Void)?
    var onWheel: ((CGFloat, Bool) -> Void)?
    private var scrollMonitor: Any?
    private var wheelEndWorkItem: DispatchWorkItem?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil && scrollMonitor == nil {
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window = self.window else { return event }
                // Only handle if event is in our window
                if event.window == window {
                    let delta = event.scrollingDeltaY
                    let scaled = event.hasPreciseScrollingDeltas ? delta : delta * 10
                    self.onScroll?(scaled)
                    self.onWheel?(delta, event.hasPreciseScrollingDeltas)

                    if event.phase == .ended || event.momentumPhase == .ended {
                        self.onScrollEnd?()
                    } else if event.phase.isEmpty && event.momentumPhase.isEmpty {
                        // 繁中改版：一般滑鼠滾輪不送 phase，停 0.25 秒就當作滾完，
                        // 不然計時模式滾完之後會一直停著
                        self.wheelEndWorkItem?.cancel()
                        let item = DispatchWorkItem { [weak self] in self?.onScrollEnd?() }
                        self.wheelEndWorkItem = item
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
                    }
                }
                return event
            }
        }
    }

    override func removeFromSuperview() {
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
        }
        wheelEndWorkItem?.cancel()
        super.removeFromSuperview()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}

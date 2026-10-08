//
//  ZhNumbers.swift
//  Textream（繁中改版）
//
//  Ported from Textream for Windows (ChineseNumbers.cs).
//

import Foundation

/// One normalized word: `text` is what gets matched; it comes from `count`
/// consecutive input words starting at index `start`.
struct ZhNormalizedWord: Equatable {
    let text: String
    let start: Int
    let count: Int
}

/// Number normalization: Chinese and Arabic numerals both become Arabic digits,
/// applied identically to the script and to the transcript (二零二六 = 2026,
/// 兩千 = 2000, 一千五 = 1500). Consecutive number words merge into one and
/// remember where they came from, so the highlight maps back onto the script.
///
/// `一起` becoming `1起` is fine — both sides agree. Financial numerals
/// (壹貳參…) are deliberately not converted: 參、陸、伍、拾 are common characters.
///
/// Mac difference: words here may carry attached punctuation (`千，`, `「三`),
/// so numbers are read from the word with its edge punctuation trimmed, and a
/// number never continues across punctuation.
enum ZhNumbers {
    private static let digits: [Character: Int] = [
        "零": 0, "〇": 0, "○": 0,
        "一": 1, "二": 2, "兩": 2, "两": 2, "三": 3, "四": 4,
        "五": 5, "六": 6, "七": 7, "八": 8, "九": 9,
    ]
    private static let smallUnits: [Character: Int] = ["十": 10, "百": 100, "千": 1000]
    private static let bigUnits: [Character: Decimal] = [
        "萬": 10_000, "万": 10_000, "億": 100_000_000, "亿": 100_000_000,
    ]
    /// 廿 = 20, 卅 = 30, 卌 = 40.
    private static let tens: [Character: Int] = ["廿": 20, "卅": 30, "卌": 40]

    static func normalize(_ words: [String]) -> [ZhNormalizedWord] {
        let cores = words.map(core)
        var result: [ZhNormalizedWord] = []
        result.reserveCapacity(words.count)
        var i = 0
        while i < words.count {
            guard isNumberWord(cores[i]) else {
                result.append(ZhNormalizedWord(text: words[i], start: i, count: 1))
                i += 1
                continue
            }
            let end = findRunEnd(words, cores, from: i)
            result.append(ZhNormalizedWord(text: evaluate(Array(cores[i..<end])), start: i, count: end - i))
            i = end
        }
        return result
    }

    // MARK: - Run detection

    /// Where the number starting at `start` ends (exclusive). Only one decimal
    /// point, and it must be followed by a digit; the fraction may be followed
    /// by 萬／億 (一點五萬).
    private static func findRunEnd(_ words: [String], _ cores: [String], from start: Int) -> Int {
        var end = start + 1
        var afterPoint = false
        while end < words.count, canJoin(words[end - 1], words[end]) {
            let word = cores[end]
            if !afterPoint, isPoint(word), end + 1 < words.count,
               canJoin(words[end], words[end + 1]), isDigitWord(cores[end + 1]) {
                afterPoint = true
                end += 1
            } else if afterPoint {
                if isDigitWord(word) {
                    end += 1
                    continue
                }
                if isBigUnit(word) {
                    end += 1
                }
                break
            } else if isNumberWord(word) {
                end += 1
            } else {
                break
            }
        }
        return end
    }

    /// A number may not continue across punctuation (`兩千，三百` is two numbers).
    private static func canJoin(_ previous: String, _ next: String) -> Bool {
        !(previous.last?.isPunctuation ?? false) && !(next.first?.isPunctuation ?? false)
    }

    /// The word without punctuation at either end (`「三` → `三`, `2,000。` → `2,000`).
    private static func core(_ word: String) -> String {
        var characters = Substring(word)
        while let first = characters.first, first.isPunctuation { characters = characters.dropFirst() }
        while let last = characters.last, last.isPunctuation { characters = characters.dropLast() }
        return String(characters)
    }

    // MARK: - Evaluation

    private static func evaluate(_ run: [String]) -> String {
        let point = run.firstIndex(where: isPoint)
        let integerPart = point.map { Array(run[..<$0]) } ?? run
        var fractionPart = point.map { Array(run[($0 + 1)...]) } ?? []

        var multiplier: Decimal?
        if let last = fractionPart.last, isBigUnit(last), let unit = bigUnits[last.first!] {
            multiplier = unit
            fractionPart.removeLast()
        }
        let fractionDigits = fractionPart.map(digitsOf).joined()

        let positional = integerPart.contains { word in
            word.count == 1 && (smallUnits[word.first!] != nil || bigUnits[word.first!] != nil || tens[word.first!] != nil)
        }
        if !positional && multiplier == nil {
            // Read digit by digit (二零二六, 零九一二) or plain Arabic: join literally,
            // keeping leading and trailing zeros.
            let integerDigits = integerPart.map(digitsOf).joined()
            return point == nil ? integerDigits : "\(integerDigits).\(fractionDigits)"
        }

        var value = positional
            ? evaluatePositional(integerPart)
            : Decimal(string: integerPart.map(digitsOf).joined(), locale: Locale(identifier: "en_US_POSIX")) ?? 0
        if !fractionDigits.isEmpty, let fraction = Decimal(string: "0.\(fractionDigits)", locale: Locale(identifier: "en_US_POSIX")) {
            value += fraction
        }
        if let multiplier {
            value *= multiplier
        }
        return format(value)
    }

    /// Positional readings: 一千二百三十四、兩千零二十六、三萬五千、一千五 (= 1500).
    private static func evaluatePositional(_ words: [String]) -> Decimal {
        var total: Decimal = 0
        var section: Decimal = 0
        var number: Decimal?
        var lastUnit: Decimal = 1
        var zeroSinceUnit = false

        for word in words {
            if let arabic = parseArabic(word) {
                number = arabic
                continue
            }
            guard let c = word.first else { continue }
            if let digit = digits[c] {
                if digit == 0 {
                    zeroSinceUnit = true
                } else {
                    number = number.map { $0 * 10 + Decimal(digit) } ?? Decimal(digit)
                }
            } else if let small = smallUnits[c] {
                section += (number ?? 1) * Decimal(small)
                number = nil
                lastUnit = Decimal(small)
                zeroSinceUnit = false
            } else if let ten = tens[c] {
                section += Decimal(ten)
                number = nil
                lastUnit = 10
                zeroSinceUnit = false
            } else if let big = bigUnits[c] {
                if section == 0 && number == nil {
                    total = total > 0 ? total * big : big // 萬一、一萬億
                } else {
                    total += (section + (number ?? 0)) * big
                }
                section = 0
                number = nil
                lastUnit = big
                zeroSinceUnit = false
            }
        }

        if let last = number {
            // A digit right after a unit with no zero in between: 一千五 = 1500,
            // 兩萬三 = 23000, 二十五 = 25.
            section += !zeroSinceUnit && lastUnit >= 10 ? last * (lastUnit / 10) : last
        }
        return total + section
    }

    /// Plain decimal string without exponent or trailing zeros (1500, 1.5).
    private static func format(_ value: Decimal) -> String {
        var rounded = Decimal()
        var input = value
        NSDecimalRound(&rounded, &input, 12, .plain)
        return NSDecimalNumber(decimal: rounded).stringValue
    }

    // MARK: - Word classes

    private static func isNumberWord(_ word: String) -> Bool {
        if parseArabic(word) != nil { return true }
        guard word.count == 1, let c = word.first else { return false }
        return digits[c] != nil || smallUnits[c] != nil || bigUnits[c] != nil || tens[c] != nil
    }

    /// What may follow a decimal point: Chinese 零–九, or a plain Arabic integer.
    private static func isDigitWord(_ word: String) -> Bool {
        if word.count == 1, let c = word.first, digits[c] != nil { return true }
        let folded = fold(word)
        return !folded.isEmpty && folded.allSatisfy(\.isASCIIDigit)
    }

    private static func isPoint(_ word: String) -> Bool { word == "點" || word == "点" }

    private static func isBigUnit(_ word: String) -> Bool {
        word.count == 1 && word.first.map { bigUnits[$0] != nil } == true
    }

    /// One number word as Arabic digits: one Chinese digit per character;
    /// Arabic numerals lose their thousands separators.
    private static func digitsOf(_ word: String) -> String {
        if word.count == 1, let c = word.first, let digit = digits[c] {
            return String(digit)
        }
        return fold(word).replacingOccurrences(of: ",", with: "")
    }

    /// `^[0-9]+(,[0-9]{3})*(\.[0-9]+)?$` after folding full-width forms.
    private static func parseArabic(_ word: String) -> Decimal? {
        let folded = fold(word)
        let parts = folded.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return nil }
        if parts.count == 2 {
            guard !parts[1].isEmpty, parts[1].allSatisfy(\.isASCIIDigit) else { return nil }
        }
        let groups = parts[0].split(separator: ",", omittingEmptySubsequences: false)
        guard let head = groups.first, !head.isEmpty, head.allSatisfy(\.isASCIIDigit) else { return nil }
        for group in groups.dropFirst() where group.count != 3 || !group.allSatisfy(\.isASCIIDigit) {
            return nil
        }
        return Decimal(string: folded.replacingOccurrences(of: ",", with: ""), locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Full-width digits, commas and points (２，０００．５) become half-width.
    private static func fold(_ word: String) -> String {
        word.precomposedStringWithCompatibilityMapping
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}

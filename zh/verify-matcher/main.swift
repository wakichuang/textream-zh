import Foundation

// 中文比對回歸檢查：Textream for Windows 的 ZH-01～ZH-23、原版移植測試、數字正規化，
// 再加 Mac 專屬情境（Apple 一整段越來越長的辨識結果、繁體輸出、阿拉伯數字）。
// 同一組情境跑兩個比對：原版（LegacyMatcher，目前 SpeechRecognizer 的寫法）與新版（ZhPromptMatcher）。
// 用法：main <unihan-pinyin.tsv>；新版有任何一條沒過，結束碼為 1。

let pinyin = ZhPinyinTable(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))!

// MARK: - 兩個比對的共同介面

protocol Follower: AnyObject {
    var text: String { get }
    var position: Int { get }
    /// 逐句模式：這一句（上次重新起算以來）的辨識結果。
    func hear(_ transcript: String)
    /// 逐句模式：一句講完，下一句從目前位置開始比。
    func restart()
    /// Mac 串流模式：辨識工作到目前為止的完整辨識結果。
    func hearStream(_ fullTranscript: String)
    /// Mac 串流模式：講者停頓後再開口（語音活動偵測）。
    func pause(_ fullTranscript: String)
}

final class NewFollower: Follower {
    let matcher: ZhPromptMatcher
    var state = ZhPromptMatcher.State()
    init(_ script: String) {
        matcher = ZhPromptMatcher(words: splitTextIntoWords(script), pinyin: pinyin)
        state.recognized = matcher.advancePastAnnotations(from: 0)
        state.matchStart = state.recognized
    }
    var text: String { matcher.text }
    var position: Int { state.recognized }
    func hear(_ transcript: String) { matcher.match(transcript, state: &state) }
    func restart() { state.matchStart = state.recognized; state.recentPositions = [] }
    func hearStream(_ fullTranscript: String) { matcher.follow(fullTranscript: fullTranscript, state: &state) }
    func pause(_ fullTranscript: String) { matcher.sentenceBreak(fullTranscript: fullTranscript, state: &state) }
}

final class OldFollower: Follower {
    let matcher: LegacyMatcher
    init(_ script: String) { matcher = LegacyMatcher(words: splitTextIntoWords(script)) }
    var text: String { matcher.sourceText }
    var position: Int { matcher.recognizedCharCount }
    func hear(_ transcript: String) { matcher.match(transcript) }
    func restart() { matcher.matchStartOffset = matcher.recognizedCharCount; matcher.recentMatchPositions = [] }
    func hearStream(_ fullTranscript: String) { matcher.match(fullTranscript) }
    func pause(_ fullTranscript: String) {} // 原版沒有停頓切句
}

enum Mode: String { case perUtterance = "逐句", stream = "Mac 串流" }

struct Failure: Error { let message: String }

func check(_ condition: Bool, _ message: @autoclosure () -> String) throws {
    if !condition { throw Failure(message: message()) }
}

/// 每一句的辨識結果每次多 2 個字（部分結果）。逐句模式一句講完就重新起算（Windows 的 sherpa-onnx）；
/// Mac 串流模式的辨識結果一路接下去（Apple 一段辨識最長約一分鐘），句與句之間有停頓，
/// 由語音活動偵測觸發 sentenceBreak。
/// 回傳每一句講完時的位置；過程中只要倒退一次就失敗。
func feed(_ follower: Follower, _ mode: Mode, _ utterances: [String], before: String = "") throws -> [Int] {
    var afterEach: [Int] = []
    var last = follower.position
    var heard = before
    for utterance in utterances {
        let characters = Array(utterance)
        var k = min(2, characters.count)
        while k <= characters.count {
            let partial = String(characters[..<k])
            switch mode {
            case .perUtterance: follower.hear(partial)
            case .stream: follower.hearStream(heard + partial)
            }
            try check(follower.position >= last, "倒退了：\(last) → \(follower.position)（聽到「\(partial)」）")
            last = follower.position
            k = k == characters.count ? k + 1 : min(k + 2, characters.count)
        }
        heard += utterance
        switch mode {
        case .perUtterance: follower.restart()
        case .stream: follower.pause(heard)
        }
        afterEach.append(last)
    }
    return afterEach
}

/// 讀到第幾個可讀字（不算空白、標點）。
func readable(_ text: String, _ offset: Int) -> Int {
    text.prefix(offset).filter { $0.isLetter || $0.isNumber }.count
}

func reachesEnd(_ follower: Follower, _ position: Int, _ id: String) throws {
    let t = follower.text
    try check(position == t.count,
              "\(id)：停在可讀字 \(readable(t, position))／\(readable(t, t.count))，停在「\(String(t.dropFirst(position).prefix(12)))」之前")
}

// MARK: - 情境

/// 每個情境都要能拿兩種比對各跑一次，所以情境存的是「講稿」加「怎麼餵」。
struct Case {
    let id: String
    let title: String
    let script: String
    /// 逐句與串流行為相同的情境（一次給完、或只有一句）只跑一種。
    let modes: [Mode]
    let run: (Follower, Mode) throws -> Void
}
var cases: [Case] = []
func test(_ id: String, _ title: String, _ script: String, modes: [Mode] = [.perUtterance],
          _ run: @escaping (Follower, Mode) throws -> Void) {
    cases.append(Case(id: id, title: title, script: script, modes: modes, run: run))
}
let both: [Mode] = [.perUtterance, .stream]

// ── 原版移植測試（Textream PromptCoreTests.swift） ──

test("原版-1", "跳過 [標註]、英文模糊比對", "Welcome [smile] to the presentation today") { f, _ in
    f.hear("welcome to the")
    let first = f.position
    f.hear("welcome to the presentation")
    let second = f.position
    try check(first > "Welcome".count, "first = \(first)")
    try check(second >= first && second > "Welcome [smile] to the".count, "first = \(first), second = \(second)")
}

test("原版-2", "高亮不倒退", "one two three four five six") { f, _ in
    f.hear("one two three four")
    let forward = f.position
    f.hear("one")
    try check(forward > 0 && f.position == forward, "forward = \(forward), stale = \(f.position)")
}

// ── ZH-01～ZH-14：一次給完要到結尾（Windows 模型輸出簡體，這裡照用） ──

for (id, title, script, transcript) in [
    ("ZH-01", "同音字", "我已經讀完了", "我以经读完了"),
    ("ZH-02", "簡體輸出", "閱讀前哨站", "阅读前哨站"),
    ("ZH-03", "多音字", "銀行和行動", "银行和行动"),
    ("ZH-04", "國字念數字", "我在 2026 年寫這本書", "我在二零二六年写这本书"),
    ("ZH-05", "數字寫法不同", "一共兩千元", "一共2000元"),
    ("ZH-06", "中英混", "我讀了 Atomic Habits 這本書", "我读了 ATOMIC HABITS 这本书"),
    ("ZH-07", "標點跳過但算位置", "「卡片盒」筆記法。", "卡片盒笔记法"),
    ("ZH-08", "跳過 [標註]", "開場 [看鏡頭] 大家好", "开场大家好"),
    ("ZH-09", "跳讀一段", "第一段……第二段……第三段", "第一段第三段"),
    ("ZH-11", "同音（瓦基／哇基）", "瓦基", "哇基"),
    ("ZH-13", "全形半形", "ＡＩ工具", "ai工具"),
] {
    test(id, title, script) { f, _ in
        f.hear(transcript)
        try reachesEnd(f, f.position, id)
    }
}

for (id, script, transcript) in [
    ("ZH-01", "我已經讀完了", "我以经读完了"),
    ("ZH-02", "閱讀前哨站", "阅读前哨站"),
    ("ZH-03", "銀行和行動", "银行和行动"),
    ("ZH-11", "瓦基", "哇基"),
] {
    test("\(id)b", "同音、簡體逐字前進（不靠後面的字撿回來）", script) { f, _ in
        let characters = Array(transcript)
        for k in 1...characters.count {
            let fresh: Follower = f is NewFollower ? NewFollower(script) : OldFollower(script)
            fresh.hear(String(characters[..<k]))
            let expected = k < characters.count ? 2 * k : fresh.text.count
            try check(fresh.position == expected, "聽到「\(String(characters[..<k]))」，應該在 \(expected)，實際在 \(fresh.position)")
        }
    }
}

for (id, script, transcript, next) in [
    ("ZH-04b", "我在 2026 年寫這本書", "我在二零二六", "年"),
    ("ZH-04c", "我在二〇二六年寫這本書", "我在2026", "年"),
    ("ZH-05b", "一共兩千元", "一共2000", "元"),
    ("ZH-05c", "一共兩千元", "一共两千", "元"),
] {
    test(id, "只聽到數字就越過整個數字", script) { f, _ in
        let expected = Array(f.text).firstIndex(of: Character(next))!
        f.hear(transcript)
        try check(f.position == expected, "聽到「\(transcript)」，應該停在「\(next)」（\(expected)），實際在 \(f.position)")
    }
}

test("ZH-10", "辨識改口不倒退", "我已經讀完了，今天天氣很好") { f, _ in
    f.hear("我以经读完了")
    let first = f.position
    f.hear("我已")
    let corrected = f.position
    f.hear("我已经读完了今天天气")
    try check(first > 0 && corrected == first && f.position > first, "first = \(first), corrected = \(corrected), later = \(f.position)")
}

test("ZH-12", "罕用字與 emoji 不錯位", "我愛\u{2000B}🙂讀書") { f, _ in
    f.hear("我爱\u{2000B}读书")
    try reachesEnd(f, f.position, "ZH-12")
}

test("ZH-14", "中間單一個字不能跳過去", "今天想跟大家聊聊閱讀這件事，我們從某本書開始講起，然後再談到卡片盒筆記") { f, _ in
    f.hear("盒")
    try check(f.position == 0, "跳到 \(f.position)")
}

test("重新起算", "一句講完後，下一句從目前位置比", "我已經把這本書讀完了。今天很好。") { f, _ in
    f.hear("我已经把这本书读完了")
    try check(f.position > 0, "第一句沒前進")
    f.restart()
    f.hear("今天很好")
    try reachesEnd(f, f.position, "重新起算")
}

// ── ZH-15～ZH-23：容錯（插話、跳子標題、跳句、改講法），逐句與 Mac 串流各跑一次 ──

test("ZH-15", "跳過子標題", "所以這本書最後想說的是，好好照顧自己。\n\n## 四個步驟，照顧你的陰鬱小孩\n\n第一步是認出你的保護策略，看見自己在逃避什麼。", modes: both) { f, mode in
    let p = try feed(f, mode, ["所以这本书最后想说的是好好照顾自己", "第一步是认出你的保护策略看见自己在逃避什么"])
    try reachesEnd(f, p.last!, "ZH-15")
}

test("ZH-16", "跳過一整句", "今天要聊三件事。第一件事是閱讀的習慣，很多人覺得自己沒有時間讀書。第二件事是寫作，寫作其實是在整理思考。", modes: both) { f, mode in
    let p = try feed(f, mode, ["今天要聊三件事", "第二件事是写作写作其实是在整理思考"])
    try reachesEnd(f, p.last!, "ZH-16")
}

let awareness = "我讀完這本書之後，最大的收穫是學會了覺察。覺察就是有意識地看見自己的反應，然後選擇怎麼回應。"
test("ZH-17", "句與句之間插話", awareness, modes: both) { f, mode in
    let p = try feed(f, mode, ["我读完这本书之后最大的收获是学会了觉察", "对啊这个真的很重要我上礼拜还跟我太太聊到这件事情", "觉察就是有意识地看见自己的反应然后选择怎么回应"])
    try check(readable(f.text, p[1]) - readable(f.text, p[0]) <= 2, "插話期間從可讀字 \(readable(f.text, p[0])) 動到 \(readable(f.text, p[1]))")
    try reachesEnd(f, p.last!, "ZH-17")
}

test("ZH-18", "插話與原稿在同一句", awareness, modes: [.perUtterance]) { f, mode in
    let p = try feed(f, mode, ["我读完这本书之后最大的收获是学会了觉察对啊这个真的很重要我上礼拜还跟我太太聊到觉察就是有意识地看见自己的反应然后选择怎么回应"])
    try reachesEnd(f, p.last!, "ZH-18")
}

test("ZH-19", "改講法後接回", "這種習慣不是一天養成的，它需要時間慢慢累積。所以不要急，先給自己一點耐心，再一步一步往前走。", modes: both) { f, mode in
    let p = try feed(f, mode, ["这种习惯不是一天养成的", "就是说你要花很多功夫去一点一点地堆起来", "所以不要急先给自己一点耐心再一步一步往前走"])
    try reachesEnd(f, p.last!, "ZH-19")
}

test("ZH-20", "連續閒聊三句不漂移", "很多人一輩子都在別人身上找安全感，找伴侶、找朋友、找一份穩定的工作。可是作者說，真正的安全感是一個內在的家，要靠我們自己一磚一瓦蓋起來。這個家蓋好了，外面再怎麼風吹雨打，你都有地方可以回去。", modes: both) { f, mode in
    let chat = ["很多人一辈子都在别人身上找安全感找伴侣找朋友找一份稳定的工作", "好那我们先休息一下喝口水", "其实我昨天晚上睡得不太好所以今天声音有点哑", "等一下录完我还要去接小孩放学我们继续"]
    let p = try feed(f, mode, chat)
    try check(readable(f.text, p.last!) - readable(f.text, p[0]) <= 10, "閒聊後從可讀字 \(readable(f.text, p[0])) 跑到 \(readable(f.text, p.last!))")
    let rejoined = try feed(f, mode, ["可是作者说真正的安全感是一个内在的家要靠我们自己一砖一瓦盖起来"], before: mode == .stream ? chat.joined() : "")
    try check(readable(f.text, rejoined.last!) >= readable(f.text, p[0]) + 30, "閒聊完接不回原稿（停在可讀字 \(readable(f.text, rejoined.last!))）")
}

test("ZH-21", "插話裡的常用詞不跳過去", "第一段先講背景，作者是一位心理治療師，在德國執業超過二十年。第二段講方法，她把人的內心分成兩個小孩和一個大人，用很生活化的例子說明。第三段是心得，我覺得很多人都需要這樣的語言。最後推薦這本書給正在育兒的朋友。", modes: both) { f, mode in
    let p = try feed(f, mode, ["第一段先讲背景作者是一位心理治疗师在德国执业超过二十年", "我觉得这本书不错啦"])
    try check(readable(f.text, p[1]) - readable(f.text, p[0]) <= 2, "插話讓高亮從可讀字 \(readable(f.text, p[0])) 跳到 \(readable(f.text, p[1]))")
}

test("ZH-22", "句中跳過幾個字", "我覺得這本書最大的價值，在於它給了我們一套很好懂的語言。", modes: both) { f, mode in
    let p = try feed(f, mode, ["我觉得这本书最大的价值在于给了我们好懂的语言"])
    try reachesEnd(f, p.last!, "ZH-22")
}

test("ZH-23", "EP.659：常用詞組不把高亮騙到 200 字後", "簡單來說，這是一個站在百年傳統上的簡化工具。作者希望透過一個簡單易懂的比喻，幫你看懂自己為什麼會那樣反應。\n## 跟《蛤蟆先生去看心理師》有什麼不一樣？\n以前聽過我分享《蛤蟆先生去看心理師》的朋友，讀到這裡應該會覺得很熟悉。\n沒錯，兩本書是同一棵樹上的兩根分枝。\n「兒童自我、成人自我、父母自我」正是溝通分析（Transactional Analysis）的用語，也就是蒼鷺幫蛤蟆諮商的那套方法。史塔爾在書中沒有特別點名，但兩本書的根是同一條。\n兩本書的共同點很清楚：「童年經驗」會形塑我們今天的反應，而最終的出口都在「大人」這個狀態，也就是說，你要為自己負責。\n這兩本書之間，我認為有三個不一樣的地方。", modes: both) { f, mode in
    let p = try feed(f, mode, ["所以简单来讲这是一个站在百年传统上的一个简化的一个方法然后作者他希望可以透过一个",
                                 "简单好懂的比喻来帮你去看懂自己为什么会做出那些反应那接下来我们来看一下这本书跟蛤蟆先生去看心理师有什么不一样的地方因为以前很多朋友可能听过我分享蛤蟆先生去看心理师那本书嘛很多朋友都很喜欢这一本那读到这里的时候应该会"])
    let limit = f.text.distance(from: f.text.startIndex, to: f.text.firstIndex(of: "沒")!)
    try check(p.last! <= limit, "高亮跑到「\(String(f.text.prefix(p.last!).suffix(12)))」之後，超過了還沒念的「沒錯」")
}

// ── Mac 專屬：Apple 辨識輸出繁體、數字常寫成阿拉伯數字、一段辨識結果很長 ──

test("MAC-01", "Apple 把國字數字寫成阿拉伯數字", "那一年他三十六歲，搬到新的城市，而且換過三份工作。", modes: both) { f, mode in
    let p = try feed(f, mode, ["那一年他36歲搬到新的城市而且換過3份工作"])
    try reachesEnd(f, p.last!, "MAC-01")
}

test("MAC-02", "繁體同音錯字（已經→以經、瓦基→哇基）", "我是瓦基，我已經把這本書讀完了。", modes: both) { f, mode in
    let p = try feed(f, mode, ["我是哇基我以經把這本書讀完了"])
    try reachesEnd(f, p.last!, "MAC-02")
}

test("MAC-03", "一分鐘長的辨識結果：中途跳一段後繼續跟", String(repeating: "這是前面的鋪陳，我們慢慢念過去。", count: 3) + "接下來這一段我想跳過，因為今天時間不夠。最後一段是結論，閱讀是一輩子的事情，請你每天都讀一點。", modes: [.stream]) { f, mode in
    let p = try feed(f, mode, [String(repeating: "这是前面的铺陈我们慢慢念过去", count: 3), "最后一段是结论阅读是一辈子的事情请你每天都读一点"])
    try reachesEnd(f, p.last!, "MAC-03")
}

// MARK: - 數字正規化（Windows ChineseNumbersTests）

let numberCases: [(String, String)] = [
    ("我在 2026 年", "我|在|2026|年"), ("我在二零二六年", "我|在|2026|年"), ("二〇二六", "2026"), ("零九一二", "0912"),
    ("兩千零二十六年", "2026|年"), ("一共兩千元", "1|共|2000|元"), ("一共2000元", "1|共|2000|元"), ("两千", "2000"),
    ("十", "10"), ("十五", "15"), ("二十", "20"), ("二十五", "25"), ("一百零五", "105"), ("一千二百三十四", "1234"),
    ("三萬五千", "35000"), ("三万五千", "35000"), ("一億兩千萬", "120000000"), ("廿五", "25"), ("卅", "30"),
    ("一千五", "1500"), ("三百五", "350"), ("兩萬三", "23000"), ("2,000 元", "2000|元"), ("２０２６", "2026"),
    ("3萬", "30000"), ("1.5萬", "15000"), ("一點五萬", "15000"), ("三點一四", "3.14"), ("3.14", "3.14"),
    ("三點開會", "3|點|開|會"), ("讀了 Atomic Habits", "讀|了|Atomic|Habits"), ("COVID-19", "COVID-19"),
    ("參加大陸", "參|加|大|陸"), ("一點一點", "1.1|點"), ("一点一点", "1.1|点"),
    // Mac 專屬：標點黏在字上時，數字不跨過標點（比對用的文字本來就不含標點）
    ("兩千，三百", "2000|300"), ("「三」", "3"), ("三份工作", "3|份|工|作"),
]

// MARK: - 執行

var newFailures = 0
var rows: [String] = []
for c in cases {
    for mode in c.modes {
        var cells: [String] = []
        for make in [{ OldFollower(c.script) as Follower }, { NewFollower(c.script) as Follower }] {
            let follower = make()
            do {
                try c.run(follower, mode)
                cells.append("✅")
            } catch let failure as Failure {
                cells.append("❌ \(failure.message)")
                if follower is NewFollower { newFailures += 1 }
            }
        }
        rows.append("| \(c.id) | \(c.title) | \(mode.rawValue) | \(cells[0]) | \(cells[1]) |")
    }
}
print("| 編號 | 情境 | 餵法 | 原版 | 新版 |")
print("| :-- | :-- | :-- | :-- | :-- |")
rows.forEach { print($0) }

var numberFailures = 0
for (input, expected) in numberCases {
    let words = splitTextIntoWords(input)
    let actual = ZhNumbers.normalize(words).map(\.text).joined(separator: "|")
    if actual != expected {
        numberFailures += 1
        print("數字正規化 ❌ 「\(input)」應為 \(expected)，實際 \(actual)")
    }
}
print("數字正規化：\(numberCases.count - numberFailures)／\(numberCases.count) 通過")
print("拼音表：\(pinyin.count) 字；行 = \(pinyin.soundKeys(of: "行"))")

// 速度：一分鐘長的辨識結果
let longScript = String(repeating: "很多人一輩子都在別人身上找安全感，找伴侶、找朋友、找一份穩定的工作。", count: 40)
let speed = NewFollower(longScript)
let longTranscript = String(repeating: "很多人一辈子都在别人身上找安全感找伴侣找朋友找一份稳定的工作", count: 10)
let clock = ContinuousClock()
var calls = 0
let elapsed = clock.measure {
    var k = 2
    let chars = Array(longTranscript)
    while k <= chars.count {
        speed.hearStream(String(chars[..<k]))
        calls += 1
        k += 2
    }
}
let perCall = Double(elapsed.components.attoseconds) / 1e15 / Double(calls) + Double(elapsed.components.seconds) * 1000 / Double(calls)
print(String(format: "速度：%d 字的辨識結果分 %d 次餵，平均每次 %.2f 毫秒，最後追到可讀字 %d", longTranscript.count, calls, perCall, readable(speed.text, speed.position)))

print(newFailures == 0 && numberFailures == 0 ? "新版全部通過" : "新版有 \(newFailures + numberFailures) 條沒過")
exit(newFailures == 0 && numberFailures == 0 ? 0 : 1)

# AGENTS.md：Textream 繁中改版

瓦基自己在 MacBook 上用的 Textream 改版。上游是 [f/textream](https://github.com/f/textream)（MIT），本 repo 只修繁體中文的問題，其餘跟原版一致。

## 遠端與分支

- `origin` → `wakichuang/textream-zh`（private）；`upstream` → `f/textream`。
- 分支沿用原版的 `master`，方便合併上游：`git fetch upstream && git merge upstream/master`。
- 改動盡量集中、少碰原版的其他地方，合併上游時衝突才小。改過的地方在下面「改動清單」記一行。

## 改動清單

| 檔案 | 改了什麼 | 為什麼 |
| :-- | :-- | :-- |
| `Textream/Textream/MarqueeTextView.swift` `splitTextIntoWords` | 全形標點不再單獨成字：開頭類（「（《“）黏到下一個字，其餘黏到前一個字；一行一行處理，不跨行黏 | 單獨的標點會被當成「標註」顯示成斜體變淡，寬度也量錯（上游 issue #128） |
| 同檔 `buildLines` | 寬度改成整串量 `word + " "`，再 `floor + 1` | 分開量會少算全形標點約 10 pt，整行超寬時 SwiftUI 把數字、英文縮成「…」 |
| 同檔 `wordView` | 每個字的 `Text` 加 `.fixedSize()` | 保險：萬一還是估錯，也不會吃字 |

## 驗證

- `zh/verify-layout/run.sh`：只需要 Command Line Tools。切字結果、四種字型在 200～800 pt 每種寬度下有沒有任何一行超出容器，並畫出 PNG。**合併上游之後一定要跑**，「超出容器的行」必須是 0、「被當成標註的字」必須是空的。
- 語音追蹤的比對（`SpeechRecognizer.swift`）會先濾掉標點，所以標點黏在字上不影響追蹤；改切字規則時要記得這一點。
- iOS 版（`TextreamiOS/`）有自己的一套切字（`PromptTextProcessor.swift`），本改版沒動。

# AGENTS.md：Textream 繁中改版

瓦基自己在 MacBook 上用的 Textream 改版。上游是 [f/textream](https://github.com/f/textream)（MIT），本 repo 只修繁體中文的問題，其餘跟原版一致。

## 遠端與分支

- `origin` → `wakichuang/textream-zh`（**public**，f/textream 的正式 fork，2026-10-08 起）；`upstream` → `f/textream`。這是公開 repo：個人路徑、email、金鑰、錄音一律不進來。
- 分支沿用原版的 `master`，方便合併上游：`git fetch upstream && git merge upstream/master`。
- 改動盡量集中、少碰原版的其他地方，合併上游時衝突才小。改過的地方在下面「改動清單」記一行。

- `README.md` 是繁中版自己的說明；原版的英文 README 搬到 `docs/README.upstream.md`。合併上游時 README 衝突一律保留繁中版，原版改了什麼再手動更新 `docs/README.upstream.md`。

## 版本號與發佈

- 版本號用 4 段數字：`原版版本.繁中版第幾版`，例如基於原版 1.7.1 的第一版是 `1.7.1.1`，小修就 `1.7.1.2`，合併原版 1.7.2 之後變 `1.7.2.1`。不能加文字（`1.7.1-zh`），因為 `UpdateChecker` 只比數字，文字會被忽略。
- 發佈步驟：改 `Textream/Textream.xcodeproj/project.pbxproj` 裡 macOS 三組設定（Debug、Release、AppStore）的 `MARKETING_VERSION` → 跑 `zh/verify-layout/run.sh`、`zh/verify-matcher/run.sh` → `zh/install.sh` → commit、推送 → `gh release create v<版本> --title "Textream 繁中版 <版本>（基於原版 x.y.z）" --notes-file <說明>`。README 安裝步驟裡的 `--branch v…` 一起改成新版。
- 目前只發原始碼，不附 DMG：沒有 Apple Developer Program 的 Developer ID 簽名與公證，別人下載了也打不開。
- 發佈是公開動作，要瓦基點頭才做。

## 改動清單

| 檔案 | 改了什麼 | 為什麼 |
| :-- | :-- | :-- |
| `Textream/Textream/MarqueeTextView.swift` `splitTextIntoWords` | 全形標點不再單獨成字：開頭類（「（《“）黏到下一個字，其餘黏到前一個字；一行一行處理，不跨行黏 | 單獨的標點會被當成「標註」顯示成斜體變淡，寬度也量錯（上游 issue #128） |
| 同檔 `buildLines` | 寬度改成整串量實際顯示的 `displayText`，再 `ceil` | 分開量會少算全形標點約 10 pt，整行超寬時 SwiftUI 把數字、英文縮成「…」；實測 SwiftUI 寬度＝`ceil`（672 筆無例外） |
| 同檔 `wordView` | 每個字的 `Text` 加 `.fixedSize()` | 保險：萬一還是估錯，也不會吃字 |
| 同檔 `displaySeparator`、`WordItem.displayText` | 中文字（漢字、假名）之間不顯示空白；全形標點後面放極細空白 U+200A；中英、數字、韓文之間保留空白。只改顯示，`charOffset` 照舊每字算一個空白 | 原版每個中文字後面都有空白，字距鬆。標點若落在一段 `Text` 的最尾巴，右半邊會被裁掉、看起來黏到下一個字，極細空白能讓它保持全寬 |
| 同檔 `leadingPunctuationTrim`、`WordItem.trailingTrim` | 開頭是全形開括號的字（「自、《原），尾端用負的 padding 扣回 Core Text 縮掉的量 | Core Text 會把開括號左半邊縮掉，但回報的寬度沒扣，字後面多出約 1.8 pt 的空隙 |
| `Textream/Textream/ZhMatching/`（新增） | 移植 Textream for Windows 的中文比對：`ZhPinyinTable`（Unihan 讀音表，所有讀音）、`ZhNumbers`（國字／阿拉伯數字統一）、`ZhPromptMatcher`（字元層＋詞層、讀音集合比對、防拖走、找回位置）。門檻與 Windows 版相同：對不上前後各找 5 個、找回位置往後 400 個可讀單位、基本連續 5 個、每遠 50 個多 1 個 | 原版前後只容錯 5 個單位、字要完全一樣，跳過一兩句或子標題就卡住；同音錯字、Apple 把「三」寫成「3」也對不上 |
| `UpdateChecker.swift`、`TextreamApp.swift` | 檢查更新改查 `wakichuang/textream-zh` 的 Releases；選單「檢查更新…」與所有對話框改成中文，有新版時提示下載原始碼後跑 `zh/install.sh`（1.7.1.2） | 原本查 `f/textream`，照提示更新會裝回原版、修正全部消失；英文介面加上 Release 只有原始碼，使用者不知道怎麼更新 |
| `.github/ISSUE_TEMPLATE/`（新增） | 中文的「問題回報」「改善建議」兩張 issue 表單，README 加「回報問題與建議」一節與範例；GitHub 上的 Issues 於 2026-10-09 打開 | fork 預設關閉 Issues，朋友想回報問題、提建議沒有地方提；表單要求貼講稿文字與版本號，拿到就能直接跑測試重現 |
| `SpeechRecognizer.swift` `matchCharacters`、`recordAudioLevel` | 有 `zhMatcher` 就交給它比對；停頓後再開口（語音活動偵測由不活躍轉活躍）時呼叫 `sentenceBreak`。原版的 `charLevelMatch`／`wordLevelMatch` 原封不動留著 | Apple 的辨識一段最長約一分鐘、不會每句重來；不切句的話，長段插話的漂移會累積，被常用詞一次確認跳太遠（ZH-20）。留著原版函式給測試當對照組，也讓合併上游衝突小 |

## 安裝到這台 Mac

- `zh/install.sh`：Xcode 編譯 Release（Apple Silicon）、用 Apple Development 憑證簽名、舊版移到垃圾桶、裝到 `/Applications/Textream.app` 並開啟。改完程式碼就跑它。
- 不用 Xcode 自動簽名：識別碼 `dev.fka.textream` 登記在原作者的團隊，自動簽名會失敗；沙盒、麥克風、網路這幾項權限在 macOS 不需要描述檔，直接 `codesign` 就好。
- 簽名要固定用同一張憑證，麥克風與語音辨識權限才不會每次重編就失效。憑證有效到 2027-10-08，到期在 Xcode → Settings → Accounts 重建。
- Homebrew 版已卸載，不要再 `brew install --cask textream`，不然會蓋回原版。

## 驗證

- `zh/verify-layout/run.sh`：只需要 Command Line Tools（裝了 Xcode 但還沒同意授權時，前面加 `DEVELOPER_DIR=/Library/Developer/CommandLineTools`）。切字結果、四種字型在 200～800 pt 每種寬度下有沒有任何一行超出容器，並畫出 PNG。**合併上游之後一定要跑**，「超出容器的行」必須是 0、「被當成標註的字」必須是空的。
- `zh/verify-matcher/run.sh`：中文比對回歸檢查，只要 Command Line Tools。同一組情境（Windows 的 ZH-01～ZH-23、原版移植測試、Mac 專屬 MAC-01～03、數字正規化 38 條）跑原版與新版兩個比對，印成表格；**新版必須全綠**。原版的比對是從 `SpeechRecognizer.swift` 原樣抽出來的（`make_legacy.py`），所以原版函式不要刪。
- `zh/verify-matcher/mutations.py`：突變檢查，逐一拿掉找回位置、防拖走、讀音比對、數字正規化、停頓切句，每一項都要有測試變紅。**改比對規則之後兩支都要跑。**
- 「Mac 串流」餵法模擬 Apple 一整段越來越長的辨識結果、句與句之間有停頓；「逐句」餵法模擬 Windows 每句重來。
- 語音追蹤的比對（`SpeechRecognizer.swift`）會先濾掉標點，所以標點黏在字上不影響追蹤；改切字規則時要記得這一點。
- iOS 版（`TextreamiOS/`）有自己的一套切字與比對（`PromptTextProcessor.swift`、`PromptMatcher.swift`），本改版沒動。
- 第三方資料的授權聲明在 `zh/THIRD_PARTY_NOTICES.md`（Unihan 讀音表，Unicode License v3）。

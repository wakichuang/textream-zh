<p align="center">
  <img src="Textream/Textream/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" height="128" alt="Textream icon">
</p>

<h1 align="center">Textream 繁中版（非官方）</h1>

<p align="center">
  <strong>為繁體中文講稿調整過的 Textream，語音追蹤提詞機（macOS）。</strong>
</p>

---

## 這是什麼

[Textream](https://github.com/f/textream) 是 Fatih Kadir Akin 開發的免費、開源提詞機，邊念邊用語音辨識高亮你念到的地方，以 MIT 授權釋出。

原版的比對規則是照英文設計的，念中文稿會遇到幾個問題：

- 播放時數字、英文或標點被縮成「…」。
- 全形標點變成斜體、變淡。
- 中文字之間的字距太鬆。
- 跳過一兩句、插一段話之後，高亮就卡住不動。
- 講到一半想往前回看、往後跳一段，滑鼠滾輪沒有反應。

這個版本只針對這些地方做修改，其他功能與原版相同。

**這不是官方版本**，跟原作者沒有合作關係。Textream 的名稱與圖示屬於原作者。中文的問題已經回報給原作者（[f/textream#128](https://github.com/f/textream/issues/128)），原版修好的部分，這裡會跟著同步。

## 跟原版差在哪

| 項目 | 原版念中文稿時 | 繁中版 |
| :-- | :-- | :-- |
| 數字、英文被吃字 | 一行塞不下時，「36」「Heptabase」被縮成「…」，數字還會擠成直排 | 寬度照實際畫出來的量，不會吃字 |
| 全形標點 | 「，。：「」」被當成標註，顯示成斜體、變淡，前面多一個空白 | 標點黏在前一個字上（開括號黏後一個字），照一般文字顯示 |
| 字距 | 每個中文字後面都有一個空白 | 中文字之間不留空白；中英文、數字之間保留空白 |
| 同音錯字 | 辨識出「以經」就對不上稿子的「已經」 | 比讀音，同音字、簡體、多音字都算對 |
| 數字寫法 | 稿子寫「三份」、辨識出「3份」就對不上 | 國字與阿拉伯數字統一後再比 |
| 跳句、跳子標題 | 只往後找 5 個字，跳超過就卡住 | 往後找最多 400 個字，連續對上 5 個字以上就跳過去，跳越遠要對上越多字，避免高亮跑到你前面 |
| 插話、改講法 | 插話裡零星的同音字會把高亮一格一格拖走 | 要連續對上才算數；停頓後再開口就從目前位置重新比對 |
| 滾輪 | 語音追蹤時只有暫停才能滾，而且只是偷看，按繼續就彈回原處 | 播放中也能滾，一格跳一行，接著講就從那裡往下追；瀏海、浮動、全螢幕、外接螢幕都可以 |

中文的比對規則移植自作者自己另外開發的 Windows 版，同一套規則已經用真實的 Podcast 錄音調過門檻。

## 安裝

目前只提供原始碼，需要自己用 Xcode 編譯，還沒有簽好名、可以直接下載的安裝檔。

1. 從 App Store 安裝 Xcode，打開一次並同意授權條款。
2. 在 Xcode → Settings → Accounts 登入 Apple ID（免費帳號即可），在 Manage Certificates 建立一張 Apple Development 憑證。
3. 下載原始碼：到 [Releases](https://github.com/wakichuang/textream-zh/releases/latest) 下載最新版的原始碼壓縮檔並解壓縮，或用 git 指定版本 clone（直接 clone 拿到的是開發中的最新內容，不一定是發佈版）：

```bash
git clone --branch v1.7.1.3 https://github.com/wakichuang/textream-zh.git
```

4. 在下載的資料夾裡執行：

```bash
zh/install.sh
```

腳本會編譯、用你的憑證簽名、裝到「應用程式」資料夾並開啟。第一次開啟時，macOS 會詢問麥克風與語音辨識權限，按允許即可。

- 如果已經用 Homebrew 裝過原版，先 `brew uninstall --cask textream`，免得 `brew upgrade` 把原版蓋回來。
- 如果出現「找不到 Apple Development 憑證」，但 Xcode 裡明明有，通常是鑰匙圈缺少 Apple 的 WWDR G3 中繼憑證，可以到 [Apple PKI](https://www.apple.com/certificateauthority/) 下載 `AppleWWDRCAG3.cer` 加進鑰匙圈。
- 每次開啟 App 會自動檢查有沒有新版，有才會跳出通知；也可以手動檢查：螢幕最上方選單列的「Textream」→「檢查更新…」。查的是繁中版的發佈版本，不會把你換回原版。有新版時照第 3、4 步重裝一次即可。

## 回報問題與建議

用起來卡卡的、高亮跟丟了，或是想要什麼新功能，都歡迎到 [Issues](https://github.com/wakichuang/textream-zh/issues/new/choose) 告訴我。需要一個 GitHub 帳號（免費）。

1. 點上面的連結，選「問題回報」或「改善建議」。
2. 照表單一格一格填，標題寫一句話講重點。
3. 按「Create」送出。我回覆或修好之後，GitHub 會寄信通知你。

幾個讓我更快修好的小訣竅：

- **講稿貼文字，不要截圖。** 我會把你貼的那幾句直接拿去跑測試，截圖沒辦法跑。不想公開的內容，換成一段一樣會出問題的文字就好。
- **附上版本號。** 選單列「Textream」→「About Textream」可以看到，例如 `1.7.1.2`。
- **一個問題開一則。** 兩個問題混在一起，修好一個就很難關。

### 範例：問題回報

以下兩則都是虛構的範例，示範怎麼寫。

> **標題**：[問題] 插話之後高亮跳回第一段
>
> **發生了什麼事**：念到第三段時臨時插了一段即興分享，再回到稿子，高亮就跳回第一段的開頭。
>
> **怎麼重現**：
> 1. 貼上下面的講稿
> 2. 按開始，從第一句念起
> 3. 念到第三段時插話 30 秒左右，再接著念稿子
>
> **講稿片段**：
> ```text
> 第三段：上個月我讀完《原子習慣》，最有感的是兩分鐘法則。
> 插話：（這邊我多講了一段自己早上跑步的經驗）
> 接回稿子：所以重點不是目標多大，而是先讓自己開始。
> ```
>
> **版本**：1.7.1.2，macOS 26.0、MacBook Air M2

### 範例：改善建議

> **標題**：[建議] 英文專有名詞念不準時也能跟上
>
> **使用情境**：錄 YouTube 時把 Textream 放在鏡頭正下方，一次念 10 分鐘左右的稿子。
>
> **現在哪裡不方便**：稿子裡有很多英文專有名詞，念的時候常常要停下來，高亮就跟丟了。
>
> **希望變成怎樣**：英文單字念錯一兩個音也能算對上，或是可以先標記哪些詞可以跳過。

原版 Textream 本身的問題（跟中文無關的功能），也可以直接回報給原作者：[f/textream Issues](https://github.com/f/textream/issues)。不確定是哪一邊的問題，就先回報在這裡，我會幫忙判斷。

## 驗證

三支檢查都只需要 Xcode 附帶的命令列工具：

| 指令 | 檢查什麼 |
| :-- | :-- |
| `zh/verify-layout/run.sh` | 切字結果；四種字型在 200 到 800 pt 的每一種寬度下，有沒有任何一行超出畫面（超出就會被吃字） |
| `zh/verify-matcher/run.sh` | 中文比對：同音字、簡體、數字、跳句、插話、改講法等情境，原版與繁中版各跑一次並列成表格 |
| `python3 zh/verify-matcher/mutations.py` | 故意拿掉每一項新規則，確認測試真的會失敗 |
| `zh/verify-scroll/run.sh` | 滾輪逐行跳轉：一格跳幾行、跳到哪一行開頭、不跳過最後一行；`python3 zh/verify-scroll/mutations.py` 做同樣的突變檢查 |

改了哪些檔案、為什麼改，列在 [AGENTS.md](AGENTS.md) 的「改動清單」。

## 關於作者

Textream 繁中版由[瓦基](https://readingoutpost.com/)製作。我是書評部落格《閱讀前哨站》和說書頻道《下一本讀什麼？》的創辦人，錄 Podcast、錄影片，都是看著稿子講。原版 Textream 對繁體中文的支援度不夠，念稿時有時候會漏字，有時候會判斷不準，有些效果不是我要的，所以我動手改成繁中版，把這些地方一一調整好。

► 想認識更多關於我？

- [閱讀前哨站](https://readingoutpost.com/)：我的書評部落格，寫讀過的好書與心得，也記錄把書中方法用在生活與工作的實踐。
- [下一本讀什麼？](https://readingoutpost.com/podcast/)：我的說書節目，在 Podcast 與 [YouTube](https://www.youtube.com/@readingoutpost) 同步播出，用 30 分鐘帶你吸收一本好書的精華與心得。
- [AI 瓦基第二大腦](https://readingoutpost.com/recommends/waki-ai/)：線上課程。你想讓 AI 成為工作夥伴，而不是用得越多越挫折嗎？我將一人公司的方法結合 AI 協作，設計出一套簡單好上手的 AI 課程。跟著流程走，透過十個專案包示範，帶你做出好成果。
- 追蹤我：[Facebook](https://www.facebook.com/ReadingOutpost/)・[Instagram](https://www.instagram.com/readingoutpost/)・[Threads](https://www.threads.net/@readingoutpost)

這個程式永遠免費。如果它讓你錄影時少低頭找幾次稿，**點顆星**我會很開心。

## 授權與致謝

- 原版 Textream：Copyright (c) 2026 Fatih Kadir Akin，[MIT License](LICENSE)。最初的點子來自 [Semih Kışlar](https://x.com/semihdev)。
- 繁中版的修改部分同樣以 MIT License 釋出。
- 中文讀音表取自 Unicode Unihan 資料庫（Unicode License v3），內建的 OpenDyslexic 字型為 SIL Open Font License 1.1，詳見 [zh/THIRD_PARTY_NOTICES.md](zh/THIRD_PARTY_NOTICES.md)。

原版的完整英文說明（功能、iPhone 版、外部控制 API 等）保留在 [docs/README.upstream.md](docs/README.upstream.md)。

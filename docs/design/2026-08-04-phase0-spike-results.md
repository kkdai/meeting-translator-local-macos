# Phase 0 Spike 結果：WhisperKit（STT）

日期：2026-08-04
狀態：STT 部分完成並驗證；翻譯（MLX Gemma 4）部分因環境限制暫停，見文末

測試機器：MacBook Air, Apple M4, 16GB 統一記憶體, macOS 15.7.8, 僅安裝 Command Line Tools（無完整 Xcode）

---

## 測試方法

- 套件：`argmaxinc/argmax-oss-swift` v1.0.0（WhisperKit）
- 建置方式：純 `swift build`（**不需要 Xcode**，見下方「環境發現」）
- 測試音訊：用 macOS `say` 合成兩段 ~9 秒語音（非真人錄音，僅供延遲/正確性初步驗證用）：
  - 英文（`Samantha`，en_US）："This feature is really important. Let me show you how the live demo works. We need to finish the report by Friday."
  - 中文（`Tingting`，zh_CN 簡體發音引擎）：「這個功能非常重要。讓我展示一下這個即時 demo。我們需要在星期五之前完成這份報告。」
- 每個模型/語言組合跑 3 次（1 次 warm-up 不計時 + 3 次計時），取平均
- 程式碼：`spike/Sources/WhisperSpike/main.swift`

---

## 結果：延遲

| 模型 | 磁碟大小 | 語言 | 平均轉錄時間（9秒音訊） | 相對即時倍數 |
|---|---|---|---|---|
| tiny | ~39MB | en（強制） | 0.137s | ~66x |
| tiny | ~39MB | zh（強制） | 0.121s | ~74x |
| base | ~145MB | en（自動偵測） | 0.190s | ~47x |
| base | ~145MB | zh（強制） | 0.152s | ~59x |
| small | ~465MB | en（強制） | 0.439s | ~20x |
| small | ~465MB | zh（強制） | 0.407s | ~22x |

三個模型的下載總大小 703MB（磁碟上實測）。模型載入（含首次下載）耗時 4.5–71 秒不等，屬一次性成本，不影響串流階段的逐句延遲。

**結論**：三個模型都遠遠超過「快速」的門檻，即使是 `small` 也有 20 倍以上即時速度。這代表模型大小的選擇可以優先考慮**準確度**而非速度 — `small` 甚至更大的 `base`/`large-v3-turbo` 都還有大量延遲餘裕，不需要為了速度被迫用 `tiny`。

---

## 結果：語言與繁簡體行為（重要發現，修正 feasibility 文件的假設）

1. **語言自動偵測在合成語音上會誤判**：不指定 `language` 參數（讓 WhisperKit 自動偵測）時，中文測試音訊被誤判成英文，輸出英文（且內容錯誤／幻覺）。這不是「翻譯」行為（`task` 預設就是 `.transcribe` 而非 `.translate`，已從原始碼確認），純粹是語言偵測本身誤判。
   - **設計含意**：不應完全依賴自動語言偵測。建議讓使用者在 UI 明確指定「主要語言」（比照原專案的目標 App 選擇），或至少提供偵測失敗時的手動覆蓋選項。這點需要在正式產品的 `LocalSTTEngine` 設計中補上。
2. **強制指定 `language: "zh"` 後，三個模型（tiny/base/small）都直接輸出繁體中文**，不是簡體：
   ```
   這個功能非常重要,讓我展示一下這個即時,我們需要在星期五之前完成這份報告。
   ```
   這與 feasibility 文件原本「Whisper 中文輸出傾向簡體，需要 OpenCC 後處理」的假設**不符**。至少在這次測試的多語言 checkpoint 上，繁體是預設輸出。
   - **修正**：OpenCC 後處理保險層仍建議保留（風險低、成本低，且無法保證所有模型版本/所有語者腔調都有一致行為），但不再是「已知必要」，降級為「保守防呆」而非「已知會踩的坑」。
3. 中文轉錄有一段文字掉字（"即時 demo" 的 "demo" 部分沒有被正確轉錄出來）。追查後判斷是測試腳本產生語音時，"demo" 這個英文字混在中文句子裡，TTS 引擎念得不清楚，導致原始音訊本身品質有問題，不是 WhisperKit 的辨識瑕疵。**這也連帶指出一個真實會議場景會遇到的情況**：中英夾雜（例如中文會議中夾雜英文術語）是需要額外驗證的場景，合成測試音訊無法完全代表，需要在 Phase 1 用真人錄音（含中英夾雜語句）重新驗證。

---

## 環境發現：不需要完整 Xcode 就能建置 WhisperKit

原本擔心這台機器只有 Command Line Tools、沒有完整 Xcode.app（`xcodebuild` 無法使用，也沒有 `coremlcompiler` / `xcrun metal`）會卡住整個 Phase 0。實測結果：

- WhisperKit 使用**已經編譯好的 Core ML 模型**（從 HuggingFace 下載 `.mlmodelc`），不需要在本機做 Core ML 編譯，因此不需要 `coremlcompiler`
- 純 `swift build` / `swift run` 即可建置成功，不需要 `xcodebuild`
- 官方 README 雖然列出「Prerequisites: Xcode 16+」，但那是針對「在 Xcode 專案中使用」的情境；命令列 SPM 建置實測可行

**這對正式產品開發也是好消息**：STT 這條路線不會被「使用者機器沒裝完整 Xcode」卡住（雖然一般使用者是裝好的 App，不需要自己建置，但這代表 CI/CD 也可以用較輕量的建置環境）。

---

## 翻譯（MLX Gemma 4）部分：卡在 Metal 編譯器

與 WhisperKit 不同，MLX Swift **需要在建置期編譯自訂 Metal shader**，這需要完整 Xcode.app 提供的 Metal 編譯器（`xcrun metal`），而 Command Line Tools 沒有附帶這個工具（實測 `xcrun metal --version` 報錯 "unable to find utility"）。

這台測試機目前只有 Command Line Tools，沒有安裝完整 Xcode（`/Applications` 下沒有 Xcode.app）。完整 Xcode 是數 GB 到十幾 GB 的下載，安裝也需要一些時間 — 這是需要使用者確認才能繼續的動作，已另外向使用者確認是否要安裝。

翻譯延遲驗證（Gemma 4 E2B/E4B 的 tokens/sec、首字延遲、與 WhisperKit 同時載入的記憶體峰值）待 Xcode 安裝後補做，補做後會更新本文件或另開一份 `2026-08-04-phase0-spike-results-translation.md`。

---

## 對 Phase 0 判斷準則的初步結論

| 驗證項目 | 狀態 | 結論 |
|---|---|---|
| WhisperKit 串流延遲是否夠快 | ✅ 已驗證 | 遠超預期，20-74x 即時速度，模型大小可優先選準確度 |
| Whisper 中文辨識簡繁體傾向 | ✅ 已驗證 | 直接輸出繁體（與原假設相反），OpenCC 降級為保險層 |
| 語言自動偵測穩定性 | ⚠️ 發現風險 | 合成音訊上會誤判，需要人工指定語言或偵測失敗的 fallback 機制 |
| MLX Gemma 4 翻譯延遲 | ⏸ 阻塞中 | 需要完整 Xcode（Metal 編譯器），待使用者決定是否安裝 |
| 雙模型併發記憶體峰值 | ⏸ 阻塞中 | 同上，需要先跑起 MLX 那一半才能測 |
| 中英夾雜場景辨識品質 | 📋 待補測 | 需要真人錄音樣本，合成語音無法代表，列入 Phase 1 |

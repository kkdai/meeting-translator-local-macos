# 架構設計：本地化元件對照與資料流

日期：2026-08-04
狀態：草案

---

## 元件對照表（原專案 → 本地版）

| 原檔案 | 角色 | 本地版處置 |
|---|---|---|
| `AudioCaptureManager.swift` | ScreenCaptureKit 擷取指定 App 音訊，重採樣為 16kHz mono PCM16 | **直接沿用**，與後端模型無關，不需修改 |
| `GeminiLiveConnection.swift` | WebSocket 雙向串流：送音訊、收原文/翻譯逐字稿、收配音 PCM | **移除**，拆成兩個獨立本地元件：`LocalSTTEngine.swift`（WhisperKit）+ `LocalTranslationEngine.swift`（MLX Gemma 4） |
| `AudioPlaybackManager.swift` | 播放 Gemini 回傳的翻譯配音 | **v1 移除**（無本地 TTS），Phase 6 若導入 TTSKit 再復用此模式 |
| `GeminiSummaryService.swift` | 呼叫 Gemini `generateContent` 產生會議摘要 | 改為 `LocalSummaryService.swift`，呼叫同一顆 Gemma 4（長 context 直接摘要） |
| `ContentView.swift`（`TranslatorViewModel`） | 狀態管理、UI 組裝、匯出邏輯 | **沿用架構**，`GeminiLiveConnectionDelegate` 換成新的 `LocalSTTDelegate` / `LocalTranslationDelegate`；API Key 欄位換成「模型狀態／下載進度」欄位 |
| `FloatingSubtitleWindow.swift` | 懸浮字幕視窗（NSPanel） | **直接沿用**，UI 邏輯與後端無關 |
| `MeetingMinutesView.swift` | 顯示 AI 摘要的 sheet | **直接沿用** |
| `MeetingNotesEditor.swift` | Markdown 筆記編輯 + 貼圖 | **直接沿用** |
| `NotesPreviewView.swift` | WKWebView 即時預覽 | **直接沿用** |
| `MarkdownRenderer.swift` | Markdown → HTML | **直接沿用** |
| `TranslatorApp.swift` | App 進入點 | **沿用**，新增模型初始化生命週期（App 啟動時載入/檢查 WhisperKit 與 MLX 模型） |
| — | — | **新增** `OpenCCConverter.swift`：簡體→繁體台灣慣用語後處理（見 feasibility 文件風險 1） |
| — | — | **新增** `ModelManager.swift`：管理 WhisperKit / Gemma 4 模型的下載、版本、儲存路徑、載入狀態 |

---

## 資料流

```
[目標 App 音訊輸出]
        │  ScreenCaptureKit
        ▼
AudioCaptureManager  ── 16kHz mono PCM16 ──▶  LocalSTTEngine (WhisperKit, 串流)
                                                       │
                                     partial / final transcript segments
                                                       │
                                                       ▼
                                     句子邊界偵測（沿用 checkAndRotateSubtitle 邏輯）
                                                       │
                                    ┌──────────────────┴───────────────────┐
                                    │                                      │
                         原文已是中文？                          原文為其他語言
                                    │                                      │
                          OpenCCConverter (s2twp)              LocalTranslationEngine
                                    │                          (MLX, Gemma 4 E4B)
                                    │                                      │
                                    │                          OpenCCConverter (s2twp，保險)
                                    └──────────────────┬───────────────────┘
                                                        ▼
                                        SubtitleLine { originalText, translatedText }
                                                        │
                                    ┌───────────────────┼────────────────────┐
                                    ▼                   ▼                    ▼
                          主視窗字幕列表      FloatingSubtitleWindow    subtitleHistory（累積）
                                                                              │
                                                                     stop() 觸發
                                                                              │
                                                        ┌─────────────────────┼─────────────────────┐
                                                        ▼                     ▼                     ▼
                                          exportTranscript()      LocalSummaryService        exportWebPage()
                                          (雙語逐字稿 .md)         (Gemma 4 長 context 摘要)   (HTML，整合摘要+筆記+逐字稿)
```

---

## 關鍵設計決策

### 1. STT 與翻譯是兩個獨立、解耦的本地元件

比照原專案 `GeminiLiveConnection`（即時串流）與 `GeminiSummaryService`（會後分析）解耦的原則，本地版把 **STT**（連續串流、低延遲要求）與 **翻譯**（陣發性、句子觸發）也拆成兩個獨立元件，各自管理自己的模型生命週期。好處：

- STT 串流不需要等翻譯完成才能顯示原文字幕（可以先顯示原文，翻譯結果非同步補上，與原專案 `didReceiveInputTranscription` / `didReceiveOutputTranscription` 分開回呼的行為一致）。
- 未來若要替換翻譯後端（例如改用 Apple 的翻譯 API 或另一顆模型），不影響 STT 元件。

### 2. 句子邊界觸發翻譯，而非逐字翻譯

沿用原專案 `checkAndRotateSubtitle` 的句尾偵測機制（標點符號 + 0.8 秒 debounce）。這不只是延續既有 UX，也是 feasibility 文件中「陣發性負載」設計的關鍵 — 讓 Gemma 4 的運算集中在句子完成的瞬間，而非持續佔用 GPU。

### 3. `ModelManager` 取代「API Key」作為啟動門檻

原專案的第一步是輸入 Gemini API Key。本地版沒有 API Key，但有等價的「啟動前置需求」：模型是否已下載。`ModelManager` 負責：

- 檢查 WhisperKit / Gemma 4 模型是否已存在於本機（`~/Library/Application Support/MeetingTranslatorLocal/models/`）
- 首次啟動時觸發下載，顯示進度（對應原本 `SecureField` 輸入 API Key 的 UI 位置，改成「下載模型」進度條）
- 提供模型大小選擇（WhisperKit tiny/base/small、Gemma 4 E2B/E4B），對應 feasibility 文件中依機器規格（16GB vs 24GB+）給預設值

### 4. OpenCC 是保險層，不是主要翻譯邏輯

不依賴 Whisper 或 Gemma 4「自己」穩定產出繁體 — 在兩個可能產生中文文字的節點（STT 直接辨識出中文、翻譯引擎輸出中文）之後都各自過一次 OpenCC s2twp 轉換，確保最終顯示與匯出的文字一律是繁體中文台灣慣用語，不受模型行為波動影響。

### 5. 明確排除：即時語音配音（TTS 同聲傳譯播放）

原專案的 `AudioPlaybackManager` 播放 Gemini 回傳的翻譯配音，讓使用者「邊看邊聽」。本地版 v1 不做這塊 — 純文字字幕已滿足「快速 STT + 翻譯字幕」的核心需求，且 TTS 會再引入一顆模型、增加記憶體與延遲預算，優先度低於把 STT+翻譯的核心體驗做穩。若之後要補上，`argmax-oss-swift`（WhisperKit 所在的同一個套件）已內建 `TTSKit`（Qwen3-TTS Core ML），屆時可直接沿用同一套件生態，不需要重新選型。

---

## 新增檔案清單（規劃）

| 檔案 | 職責 |
|---|---|
| `LocalSTTEngine.swift` | 封裝 WhisperKit：串流辨識、partial/final result 回呼、語言偵測 |
| `LocalTranslationEngine.swift` | 封裝 MLX Gemma 4：載入模型、句子翻譯、prompt 組裝（目標語言固定 zh-TW） |
| `LocalSummaryService.swift` | 封裝 Gemma 4 長 context 摘要（取代 `GeminiSummaryService`，介面盡量保持一致：輸入逐字稿、輸出 `MeetingMinutes`） |
| `OpenCCConverter.swift` | 簡體→繁體台灣慣用語轉換（s2twp），提供給 STT 與翻譯結果共用 |
| `ModelManager.swift` | 模型下載、版本管理、載入狀態、儲存路徑 |

不變的檔案：`AudioCaptureManager.swift`、`FloatingSubtitleWindow.swift`、`MeetingMinutesView.swift`、`MeetingNotesEditor.swift`、`NotesPreviewView.swift`、`MarkdownRenderer.swift`（皆可直接複製沿用，介面不需更動）。

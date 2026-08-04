# meeting-translator-local-macos

MeetingTranslator（本地版）— `gemini-live-translate-macos` 的離線重製版本。保留原專案的會議即時翻譯、雙語逐字稿、會議筆記與網頁匯出等使用體驗，但把所有需要雲端 API 的環節（Gemini Live STT/翻譯/配音、Gemini 摘要）換成完全在裝置端執行的模型，資料不出機器。

> 目前狀態：**設計評估階段**，尚未開始實作。詳見 `docs/design/`。

---

## 為什麼要做本地版

原專案 [`gemini-live-translate-macos`](https://github.com/kkdai/gemini-live-translate-macos) 依賴 Gemini 3.5 Live Translate（雲端 WebSocket API），需要 API Key、網路連線，且會議內容會經過 Google 的伺服器。本地版的目標：

1. **隱私**：會議音訊與逐字稿全程留在裝置上，不上傳任何第三方伺服器。
2. **零 API 成本／零金鑰管理**：不需要申請、儲存、輪替 API Key。
3. **離線可用**：沒有網路也能開會、也能翻譯。
4. **硬體目標明確**：以 MacBook（Apple M4）為基準機種評估可行性。

## 核心功能（與原專案對齊）

- 快速本地 STT，即時顯示繁體中文字幕（雙語對照：原文 + 中文翻譯）
- 使用小型本地模型（Gemma 4 的小型變體）處理翻譯
- 懸浮字幕視窗（會議中不需切換視窗）
- 雙語逐字稿自動匯出（Markdown，存到 Desktop）
- 會議筆記編輯器（Markdown + 貼上截圖）與即時預覽
- 會議記錄網頁匯出（AI 摘要 + 使用者筆記 + 雙語逐字稿，單一 HTML 檔）

## 與原專案的差異總覽

| 環節 | 原專案（雲端） | 本地版（規劃） |
|---|---|---|
| 音訊擷取 | ScreenCaptureKit（`AudioCaptureManager.swift`） | 相同，直接沿用 |
| 語音辨識 (STT) | Gemini Live WebSocket `inputTranscription` | WhisperKit（Core ML / ANE，本地） |
| 翻譯 | Gemini Live WebSocket `outputTranscription` | Gemma 4（E2B/E4B，MLX，本地） |
| 語音配音 | Gemini Live 回傳 PCM 音訊 + `AudioPlaybackManager` | **v1 不做**（見 feasibility 文件的排除範圍） |
| 會議摘要 | Gemini `generateContent` REST API | Gemma 4（同一顆本地模型，長 context 摘要） |
| 筆記編輯／預覽／匯出 | 本機邏輯，無雲端依賴 | 相同，直接沿用 |
| 網路需求 | 需要（WebSocket + REST） | 不需要（僅首次下載模型權重時需要） |

## 文件

- [`docs/design/2026-08-04-feasibility.md`](docs/design/2026-08-04-feasibility.md) — STT / 翻譯技術選型評估、硬體資源估算、風險
- [`docs/design/2026-08-04-architecture.md`](docs/design/2026-08-04-architecture.md) — 元件架構、資料流、新增/沿用檔案清單
- [`docs/design/2026-08-04-roadmap.md`](docs/design/2026-08-04-roadmap.md) — 分階段實作計畫

## 授權

規劃比照原專案採用 MIT。

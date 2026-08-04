# Phase 0 Spike 結果：Gemma 4（MLX 翻譯）

日期：2026-08-05
狀態：E2B、E4B 延遲與品質皆已驗證；雙模型併發記憶體峰值待補

測試機器：MacBook Air, Apple M4, 16GB 統一記憶體, macOS 15.7.8, Xcode 16.4（為此新裝，見下方「環境發現」）

---

## 環境發現：MLX Swift 必須用 Xcode 建置，不能只用 `swift build`

這是本次 spike 花最多時間排查的地方，記錄下來避免以後重踩：

1. **需要完整 Xcode，不是只有 Command Line Tools** — MLX 在建置期需要編譯自訂 Metal shader，需要 `xcrun metal`，這個工具只隨完整 Xcode.app 附帶，Command Line Tools 沒有。這點 feasibility 文件已經記錄過。
2. **即使裝了 Xcode，純 `swift build` / `swift run` 還是不行** — 實測純 SPM 建置會成功編譯，但執行時噴錯：
   ```
   MLX error: Failed to load the default metallib. library not found ...
   ```
   原因：MLX 的 Metal shader 編譯與封裝成 `mlx-swift_Cmlx.bundle` 這個步驟，是掛在 Xcode 專案層級的 build phase / xcconfig 設定，**不是**標準 SPM plugin，所以 `swift build` 根本不會觸發這個步驟。官方 `mlx-swift` 的 troubleshooting 文件也證實了這點（"MLX requires metal shaders from the Cmlx framework -- these are not usable from command line tools unless `DYLD_FRAMEWORK_PATH` makes them visible"）。
   - **正確做法**：即使是純命令列工具、沒有 storyboard/App 介面，只要用到 MLX，就必須透過 `xcodebuild` 建置（可以是對著一個 `Package.swift` 直接下 `xcodebuild -scheme <package-name>`，不需要額外建立 `.xcodeproj`——Xcode 16 會自動幫本地 SPM package 產生一個對應套件名稱的 scheme）。
   - 這對正式產品開發是重要提醒：**`LocalTranslationEngine` 這塊程式碼未來一定要放進 Xcode 專案建置流程**，不能假設可以用輕量 CI（純 swift build）建置，CI/CD 需要跑完整 Xcode toolchain。
3. **`@main` 不能放在檔名為 `main.swift` 的檔案裡，用 `xcodebuild` 建置時會報錯**（`swift build` 卻不會報這個錯——SwiftPM 對這個組合有特殊相容處理，但 `xcodebuild` 走嚴格規則）。修法：把檔案改名（例如 `GemmaSpike.swift`），保留 `@main struct GemmaSpike { static func main() async {...} }`。這是純粹的建置系統差異，不是程式邏輯問題，但如果不知道這個規則會卡很久。
4. 遇到的另一個岔路：一開始想直接用官方 `mlx-swift-examples` repo 的 `llm-tool` CLI（現成、有 profiling 功能），但它的 Release build 在 `MLXVLM`（處理圖片/影片輸入的模組）踩到 Swift 6 strict concurrency 的 `CIContext`（非 Sendable）編譯錯誤，且這個模組是給 VLM 用的，我們的翻譯需求完全用不到。最後改成自己寫一個最小的 SPM package，只依賴 `MLXLLM` + `MLXLMCommon` + `MLXHuggingFace`（加上巨集展開需要的 `HuggingFace`、`Tokenizers`），成功繞開整個 VLM 模組，`.build` 過程仍然把 `MLXVLM` 拉進來當 transitive dependency，但透過 `xcodebuild` 建置時沒有再踩到那個 concurrency 錯誤（可能是套件層級 vs 專案層級的 strict concurrency 設定不同）。

---

## 測試方法

- 套件：自建的 `spike/gemma-spike`（`MLXLLM` + `MLXLMCommon` + `MLXHuggingFace`，依賴 `ml-explore/mlx-swift-lm` `3.31.x`）
- 模型：`mlx-community/gemma-4-e2b-it-4bit`（`LLMRegistry.gemma4_e2b_it_4bit`），4-bit 量化
- 情境：單一 `ChatSession`，system instructions 設定為「即時會議口譯，只輸出繁體中文翻譯」，模擬正式產品「一個會議 session 內重複使用同一個 session、只是不斷追加新句子」的設計（見 architecture 文件的句子邊界觸發翻譯機制）
- 依序丟 5 句英文會議常見句子，量測：模型載入時間、每句的**首字延遲**（time to first token）、prompt 處理速度（tokens/s）、生成速度（tokens/s）、整句總時間

---

## 結果：Gemma 4 E2B（4-bit）

模型下載後磁碟大小：**3.3GB**（比 feasibility 文件原本估計的 1.3-1.8GB 大很多，已知需要回頭修正該文件的記憶體/磁碟估算，見文末）。

| 句子 | 首字延遲 | 總時間 | prompt tok/s | 生成 tok/s |
|---|---|---|---|---|
| This feature is really important.（第一句，含 session 冷啟動） | 1.836s | 1.953s | 34.4 | 36.8 |
| Let me show you how the live demo works. | 0.211s | 0.387s | 314.0 | 60.3 |
| We need to finish the report by Friday. | 0.217s | 0.346s | 300.6 | 59.5 |
| Can everyone see my screen right now? | 0.261s | 0.381s | 246.6 | 63.0 |
| I think we should postpone this decision until next week. | 0.226s | 0.425s | 298.4 | 63.0 |

翻譯品質（人工檢查，全部正確且是繁體中文）：
```
This feature is really important.                          → 這個功能非常重要
Let me show you how the live demo works.                    → 讓我向您展示實體演示如何運作
We need to finish the report by Friday.                     → 我們需要在星期五前完成報告
Can everyone see my screen right now?                       → 大家現在能看到我的畫面嗎
I think we should postpone this decision until next week.   → 我認為我們應該將這個決定延期到下週
```

### 觀察

1. **第一句有明顯的冷啟動成本**（1.8s vs 之後的 0.2-0.4s），推測是 MLX 針對這個運算圖形狀第一次做 lazy Metal kernel 編譯／JIT 的一次性成本，而非模型本身推論慢。**設計含意**：正式產品應該在使用者按下「開始翻譯」、選好來源 App 但音訊還沒進來的空檔，就先送一個 dummy 短句「暖機」，把這個一次性成本移到使用者感受不到的地方，而不是讓會議中第一句話的翻譯明顯卡頓。
2. **暖機後單句延遲 0.35-0.43 秒**，這是「首字延遲 + 生成完整句子」的總時間 — 遠低於原專案雲端方案「落後說話者數秒」的水準，是本地方案在這個環節相對雲端的優勢，而不是妥協。
3. 沿用同一個 `ChatSession`（讓 system instructions 的 KV cache 只需要建立一次）是關鍵 — prompt tok/s 從第一句的 34 跳到後面的 250-314，這驗證了 architecture 文件「一個會議 session 維持一個 ChatSession，不要每句話都重新建立」的設計方向是對的。

---

## 結果：Gemma 4 E4B（4-bit）

模型下載後磁碟大小：**4.8GB**。下載耗時計入了 495 秒的「模型載入」時間（首次下載，非推論成本）。

| 句子 | 首字延遲 | 總時間 | prompt tok/s | 生成 tok/s |
|---|---|---|---|---|
| This feature is really important.（第一句，含冷啟動，但比 E2B 的第一句快很多） | 0.660s | 0.820s | 99.9 | 33.8 |
| Let me show you how the live demo works. | 0.410s | 0.777s | 161.5 | 33.8 |
| We need to finish the report by Friday. | 0.414s | 0.665s | 157.3 | 33.6 |
| Can everyone see my screen right now? | 0.380s | 0.669s | 169.0 | 32.9 |
| I think we should postpone this decision until next week. | 0.422s | 0.774s | 159.1 | 32.5 |

翻譯結果（標點更完整，語氣略更自然）：
```
This feature is really important.                          → 這個功能真的很重要。
Let me show you how the live demo works.                    → 讓我們先向您展示這個線上演示如何運作。
We need to finish the report by Friday.                     → 我們需要在星期五前完成報告。
Can everyone see my screen right now?                       → 大家現在都能看到我的螢幕嗎？
I think we should postpone this decision until next week.   → 我想我們應該把這個決定延到下週。
```

## E2B vs E4B 比較

| | E2B (4-bit) | E4B (4-bit) |
|---|---|---|
| 磁碟大小 | 3.3GB | 4.8GB |
| 首句冷啟動延遲 | 1.836s | 0.660s（意外地更短，見下方分析） |
| 暖機後單句總延遲 | 0.35-0.43s | 0.67-0.82s |
| 生成速度 | ~60-63 tok/s | ~33-34 tok/s |
| 翻譯品質 | 正確、簡潔 | 正確、標點與語氣略更完整自然 |

**E2B 的第一句冷啟動反而比 E4B 慢**，推測與兩次測試各自的 Metal shader 快取狀態有關（E4B 是這次 spike session 裡第二個載入的 Gemma 模型，某些共用的 kernel 可能已經被前一次 E2B 執行「預熱」過，需要更嚴謹的 A/B 測試才能確認，不是本次 spike 的優先項）。**扣掉冷啟動後，E2B 的單句延遲是 E4B 的一半左右**（0.35-0.43s vs 0.67-0.82s），符合參數量差距的預期。

兩者的翻譯品質差異在這 5 句簡單會議句子上並不顯著，都正確且通順；E4B 標點與語氣略勝一籌，但差距不足以在「快速字幕」這個場景下犧牲兩倍延遲。**初步建議 v1 預設用 E2B**，E4B 留給硬體較寬裕（24GB+）或使用者主動要求更高翻譯品質時的選項 — 這與 feasibility 文件原本的方向一致，這次是用實測數字而非猜測確認。

---

## 待補：雙模型併發記憶體峰值

- [ ] WhisperKit（`small`）與 Gemma 4（E2B）同時載入時的記憶體峰值，驗證 16GB 機型是否真的夠用
- [ ] 中英夾雜句子的翻譯品質（目前測試只用純英文句子）

---

## 需要回頭修正 feasibility 文件的地方

- Gemma 4 磁碟佔用實測：**E2B 3.3GB、E4B 4.8GB**，遠高於原本估計的 1.3-1.8GB / 2.5-3GB。需要更新「硬體資源估算」表格。
- 記憶體估算表格是用磁碟大小類推的粗略猜測，需要補上 Phase 0 實測的常駐記憶體數字（尚待測，見上方待補項）。
- 首句冷啟動成本（尤其 E2B 的 1.8 秒）是需要在正式產品用「暖機」機制解決的已知問題，不是模型推論效能的真實上限。

# 翻譯延遲測試用句子

比照原專案會議情境，每句都是「句尾觸發翻譯」模式下的單一句子長度（10-25 字英文），
用來量測 Gemma 4 單句翻譯的首字延遲與 tokens/sec。

1. This feature is really important.
2. Let me show you how the live demo works.
3. We need to finish the report by Friday.
4. Can everyone see my screen right now?
5. I think we should postpone this decision until next week.

Prompt 模板（比照原專案 GeminiSummaryService 的角色設定精神，但改成即時單句翻譯）：

```
You are a real-time meeting interpreter. Translate the following sentence into
Traditional Chinese (Taiwan usage, zh-TW). Output ONLY the translation, no
explanation, no pinyin, no quotes.

Sentence: {english_sentence}
```

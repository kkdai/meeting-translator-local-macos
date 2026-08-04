import Foundation
import HuggingFace
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

@main
struct GemmaSpike {
    static func main() async {
        let args = CommandLine.arguments
        let modelArg = args.count > 1 ? args[1] : "e4b"
        let configuration =
            modelArg == "e2b" ? LLMRegistry.gemma4_e2b_it_4bit : LLMRegistry.gemma4_e4b_it_4bit

        print("=== Gemma 4 Translation Spike ===")
        print("model: \(modelArg) (\(configuration.name))")

        let loadStart = Date()
        let model: ModelContainer
        do {
            model = try await #huggingFaceLoadModelContainer(configuration: configuration) {
                progress in
                FileHandle.standardError.write(
                    "download: \(Int(progress.fractionCompleted * 100))%\r".data(using: .utf8)!)
            }
        } catch {
            print("❌ failed to load model: \(error)")
            return
        }
        print("✅ model loaded in \(String(format: "%.3f", Date().timeIntervalSince(loadStart)))s")

        let instructions = """
            You are a real-time meeting interpreter. Translate the sentence the user \
            gives you into Traditional Chinese (Taiwan usage, zh-TW). Output ONLY the \
            translation, no explanation, no pinyin, no quotes.
            """

        let session = ChatSession(model, instructions: instructions)

        let sentences = [
            "This feature is really important.",
            "Let me show you how the live demo works.",
            "We need to finish the report by Friday.",
            "Can everyone see my screen right now?",
            "I think we should postpone this decision until next week.",
        ]

        for sentence in sentences {
            let start = Date()
            var firstTokenTime: TimeInterval?
            var output = ""
            var info: GenerateCompletionInfo?

            do {
                for try await item in session.streamDetails(to: sentence) {
                    switch item {
                    case .chunk(let text):
                        if firstTokenTime == nil {
                            firstTokenTime = Date().timeIntervalSince(start)
                        }
                        output += text
                    case .info(let completionInfo):
                        info = completionInfo
                    case .toolCall:
                        break
                    }
                }
            } catch {
                print("❌ generation failed: \(error)")
                continue
            }

            let totalTime = Date().timeIntervalSince(start)
            print("---")
            print("EN: \(sentence)")
            print("ZH: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
            print(
                "first token: \(String(format: "%.3f", firstTokenTime ?? -1))s, total: \(String(format: "%.3f", totalTime))s"
            )
            if let info {
                print(info.summary())
            }
        }
        print("=== done ===")
    }
}

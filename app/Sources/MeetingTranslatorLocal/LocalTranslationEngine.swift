import Foundation
import HuggingFace
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

protocol LocalTranslationDelegate: AnyObject {
    func didUpdateTranslationStatus(_ status: String)
}

/// Wraps a single Gemma 4 `ChatSession` for the whole meeting.
///
/// Phase 0's spike (docs/design/2026-08-05-phase0-spike-results-translation.md)
/// found reusing one session across sentences -- rather than a fresh session per
/// sentence -- matters: the system-instructions KV cache only pays its prefill
/// cost once, taking prompt processing from ~34 tok/s to ~250-300 tok/s for every
/// sentence after the first. It also found a real first-call cost dominated by a
/// one-time Metal kernel JIT, not steady-state inference, so `start()` sends a
/// throwaway warm-up sentence before signalling ready.
actor LocalTranslationEngine {
    weak var delegate: LocalTranslationDelegate?

    private var session: ChatSession?

    private let instructions = """
        You are a real-time meeting interpreter. Translate the sentence the user \
        gives you into Traditional Chinese (Taiwan usage, zh-TW). Output ONLY the \
        translation, no explanation, no pinyin, no quotes.
        """

    func setDelegate(_ delegate: LocalTranslationDelegate) {
        self.delegate = delegate
    }

    /// - Parameter modelSize: "e2b" (default, ~2x faster) or "e4b" (higher quality).
    func start(modelSize: String) async {
        await notifyStatus("正在載入翻譯模型...")
        let configuration = modelSize == "e4b" ? LLMRegistry.gemma4_e4b_it_4bit : LLMRegistry.gemma4_e2b_it_4bit

        do {
            let model = try await #huggingFaceLoadModelContainer(configuration: configuration)
            let newSession = ChatSession(model, instructions: instructions)
            // Absorb the first-call Metal JIT cost now instead of on the meeting's first real sentence.
            _ = try? await newSession.respond(to: "Hello.")
            session = newSession
            await notifyStatus("翻譯模型已就緒")
        } catch {
            session = nil
            await notifyStatus("翻譯模型載入失敗：\(error.localizedDescription)")
        }
    }

    func stop() {
        session = nil
    }

    func translate(_ text: String) async -> String? {
        guard let session else { return nil }
        return try? await session.respond(to: text)
    }

    private func notifyStatus(_ status: String) async {
        let delegate = self.delegate
        await MainActor.run {
            delegate?.didUpdateTranslationStatus(status)
        }
    }
}

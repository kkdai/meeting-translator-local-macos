import Foundation
import WhisperKit

protocol LocalSTTDelegate: AnyObject {
    /// A finished chunk of transcribed original-language text.
    func didTranscribeSegment(_ text: String)
    func didUpdateSTTStatus(_ status: String)
}

/// Wraps WhisperKit for near-real-time transcription of ScreenCaptureKit audio.
///
/// WhisperKit's `AudioStreamTranscriber` is built around tapping the microphone
/// (`AudioProcessing.startRecordingLive`), which doesn't fit app audio delivered
/// via `AudioCaptureManager`'s ScreenCaptureKit callback. Instead this buffers
/// incoming PCM into fixed-length chunks and transcribes each chunk as it fills,
/// which is simpler and works with any audio source but can clip words that
/// land on a chunk boundary -- a known Phase 1 limitation, not a bug.
actor LocalSTTEngine {
    weak var delegate: LocalSTTDelegate?

    private var whisperKit: WhisperKit?
    private var sampleBuffer: [Float] = []
    private var language: String?
    private var isFlushing = false

    private let sampleRate: Double = 16000
    private let chunkDuration: Double = 3.0

    private var chunkSampleCount: Int { Int(sampleRate * chunkDuration) }

    func setDelegate(_ delegate: LocalSTTDelegate) {
        self.delegate = delegate
    }

    func start(modelName: String, language: String?) async {
        self.language = language
        sampleBuffer.removeAll()
        await notifyStatus("正在載入 \(modelName) 模型...")
        do {
            let config = WhisperKitConfig(model: modelName)
            whisperKit = try await WhisperKit(config)
            await notifyStatus("模型已就緒")
        } catch {
            whisperKit = nil
            await notifyStatus("模型載入失敗：\(error.localizedDescription)")
        }
    }

    func stop() {
        whisperKit = nil
        sampleBuffer.removeAll()
    }

    /// Appends 16kHz mono Int16 PCM data (as delivered by `AudioCaptureManager`).
    nonisolated func append(pcm16Data: Data) {
        Task { await self.appendSamples(pcm16Data) }
    }

    private func appendSamples(_ data: Data) async {
        guard whisperKit != nil else { return }

        let floats: [Float] = data.withUnsafeBytes { rawBuffer in
            let int16Buffer = rawBuffer.bindMemory(to: Int16.self)
            return int16Buffer.map { Float($0) / Float(Int16.max) }
        }
        sampleBuffer.append(contentsOf: floats)

        if sampleBuffer.count >= chunkSampleCount, !isFlushing {
            await flush()
        }
    }

    private func flush() async {
        guard !isFlushing, let whisperKit else { return }
        isFlushing = true
        defer { isFlushing = false }

        let chunk = sampleBuffer
        sampleBuffer.removeAll()

        let options = DecodingOptions(task: .transcribe, language: language)
        let results = await whisperKit.transcribe(audioArrays: [chunk], decodeOptions: options)
        guard let text = results.first.flatMap({ $0 })?.first?.text else { return }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let delegate = self.delegate
        await MainActor.run {
            delegate?.didTranscribeSegment(trimmed)
        }
    }

    private func notifyStatus(_ status: String) async {
        let delegate = self.delegate
        await MainActor.run {
            delegate?.didUpdateSTTStatus(status)
        }
    }
}

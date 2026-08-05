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
/// incoming PCM and flushes it for transcription as soon as it detects a pause
/// in speech (VAD-based chunking, reusing WhisperKit's own `EnergyVAD` rather
/// than depending on `AudioStreamTranscriber`'s mic-tap plumbing) -- Phase 1
/// originally used fixed 3-second chunks, but that clipped words at arbitrary
/// boundaries badly enough in real use (2026-08-05 user testing) to fix before
/// starting Phase 2 translation work.
actor LocalSTTEngine {
    weak var delegate: LocalSTTDelegate?

    private var whisperKit: WhisperKit?
    private var sampleBuffer: [Float] = []
    private var language: String?
    private var isFlushing = false

    private let sampleRate: Double = 16000

    /// Don't flush on a pause this early -- avoids emitting one-word fragments
    /// on every short gap between filler words.
    private let minChunkDuration: Double = 0.8
    /// Force a flush even without a detected pause, so one long unbroken
    /// sentence (or a VAD miss) can't stall the subtitle indefinitely.
    private let maxChunkDuration: Double = 8.0
    /// How much trailing silence counts as "a pause worth cutting on".
    private let trailingSilenceDuration: Double = 0.35

    private let vad = EnergyVAD(frameLength: 0.1)

    private var minChunkSamples: Int { Int(sampleRate * minChunkDuration) }
    private var maxChunkSamples: Int { Int(sampleRate * maxChunkDuration) }
    private var trailingSilenceSamples: Int { Int(sampleRate * trailingSilenceDuration) }

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

        guard !isFlushing, sampleBuffer.count >= minChunkSamples else { return }

        if sampleBuffer.count >= maxChunkSamples {
            await flush()
        } else if isTrailingSilence() {
            await flush()
        }
    }

    /// Whether the most recent `trailingSilenceDuration` of buffered audio is silent,
    /// i.e. the speaker just paused and this is a natural place to cut the chunk.
    private func isTrailingSilence() -> Bool {
        guard sampleBuffer.count >= trailingSilenceSamples else { return false }
        let tail = Array(sampleBuffer.suffix(trailingSilenceSamples))
        return !vad.voiceActivity(in: tail).contains(true)
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

import Foundation
import WhisperKit

struct Timer2 {
    let label: String
    let start = Date()
    func lap() -> String { String(format: "%.3fs", Date().timeIntervalSince(start)) }
}

func run() async {
    let args = CommandLine.arguments
    let modelName = args.count > 1 ? args[1] : "base"
    let audioPath = args.count > 2 ? args[2] : "audio-samples/english.wav"
    let language = args.count > 3 ? args[3] : nil

    print("=== WhisperKit Spike ===")
    print("model: \(modelName)")
    print("audio: \(audioPath)")
    print("language: \(language ?? "auto-detect")")

    let loadTimer = Timer2(label: "load")
    let config = WhisperKitConfig(model: modelName)
    guard let pipe = try? await WhisperKit(config) else {
        print("❌ failed to init WhisperKit")
        return
    }
    print("✅ model loaded in \(loadTimer.lap())")

    let decodeOptions = DecodingOptions(task: .transcribe, language: language)

    // Warm-up run (excludes first-call compile/allocation overhead from the timed measurement)
    _ = try? await pipe.transcribe(audioPath: audioPath, decodeOptions: decodeOptions)

    let runs = 3
    var durations: [TimeInterval] = []
    var lastText = ""
    for i in 1...runs {
        let t = Timer2(label: "transcribe-\(i)")
        let result = try? await pipe.transcribe(audioPath: audioPath, decodeOptions: decodeOptions)
        let elapsed = Date().timeIntervalSince(t.start)
        durations.append(elapsed)
        lastText = result?.first?.text ?? "(nil)"
        print("run \(i): \(String(format: "%.3f", elapsed))s")
    }

    let avg = durations.reduce(0, +) / Double(durations.count)
    print("---")
    print("avg transcribe time: \(String(format: "%.3f", avg))s over \(runs) runs")
    print("transcript: \(lastText)")
    print("=== done ===")
}

await run()

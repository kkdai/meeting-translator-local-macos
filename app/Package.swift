// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "MeetingTranslatorLocal",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "1.0.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", from: "3.31.0"),
        .package(url: "https://github.com/huggingface/swift-huggingface.git", from: "0.1.0"),
        .package(url: "https://github.com/huggingface/swift-transformers.git", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "MeetingTranslatorLocal",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ],
            // WhisperKit predates Swift 6 strict concurrency (its types aren't
            // Sendable), which the Swift 6 language mode this tools-version
            // implies would otherwise reject at actor-isolation boundaries in
            // LocalSTTEngine. Our own actor boundaries are already deliberate
            // (see LocalSTTEngine/LocalTranslationEngine's delegate hops via
            // MainActor.run), so opting this target back to Swift 5 mode is a
            // narrower fix than fighting Sendable conformance in a dependency
            // we don't own.
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)

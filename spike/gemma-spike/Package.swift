// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "gemma-spike",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", from: "3.31.0"),
        .package(url: "https://github.com/huggingface/swift-huggingface.git", from: "0.1.0"),
        .package(url: "https://github.com/huggingface/swift-transformers.git", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "GemmaSpike",
            dependencies: [
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ]
        ),
    ]
)

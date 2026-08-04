// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MeetingTranslatorLocal",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "MeetingTranslatorLocal",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
            ]
        )
    ]
)

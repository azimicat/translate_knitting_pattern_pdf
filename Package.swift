// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "KnittingTranslator",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "KnittingTranslator",
            path: "Sources/KnittingTranslator",
            resources: [.process("Resources")],
            // -parse-as-library は SPM executable target で @main を使うために必要
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        ),
        .testTarget(
            name: "KnittingTranslatorTests",
            dependencies: ["KnittingTranslator"],
            path: "Tests/KnittingTranslatorTests"
        ),
    ]
)

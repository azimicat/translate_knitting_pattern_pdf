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
            swiftSettings: [
                // Required for @main to work in SPM executable targets
                .unsafeFlags(["-parse-as-library"])
            ]
        )
    ]
)

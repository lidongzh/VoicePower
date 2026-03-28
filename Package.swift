// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "voice_power",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "VoicePower", targets: ["VoicePower"])
    ],
    targets: [
        .executableTarget(
            name: "VoicePower",
            path: "Sources/VoicePower"
        )
    ]
)

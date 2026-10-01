// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VoiceText",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "VoiceText", targets: ["VoiceTextApp"]),
        .executable(name: "vt-bench", targets: ["vt-bench"]),
    ],
    dependencies: [
        // Apache-2.0. ASR only: opt out of the NeMo text-normalization binary (TTS/ITN).
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.17.4", traits: []),
    ],
    targets: [
        .target(
            name: "VoiceTextCore",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")],
            resources: [.copy("Resources/PromptProfiles")]
        ),
        .executableTarget(
            name: "VoiceTextApp",
            dependencies: ["VoiceTextCore"]
        ),
        .executableTarget(
            name: "vt-bench",
            dependencies: ["VoiceTextCore"]
        ),
        .testTarget(
            name: "VoiceTextCoreTests",
            dependencies: ["VoiceTextCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)

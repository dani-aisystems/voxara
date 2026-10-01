// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Voxara",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Voxara", targets: ["VoxaraApp"]),
        .executable(name: "vx-bench", targets: ["vx-bench"]),
    ],
    dependencies: [
        // Apache-2.0. ASR only: opt out of the NeMo text-normalization binary (TTS/ITN).
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.17.4", traits: []),
    ],
    targets: [
        .target(
            name: "VoxaraCore",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")],
            resources: [.copy("Resources/PromptProfiles")]
        ),
        .executableTarget(
            name: "VoxaraApp",
            dependencies: ["VoxaraCore"]
        ),
        .executableTarget(
            name: "vx-bench",
            dependencies: ["VoxaraCore"]
        ),
        .testTarget(
            name: "VoxaraCoreTests",
            dependencies: ["VoxaraCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)

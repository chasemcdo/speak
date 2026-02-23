// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Speak",
    platforms: [
        .macOS(.v26)
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "Speak",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Speak",
            resources: [
                .process("Assets.xcassets")
            ],
            swiftSettings: [
                .define("SPEAK_APP")
            ],
            linkerSettings: [
                .linkedFramework("Speech"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("FoundationModels"),
            ]
        )
    ]
)

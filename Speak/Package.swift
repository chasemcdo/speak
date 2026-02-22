// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Speak",
    platforms: [
        .macOS(.v26)
    ],
    targets: [
        .executableTarget(
            name: "Speak",
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

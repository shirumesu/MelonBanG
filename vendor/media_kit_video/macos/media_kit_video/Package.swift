// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "media_kit_video",
    platforms: [.macOS("10.15")],
    products: [
        .library(name: "media-kit-video", targets: ["media_kit_video"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        .package(name: "media_kit_libs_macos_video", path: "../media_kit_libs_macos_video")
    ],
    targets: [
        .target(
            name: "media_kit_video",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "Mpv", package: "media_kit_libs_macos_video")
            ],
            exclude: ["stub"],
            sources: ["plugin"],
            resources: [.process("PrivacyInfo.xcprivacy")],
            swiftSettings: [
                .unsafeFlags([
                    "-Xcc", "-DGL_SILENCE_DEPRECATION",
                    "-Xcc", "-DCOREVIDEO_SILENCE_GL_DEPRECATION"
                ])
            ]
        )
    ]
)

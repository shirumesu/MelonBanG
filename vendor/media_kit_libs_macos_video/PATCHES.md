# Local native patches

Upstream: media-kit/media-kit at `c533e446755f51cf53c7e57aea873f2aa5355f81`,
macOS native libraries package 1.1.5 with Swift Package Manager support.
MIT license (see LICENSE).
The example application and test-only development dependencies are omitted.

The package uses the upstream libmpv v0.7.2 release's individual XCFramework
archives and SHA-256 checksums. Swift Package Manager links and embeds all
18 native frameworks, including Mpv, FFmpeg, libass, and their dependencies.
The CocoaPods integration uses the same upstream release.

The release retains mpv 0.36.0, FFmpeg 6.0, and VideoToolbox hardware decoding.
Its arm64 Mpv binary declares macOS 11.0 as its minimum deployment version.

Both the plugin and library target explicitly depend on Flutter's generated
`FlutterFramework` package, as required by current Flutter templates. The
Swift package minimum is macOS 10.15 to match Flutter's package integration.
The Dart package is removed from the upstream pub workspace so it can be used
as a local dependency override.

SwiftPM copies the macOS universal framework slice without removing unused CPU
architectures. The Runner's final `Thin Native Frameworks` phase keeps the
requested architecture for single-architecture builds and re-signs each changed
framework before Xcode signs the app. `macos/Runner/FrameworkSignatures.xcfilelist`
orders this phase after SwiftPM's framework signing; keep that list aligned with
the binary targets here when upgrading the native release.

# Melonbang

A Windows and macOS anime client built with Dart, Flutter, and media_kit.

## Run and build

### Windows

Install Flutter stable (Dart 3.13.2+) and Visual Studio's C++ desktop build tools
with a Windows SDK. The current build targets Windows x64.
From this repository root:

```powershell
flutter pub get
flutter run -d windows
flutter build windows --release
```

The executable is `build/windows/x64/runner/Release/melonbang.exe`. Keep the whole
Release directory together. `scripts/build.ps1 -Archive` also produces a portable
ZIP; set `FLUTTER_ROOT` if Flutter is not on PATH. Node.js, pnpm, and Electron are
not build or runtime requirements. The first build downloads media_kit binaries and
builds the patched torrent engine through a pinned vcpkg toolchain; this can take
several minutes. Later builds reuse the native dependency cache.

### macOS

The current native dependency build targets Apple Silicon Macs on macOS 26 or later.
Install the full Xcode app from the Mac App Store, open it once to complete its
setup, and select its command-line tools. A paid Apple Developer membership is
not needed for local builds; the runner uses ad-hoc signing with no team.

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
brew install --cask flutter
brew install cocoapods cmake ninja libtorrent-rasterbar
flutter doctor -v
flutter pub get
flutter run -d macos
```

Alternatively, set `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
in your shell profile to select Xcode for your user without changing the system
command-line tools selection.

Flutter includes Dart; a separate Dart installation is unnecessary. CocoaPods
builds the patched torrent bridge using Homebrew's libtorrent 2.1 and embeds its
native dependencies in the app. Flutter's project configuration selects arm64 for
release/profile builds; this setup does not produce a universal binary.

`flutter build macos --release` creates
`build/macos/Build/Products/Release/melonbang.app`. Local builds are desktop apps
without App Sandbox so downloaded and previously selected media remain accessible
across restarts. App Store distribution and notarization require separate signing
and packaging setup.

## Project layout

- `lib/`: application entry, service composition, navigation and lifecycle.
- `lib/ui/`: Flutter views grouped by discovery, tracking, acquisition, settings,
  and player. `ui/core/` holds shared page widgets, posters, theme and shell chrome.
- `lib/data/`: in-process repositories, provider clients, and persistence.
- `test/`: data, OAuth, playback and isolated page interaction tests.
- `integration_test/`: desktop application, native playback, and torrent tests.
- `windows/`: Flutter runner and the pinned native dependency build.
- `macos/`: Flutter runner, local signing, and Keychain integration.
- `vendor/`: patched upstream plugins; each patch is documented in `PATCHES.md`.
- `scripts/`: release packaging and packaged application verification.

Generated build output belongs in `build/` and portable releases in `dist/`.
Local experiments and historical worktrees belong in ignored `temp/`; they are
not required to build or run the app. The vendored plugins are explicit path
dependencies, so all builds use the same checked-in patches.

Pages receive data and action callbacks; `app.dart` connects them to repositories
and owns navigation, asynchronous request identity, and application shutdown.
The player separates the video scene and keyboard/drag lifecycle (`player_page`),
transport controls (`player_controls`), side-panel interactions (`player_settings`),
and the media session (`playback`). Hiding the side panel or entering fullscreen
preserves its selected tab and unfinished input. Connection settings own their
form state and credential load/save lifecycle.

Split code when it has an independent responsibility or a reusable widget boundary.
Small related views and their private widgets can share a file; cohesive repositories
stay together. This follows Flutter's
[architecture recommendations](https://docs.flutter.dev/app-architecture/recommendations)
without requiring an additional state-management framework. Keep `test/` and
`integration_test/` separate: Flutter uses the latter path to select device testing.

## Application

- Discover, search, browse the release calendar, and inspect anime and episodes.
- Keep local collections and chapter states without an account. Bangumi login
  enables account-scoped synchronization, with a durable queue for offline edits.
- Search RSS resources, import magnets or torrent files, pause and resume native
  downloads, and play completed episodes. Closing the app preserves downloaded data.
  Multi-video torrents require selecting a file in the cache list; individual files
  are not automatically assigned to the chapter used to find the collection.
- Play original video files through media_kit: native ASS subtitles, audio and
  subtitle selection, external subtitles, subtitle delay, seeks, resume, fullscreen,
  and keyboard controls. Video, controls, and danmaku share one Flutter scene.
- Match danmaku through Dandanplay, Bilibili, or Bahamut, select matches manually,
  toggle individual sources, and import local comment JSON.

Application services run in the Flutter process. `lib/data` contains Dart HTTP
clients, SQLite repositories, OAuth callbacks, operating-system credential storage,
RSS and danmaku parsers, and the libtorrent download adapter. UI calls these Dart
objects directly; no subprocess, IPC dispatcher, legacy component, or transcode
pipeline is involved. Native libraries and their licenses are listed in
[THIRD_PARTY.md](THIRD_PARTY.md).

Backend ownership, persistence guarantees, and verification boundaries are documented
in [Backend contracts](docs/backend.md).

## Data and connections

The app uses a fresh `native` directory under the operating system's application
support directory. Its path is shown in Settings. `MELONBANG_DATA_DIR` can select
another directory. Earlier runtime databases are not opened or migrated.

Settings → Downloads and seeding controls the persistent BitTorrent policy.
Defaults: at most 3 downloads and 2 seeders, unlimited download speed, 1024 KiB/s
aggregate upload speed, 50 peers per task (200 globally), automatic listen port,
DHT/IPv6/automatic port mapping enabled, and negotiated encryption. Completed
jobs seed until either uploaded bytes reach the content size (ratio 1.0) or
active seeding time reaches 60 minutes. Users can instead stop at completion or
seed indefinitely. Downloading still uploads pieces in all three modes.

The cache list distinguishes checking, queued, downloading, seeding, manually
paused, and completed/stopped tasks, and shows upload speed and sharing totals.
Settings apply to existing jobs; manually paused jobs stay paused. Startup resumes
eligible work by default and can be configured to leave all jobs paused. Seeding
only runs while the app runs. Sharing counters survive restart; older versions
have no historical sharing counters to migrate. Magnet metadata is cached for
offline recovery, and restored local files are checked before playback/transfer.
Task changes are saved immediately and transfer counters every five seconds and
on orderly shutdown. Force-quitting can lose the most recent counter interval.
Completed tasks have a Stop Seeding action that preserves downloaded files and
persists independently of global sharing limits. File sizes and individual progress
come from native verified pieces; idle seeding still counts toward the time limit. Explicit Resume clears this stop
and returns the task to the configured queue and limits. File summaries appear
below the task title; View Files opens the full list and per-file playback.

Settings provides fields for Bangumi OAuth Client ID, Client Secret, callback
address (default `http://127.0.0.1:14567/callback`), and Dandanplay App ID/Secret.
Credentials and tokens use the current Windows user's DPAPI key or the macOS login
Keychain. Credential profiles are isolated by the application data directory.
Startup attempts account recovery without a system password dialog. If Keychain
access requires authorization, use Unlock Sync to restore the saved account and
its OAuth configuration in one interaction. A cached public account profile keeps
local collections available while credentials are locked; tokens stay in native
storage. Synchronization failures do not hide a successfully restored login.
Opening Settings does not read service secrets: each service has its own Edit and
Save actions. Successful credential reads are cached in memory for the process,
and failed reads can be retried. Writes update the cache only after storage succeeds.
Windows uses DPAPI with UI forbidden and does not require a Keychain equivalent.
macOS uses a scoped SecKeychain interaction switch because the existing login
Keychain is file-based; SecItem authentication-context flags do not suppress its
access-control dialogs. Ad-hoc rebuilds may still require fresh authorization
when a credential is explicitly used. Self-signed builds can also need renewed
Keychain authorization; Apple-issued development signing is recommended for
credential continuity across builds. See
[macOS signing and account recovery](docs/macos-signing.md) for setup, migration,
and distribution details. No plaintext account-credential fallback is used.
No configuration secrets are bundled into the executable or stored in Git.

Public anime data comes from Melon API; personal writes go to Bangumi. Account
queues are isolated by user ID. Guest collections remain local and are not
silently uploaded when signing in. Download tasks and episode/file associations
are persisted in the Dart-owned SQLite database.
Bangumi requires collecting a subject before its chapter states can synchronize.
Rejected chapter edits remain queued for retry without blocking other subjects.
Local chapter states remain usable independently of subject collection.

Danmaku JSON is an array of objects containing `timeSeconds`, `text`, `mode`
(`scroll`, `top`, `bottom`), and optional `color` (`#rrggbb`). Provider availability
and title matching can vary; a provider failure is displayed without stopping video.

## Verify

```powershell
flutter analyze
flutter test
flutter test integration_test/app_test.dart -d windows
flutter test integration_test/torrent_test.dart -d windows
flutter test integration_test/bittorrent_settings_test.dart -d windows
flutter test integration_test/native_player_test.dart -d windows --dart-define=TEST_MEDIA=<absolute-video-path>
flutter test integration_test/navigation_test.dart -d windows --dart-define=TEST_MEDIA=<absolute-video-path>
./scripts/verify-window.ps1
./scripts/verify-window.ps1 -Media <absolute-video-path>
```

On macOS, run the same analyze/unit-test commands and use `-d macos` for the
integration tests. Also run
`flutter test integration_test/credentials_test.dart -d macos` to verify real
Keychain persistence, profile isolation, replacement, and deletion.
Run the macOS integration files as separate `flutter test` commands. With Flutter
3.47.2 on macOS 26, a single directory-wide invocation can fail to launch later
test binaries even though each file passes independently.

The player integration test expects a video longer than 15 seconds with two audio
tracks and embedded subtitles. Optional `TEST_CAPTURE` saves only the Flutter
surface as a PNG. Playback verification is muted. The torrent integration test
creates its own tracker, seeder, and generated fixture, verifies transferred
pieces, checks offline restart and pause/resume, and rejects a deliberately damaged
piece while reusing the valid pieces. Tests use
temporary databases and do not access personal account state.
The navigation test checks delayed searches, navigation during collection edits,
concurrent video selections, and subtitle state across page changes using mock APIs.
It also checks player settings survive panel collapse and fullscreen. Page widget
tests cover collection filtering and subject/chapter/download action identity.

Actual account synchronization and third-party provider availability should be
validated with configured accounts and representative media. Mixed-DPI monitors,
HDR, and every subtitle/codec combination are not covered by these tests.

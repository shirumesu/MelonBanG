# Melonbang

A Windows anime client built with Dart, Flutter, and media_kit.

## Run and build

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

## Project layout

- `lib/`: application entry, service composition, navigation and lifecycle.
- `lib/ui/`: Flutter views grouped by discovery, tracking, acquisition, settings,
  and player. `ui/core/` holds shared page widgets, posters, theme and shell chrome.
- `lib/data/`: in-process repositories, provider clients, and persistence.
- `test/`: data, OAuth, playback and isolated page interaction tests.
- `integration_test/`: Windows application, native playback, and torrent tests.
- `windows/`: Flutter runner and the pinned native dependency build.
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
clients, SQLite repositories, OAuth callbacks, Windows DPAPI credential storage,
RSS and danmaku parsers, and the libtorrent download adapter. UI calls these Dart
objects directly; no subprocess, IPC dispatcher, legacy component, or transcode
pipeline is involved. Native libraries and their licenses are listed in
[THIRD_PARTY.md](THIRD_PARTY.md).

## Data and connections

The app uses a fresh `native` directory under the operating system's application
support directory. Its path is shown in Settings. `MELONBANG_DATA_DIR` can select
another directory. Earlier runtime databases are not opened or migrated.

Settings provides fields for Bangumi OAuth Client ID, Client Secret, callback
address (default `http://127.0.0.1:14567/callback`), and Dandanplay App ID/Secret.
Credentials and tokens are encrypted with the current Windows user's DPAPI key.
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
flutter test integration_test/native_player_test.dart -d windows --dart-define=TEST_MEDIA=<absolute-video-path>
flutter test integration_test/navigation_test.dart -d windows --dart-define=TEST_MEDIA=<absolute-video-path>
./scripts/verify-window.ps1
./scripts/verify-window.ps1 -Media <absolute-video-path>
```

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

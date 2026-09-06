# Melonbang

A Windows anime client with a Flutter interface and native media playback.

## Run

Install Flutter stable, Node.js 24+, pnpm, and the Visual Studio C++ desktop build tools.
Make `flutter` available on PATH, or set `FLUTTER_ROOT` to the SDK directory.

```powershell
pnpm install
pnpm dev
```

Build a portable Windows application:

```powershell
pnpm build
```

Run `desktop/build/windows/x64/runner/Release/melonbang.exe`. Keep the entire
Release directory together: Flutter plugins, libmpv, and the `service` directory
are runtime dependencies. A video path can be passed as the first argument.

## Architecture

- `desktop/lib`: Dart/Flutter pages, window management, playback controls, and
  danmaku drawing. `media_kit` renders the original video into a Flutter texture.
  Video, controls, and danmaku share the Flutter scene; there is no floating
  native video window to reposition. `PlayerConfiguration(libass: true)` keeps
  styled ASS subtitles and embedded fonts in the native playback engine.
  A local Windows disposal patch is documented in
  `desktop/vendor/media_kit_video/PATCHES.md`.
- `src/native`: a private stdio request/reply service hosted by bundled Node.js.
  It reuses the existing account, SQLite, RSS, torrent, and danmaku services.
  This is a Flutter UI/playback migration, not a complete Dart backend rewrite.
  The native build aliases the small platform boundary and does not load Electron.
- The native media handoff returns the original file URI. Codec probing, HLS
  preparation, and subtitle extraction are bypassed; media_kit owns duration,
  seek, audio, and subtitle selection. FFmpeg remains available for thumbnails.
- Legacy React/Electron source is retained for comparison and existing business
  regression tests. `pnpm legacy:dev` runs that implementation explicitly.

The application includes discovery, search, calendar, subject details, collection
and episode tracking, RSS acquisition, torrent tasks, local playback, track
selection, resume, fullscreen, and provider/local JSON danmaku.

## Local configuration and data

Runtime data defaults to the application's OS support directory, independent of
the executable location. `MELONBANG_DATA_DIR` selects another data directory.
The native trial uses its own data by default; existing Electron data is not
automatically moved or modified. Back up any existing database before explicitly
pointing a different runtime at it, and do not open the same data directory in
both applications concurrently.

Bangumi OAuth uses `BANGUMI_CLIENT_ID`, `BANGUMI_CLIENT_SECRET`, and optional
`BANGUMI_REDIRECT_URI` (default `http://127.0.0.1:14567/callback`). Alternatively,
put `bangumi-oauth.json` with `clientId`, `clientSecret`, and `redirectUri` under
`temp/` within `MELONBANG_CONFIG_DIR`. The dev command defaults that configuration
root to the repository; the packaged application defaults to its support directory.
Token storage uses Windows DPAPI. Credentials are never included in builds.

The Dandanplay provider uses `DANDANPLAY_APP_ID` and `DANDANPLAY_APP_SECRET`, or
`temp/dandanplay.json` with `appId` and `appSecret` under the same configuration root.
Bilibili and Bahamut can be selected separately in the player. Provider failure
does not stop playback. Local danmaku JSON is an array of objects with
`timeSeconds`, `text`, optional `mode` (`scroll`, `top`, `bottom`) and `color`.

## Verify

```powershell
pnpm test
pnpm exec tsc -p tsconfig.native.json
pnpm native:service
node scripts/verify-service.mjs
cd desktop
flutter analyze
flutter test
```

The Windows integration test uses a generated silent HEVC 10-bit sample with two
audio tracks and embedded ASS. Run `node scripts/create-player-fixture.mjs` from
the repository, then run `flutter test integration_test/native_player_test.dart
-d windows --dart-define=TEST_MEDIA=<absolute-sample-path>` from `desktop`.
Optional `TEST_CAPTURE` writes only the Flutter test surface as a PNG.
After building, `./scripts/verify-window.ps1` checks that the packaged application
starts its service and closes during playback with exit code zero and no child
process left running. It uses a separate temporary data directory and muted audio.

The trial is not a finished distribution: it retains a Node service, the desktop
layout is being migrated rather than reproduced pixel for pixel, and original
account data needs explicit configuration. Live account writes, public torrents,
and every external danmaku provider require separate acceptance with configured
accounts and representative content.

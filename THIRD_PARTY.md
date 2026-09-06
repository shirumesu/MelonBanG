# Native dependencies

Application logic and UI are written in Dart. The Windows runner and plugins
contain the native code required by Flutter, SQLite, video playback, and BitTorrent.
There is no Node.js or Electron process and no external transcoding service.

| Dependency | Purpose | Upstream license and source |
| --- | --- | --- |
| Flutter | Window and scene rendering | [BSD-3-Clause](https://github.com/flutter/flutter/blob/master/LICENSE) |
| media_kit / media_kit_video | Dart player API and texture integration | [MIT](https://github.com/media-kit/media-kit/blob/main/LICENSE) |
| libmpv / bundled video libraries | Native media decoding and ASS subtitles | [media-kit native build sources and notices](https://github.com/media-kit/libmpv) |
| libtorrent_flutter 2.0.0 | Dart FFI bindings and packaged native torrent engine | [GPL-3.0](https://pub.dev/packages/libtorrent_flutter/license) |
| libtorrent 2.1.1 | BitTorrent protocol implementation | [Upstream licenses](https://github.com/arvidn/libtorrent/blob/RC_2_1/LICENSE) |
| SQLite | Local database | [Public domain](https://sqlite.org/copyright.html) |

The pinned package versions are in `pubspec.lock`. Flutter's generated asset
bundle includes the registered Dart package license notices. The local
media_kit_video override retains its upstream license and documents its Windows
shutdown patch in `vendor/media_kit_video/PATCHES.md`.

The local libtorrent_flutter override includes its license and recovery patch in
`vendor/libtorrent_flutter/PATCHES.md`. Windows CMake pins the native vcpkg registry
and builds the patched bridge from source. `scripts/build.ps1` copies native
dependency copyright files into the Release directory's `licenses` folder.

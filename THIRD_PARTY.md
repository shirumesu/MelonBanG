# Native dependencies

Application logic and UI are written in Dart. The desktop runners and plugins
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
| Resource Han Rounded 0.990 (CN Regular, Bold) | Bundled interface typeface | [SIL OFL 1.1](https://github.com/CyanoHao/Resource-Han-Rounded); full text in `assets/fonts/OFL.txt` |

The pinned package versions are in `pubspec.lock`. Flutter's generated asset
bundle includes the registered Dart package license notices. The local
media_kit_video override retains its upstream license and documents its Windows
shutdown patch in `vendor/media_kit_video/PATCHES.md`.

The local libtorrent_flutter override includes its license and recovery patch in
`vendor/libtorrent_flutter/PATCHES.md`. Windows CMake pins the native vcpkg registry
and builds the patched bridge from source. `scripts/build.ps1` copies native
dependency copyright files into the Release directory's `licenses` folder.
The macOS runner builds the same patched bridge against Homebrew libtorrent 2.1,
and bundles libtorrent and its non-system dynamic dependencies, including OpenSSL.
See [OpenSSL's license](https://www.openssl.org/source/license.html) and
[Boost's license](https://www.boost.org/users/license.html). The local macOS build
is intended for development; distribution needs a native-license packaging review.

## PikPak protocol reference

The Dart PikPak client uses public web-client protocol identifiers and captcha
constants documented by [Rclone's PikPak backend](https://github.com/rclone/rclone/tree/master/backend/pikpak).
Rclone is not bundled or run. The following MIT notice accompanies these protocol
references:

Copyright (C) 2012 by Nick Craig-Wood http://www.craig-wood.com/nick/

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

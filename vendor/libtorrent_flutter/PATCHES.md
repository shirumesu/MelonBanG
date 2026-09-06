# Windows disk recovery patch

Upstream: libtorrent_flutter 2.0.0, https://github.com/ayman708-UX/libtorrent_flutter.
The upstream license is retained in LICENSE. This app vendors the Dart bindings,
CA bundle, and native bridge; examples and unrelated platform runners are omitted.
The unused upstream src/CMakeLists.txt is also omitted; windows/CMakeLists.txt is
the single build entry for this Windows-only package. README.md and CHANGELOG.md
retain upstream documentation and may describe platforms absent from this copy.

The upstream session sets `no_recheck_incomplete_resume=true`, which skips existing
file verification when adding a torrent without resume data. Both reattachment and
force-recheck then returned zero progress with valid files still on disk. Set it to
false so libtorrent hashes and reuses existing pieces before downloading.

The Windows plugin builds this source against the pinned vcpkg registry configured
in windows/CMakeLists.txt. It never substitutes the upstream prebuilt DLL, which
would omit the fix. Libtorrent and its dependencies link statically into the bridge.
No separately installed torrent client is needed.

The application detaches handles with `deleteFiles:false` before upstream dispose,
because the upstream `disposeAll` deletes torrent files by default. Verify changes
with integration_test/torrent_test.dart, including restart after stopping its local
seeder and tracker. Native libraries remain independent from application services.

The Dart alert callback drains native alerts without printing every network event.
Application state and download errors remain available through torrentUpdates.

# Desktop disk recovery patch

Upstream: libtorrent_flutter 2.0.0, https://github.com/ayman708-UX/libtorrent_flutter.
The upstream license is retained in LICENSE. This app vendors the Dart bindings,
CA bundle, and native bridge; examples and unrelated platform runners are omitted.
The unused upstream src/CMakeLists.txt is also omitted. README.md and CHANGELOG.md
retain upstream documentation and may describe platforms absent from this copy.

The upstream session sets `no_recheck_incomplete_resume=true`, which skips existing
file verification when adding a torrent without resume data. Both reattachment and
force-recheck then returned zero progress with valid files still on disk. Set it to
false so libtorrent hashes and reuses existing pieces before downloading.

The Windows plugin builds this source against the pinned vcpkg registry configured
in windows/CMakeLists.txt. It never substitutes the upstream prebuilt DLL, which
would omit the fix. Libtorrent and its dependencies link statically into the bridge.
No separately installed torrent client is needed.

The macOS CocoaPod builds the same bridge with CMake against Homebrew libtorrent
2.1. Its build script copies the native dependency closure and rewrites dylib
references to relative loader paths before CocoaPods embeds and signs them.
Generated libraries and build caches are ignored. The Dart loader resolves the
bridge from the app bundle's Frameworks directory, independent of the working
directory. Re-run `pod install` after changing the native bridge or Homebrew
dependencies. Builds target the host architecture.

Engine `dispose` destroys the session without calling the destructive upstream
`disposeAll`; explicit torrent removal still supports file deletion. Verify changes
with integration_test/torrent_test.dart, including restart after stopping its local
seeder and tracker. Native libraries remain independent from application services.

The Dart alert callback drains native alerts without printing every network event.
Application state and download errors remain available through torrentUpdates.

## Download lifecycle and settings

The bridge now translates libtorrent states explicitly into the compact C/Dart
state enum; libtorrent's deprecated numeric slots cannot be cast directly.
Add calls accept flags for initially paused handles and `stop_when_ready` local
verification. Restored tasks can hash their files without briefly connecting to
peers before the application's queue/seeding policy takes effect. Auto-management
stays disabled: DownloadRepository owns queue admission and explicit pause state.

`lt_save_metadata` exports acquired metadata (including tracker tiers) so magnets
can be restored from a torrent file without rediscovering metadata online. Data
pieces are still verified on restart, rather than assumed valid through seed mode.
Settings now apply per-torrent connection limits to ordinary downloads, honor the
listen port, and apply IPv6/TCP/uTP switches in both directions when toggled.
The session no longer imposes a fixed four-times cap or floor of 200. Per-torrent
limits and application admission govern the total for downloads and seeders;
libtorrent still applies operating-system resource limits. Rebuild the bridge
after changing this policy.
Dart and native bridge must be rebuilt together because the metadata export is a
new C symbol. The native torrent test covers stopped offline recovery, native
pause/queue state, settings persistence, and corrupted local pieces.

## Desktop polling and file metadata

Status snapshots are emitted on every poll, including idle seeders, so application
seeding limits do not depend on changing peers or rates. Every native field is
refreshed, including total upload and errors. File queries populate size and
verified downloaded bytes using libtorrent's piece-granularity `file_progress`.
The C file-info struct and Dart FFI layout must be rebuilt together.

Session creation now leaves libtorrent's transport, connection, piece-picking and
socket settings at upstream defaults. The application no longer inherits the
streaming adapter's aggressive timeouts, predictive announcements and qBittorrent
fingerprint. Explicit settings and the established native disk backend remain.
Native tests cover idle accounting, file metadata, transient SQLite write failures,
same-torrent removal/re-import, local upload/download integrity and restart.

## Peer discovery and diagnostics

The session announces to one tracker in each independent tier concurrently.
Libtorrent's default stops after the first successful tier even when that tracker
returns no peers, leaving other swarms undiscovered. Same-tier fallback and tracker
minimum intervals remain unchanged; this does not announce to every URL or force
repeated announces. See [libtorrent tracker settings](https://www.libtorrent.org/reference-Settings.html).

Status snapshots expose known peers, successful/failed tracker counts and the
largest DHT routing table across interfaces. A successful tracker route takes
precedence over failures on other interfaces. DHT statistics are sampled every
five seconds, using the existing native alert thread. These are discovery signals,
not a guarantee that a peer has a complete copy or will provide upload bandwidth.
The expanded download card shows them, and an idle task with no connected peers
is labelled as searching for download nodes. Small transfer rates use KiB/s or B/s.
The C status struct and Dart FFI layout must be rebuilt together.

`integration_test/torrent_test.dart` uses two local tracker tiers: the first replies
successfully with no peers and the second supplies a real wire-protocol seeder.
It verifies downloaded hashes and the diagnostic fields through DownloadRepository,
alongside existing recovery, queue and sharing checks. This controlled test does
not establish public-swarm throughput; network routing and seed availability still
matter. Transport limits, DHT/PEX defaults and explicit pause ownership are retained.

## Persistent playback streaming

HTTP readers retain default priority outside the playback window for persistent
downloads, including after seeks and trailing-cache eviction. Ephemeral streams
retain on-demand selection. This prevents streaming from changing the wanted size
or stopping a normal cache task before every file is complete.

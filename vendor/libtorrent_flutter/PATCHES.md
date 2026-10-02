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
The Windows plugin prefers package configs so libtorrent's Boost dependency uses
BoostConfig.cmake without the removed FindBoost module warning on CMake 3.30+.
Setting CMP0167 only in the plugin does not reach vcpkg's captured macro policy scope.

The macOS Dart build hook builds the same bridge with CMake and bundles it as a
native code asset. Pinned libtorrent 2.1.2 and OpenSSL 3.6.5 sources are downloaded
with SHA-256 verification and linked statically; Homebrew supplies only the build
tools and Boost headers. All native code uses the hook's target architecture and
macOS deployment version, independent of the host's OS version or Homebrew bottle
requirements. Only C bridge symbols are exported. Flutter embeds and signs the
single resulting library, and its native asset resolver locates it at runtime.
Sources and compilation caches stay in the generated hook output directory.
Ordinary `flutter build macos` rebuilds changed bridge sources without CocoaPods
or a manual native preparation step.

Engine `dispose` destroys the session without calling the destructive upstream
`disposeAll`; explicit torrent removal still supports file deletion. Native libraries
remain independent from application services.

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
Torrent files load with `load_torrent_file`; metadata exports use
`get_resume_data(save_info_dict)` and `write_torrent_file_buf`, allowing missing v2
piece layers while a magnet is incomplete. File queries combine `layout()` with
`get_renamed_files()` to retain the engine's on-disk names without deprecated APIs.
Settings now apply per-torrent connection limits to ordinary downloads, honor the
listen port, and apply IPv6/TCP/uTP switches in both directions when toggled.
The session no longer imposes a fixed four-times cap or floor of 200. Per-torrent
limits and application admission govern the total for downloads and seeders;
libtorrent still applies operating-system resource limits. Rebuild the bridge
after changing this policy.
Dart and native bridge must be rebuilt together because the metadata export is a
new C symbol.

## Desktop polling and file metadata

Status snapshots are emitted on every poll, including idle seeders, so application
seeding limits do not depend on changing peers or rates. Every native field is
refreshed, including total upload and errors. File queries populate size and
verified downloaded bytes using libtorrent's piece-granularity `file_progress`.
The C file-info struct and Dart FFI layout must be rebuilt together.

Status queries omit `query_pieces`: the application does not consume the piece
bitfield, and copying and counting every piece on each UI poll is unnecessary.
The bridge uses libtorrent's existing `num_pieces` counter for `pieces_done`;
restored-file verification and verified file progress remain unchanged.

Session creation now leaves libtorrent's transport, connection, piece-picking and
socket settings at upstream defaults. The application no longer inherits the
streaming adapter's aggressive timeouts, predictive announcements and qBittorrent
fingerprint. Explicit settings and the established native disk backend remain.

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

## Persistent playback streaming

HTTP readers retain default priority outside the playback window for persistent
downloads, including after seeks and trailing-cache eviction. Ephemeral streams
retain on-demand selection. This prevents streaming from changing the wanted size
or stopping a normal cache task before every file is complete.

Cache hits consume the duplicate disk-read result so sequential prefetch does not
retain every played piece after the trailing cache evicts it. Concurrent HTTP
readers also wake on cached data when another reader consumes their shared disk
result. Seeking only resumes ephemeral torrents; persistent downloads keep the
application's pause and seeding policy even when an existing HTTP playback session
seeks after caching completes.

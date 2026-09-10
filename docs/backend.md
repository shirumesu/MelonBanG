# Backend contracts

The backend runs inside the Flutter process. `AppServices` constructs and disposes
Dart repositories; libtorrent owns transfer and piece verification, media_kit owns
playback, SQLite owns persistent application data, and OS APIs own credential
storage. There is no separate web server or Node service to deploy.

| Area | Owner | Behavior and regression evidence |
| --- | --- | --- |
| Startup and shutdown | `lib/app_services.dart` | Close is idempotent, partial startup releases resources, and closed services cannot restart. `test/services_test.dart`. |
| HTTP | `lib/data/network.dart` | One deadline covers headers and body; `http.AbortableRequest` cancels timed-out work without closing the shared client. Closing the service aborts active requests. A real loopback TCP test verifies disconnect and a subsequent successful request in `test/network_test.dart`. |
| Public catalog | `lib/data/catalog.dart` | Detail and list caches stay separate; concurrent fetches share a request; offline reads may reuse cache, explicit refresh reports failure. Outstanding cache fills are drained before the database closes. `test/data_test.dart`. |
| Account and OAuth | `lib/data/account.dart` | Account state is published after successful credential persistence. Login, refresh and logout writes are ordered. Refresh retains an existing refresh token if no replacement is returned. Concurrent 401 responses share one refresh and each request retries at most once. Responses from a replaced session are rejected. `test/backend_regression_test.dart`, `test/oauth_test.dart`. |
| Credential storage | `lib/data/credentials.dart` | Per-profile native Keychain/DPAPI, on-demand reads and process cache. Windows replaces encrypted files by rename without first deleting the working copy. `test/credential_access_test.dart`, `integration_test/credentials_test.dart`; native Windows checks require Windows. |
| Collections and episodes | `lib/data/tracking.dart`, `store.dart` | Partial collection edits merge inside the same SQLite transaction as their outbox mutation. Concurrent status/rating changes preserve both fields. A first rating-only collection has the same default wish state locally and remotely. Queued subject writes precede episode writes; a rejected entity does not block unrelated edits. Guest data is never silently uploaded. `test/backend_regression_test.dart`, `test/tracking_sync_test.dart`. |
| Acquisition | `lib/data/sources.dart` | RSS enclosures must identify torrent content; artwork does not supersede a download link. Torrent links can include query parameters. Recent search results are bounded across both acquisition views. `test/data_test.dart`. |
| Torrent lifecycle | `lib/data/downloads.dart`, `vendor/libtorrent_flutter/` | Application policy admits downloads/seeders; native defaults handle transfer. Polls include idle intervals for seeding accounting and native per-file verified progress. Record writes recover after individual failures; snapshots do not share nested mutable state with queued writes. Closing the engine preserves files. Removal and re-import of the same torrent are ordered. `integration_test/torrent_test.dart`. |
| Media and resume | `lib/data/playback_library.dart`, `lib/ui/player/playback.dart` | Download-backed episode shortcuts revalidate their task. Deleted task associations can resolve a replacement download. Unknown-duration saves do not erase useful progress; positions are bounded by duration. Failed media replacement stops prior playback and can recover. `test/media_repository_test.dart`, `integration_test/playback_recovery_test.dart`. |
| Danmaku | `lib/data/danmaku_repository.dart`, `playback_library.dart` | XML uses `xml`, HTML uses a DOM parser, and binary wire decoding uses Google's Dart `protobuf` runtime. Replacing a source clears obsolete comments even when the new fetch fails; stale requests cannot replace a newer selection. `test/data_test.dart`, `test/media_repository_test.dart`. |

## Dependency choices

Use the maintained native engines already integrated into the app. The desktop
libtorrent session uses upstream transport and piece-picking defaults instead of
streaming-specific connection churn, predictive announcements, socket tuning, or
another client's fingerprint. Explicit application settings still control rates,
connections, discovery, listen interfaces, encryption and queue policy. Existing
mmap disk-backend selection is retained for the supported native build.

The vendored engine's optional HTTP streaming/cache implementation is not used by
the application: playback opens verified local files through media_kit. This code
remains upstream plugin functionality, not an independently verified application
feature. `vendor/*/PATCHES.md` records deviations that must survive dependency
updates. The small torrent identity scanner hashes original encoded info bytes;
libtorrent remains the authoritative torrent parser and verifier.

## Verification boundaries

Isolated tests cover provider parsing, persistence and request ordering without
personal credentials. Real desktop integration covers native transfer, file
retention, queue policy, Keychain, and media recovery. Provider fixtures are not
proof that a third-party service is currently available or that a real account has
all required permissions. Full Bangumi account round trips and Windows-native
execution require the corresponding configured environment. Newer native library
APIs must remain compatible with both the Windows pinned toolchain and macOS build.

References: [libtorrent file progress](https://libtorrent.org/reference-Torrent_Handle.html#file_progress()),
[Dart HTTP cancellation](https://pub.dev/documentation/http/latest/http/AbortableRequest-class.html),
[Dart protobuf runtime](https://pub.dev/documentation/protobuf/latest/protobuf/CodedBufferReader-class.html).

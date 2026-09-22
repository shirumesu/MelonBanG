# Backend contracts

The backend runs inside the Flutter process. `AppServices` constructs and disposes
Dart repositories; libtorrent owns transfer and piece verification, media_kit owns
playback, SQLite owns persistent application data, and OS APIs own credential
storage. There is no separate web server or Node service to deploy.

| Area | Owner | Behavior and regression evidence |
| --- | --- | --- |
| Startup and shutdown | `lib/app_services.dart` | Close is idempotent, partial startup releases resources, and closed services cannot restart. `test/services_test.dart`. |
| HTTP | `lib/data/network.dart` | One deadline covers headers and body; `http.AbortableRequest` cancels timed-out work without closing the shared client. Closing the service aborts active requests. A real loopback TCP test verifies disconnect and a subsequent successful request in `test/network_test.dart`. |
| Public catalog | `lib/data/catalog.dart` | Detail and list caches stay separate; concurrent fetches share a request. Discovery/detail views publish saved content before refreshing expired entries; explicit refresh reports failure without clearing the view. Outstanding cache fills are drained before the database closes. `test/data_test.dart`, `test/catalog_responsiveness_test.dart`. |
| Account and OAuth | `lib/data/account.dart` | Authenticated tokens are published after successful credential persistence; a public local profile preserves collection scope while credentials await authorization. Login, refresh and logout writes are ordered. Refresh retains an existing refresh token if no replacement is returned. Concurrent 401 responses share one refresh and each request retries at most once. Responses from a replaced session are rejected. `test/backend_regression_test.dart`, `test/oauth_test.dart`. |
| Credential storage | `lib/data/credentials.dart` | Per-profile native Keychain/DPAPI, on-demand reads and process cache. [macOS signing and recovery](macos-signing.md) documents cross-build identity requirements. Windows replaces encrypted files by rename without first deleting the working copy. `test/credential_access_test.dart`, `integration_test/credentials_test.dart`; native Windows checks require Windows. |
| Collections and episodes | `lib/data/tracking.dart`, `store.dart` | Partial collection edits merge inside the same SQLite transaction as their outbox mutation. Concurrent status/rating changes preserve both fields. A first rating-only collection has the same default wish state locally and remotely. Queued subject writes precede episode writes; a rejected entity does not block unrelated edits. Guest data is never silently uploaded. `test/backend_regression_test.dart`, `test/tracking_sync_test.dart`. |
| Acquisition | `lib/data/sources.dart` | RSS enclosures must identify torrent content; artwork does not supersede a download link. Torrent links can include query parameters. Chinese/original/alias queries publish independently to both acquisition views; per-provider hash deduplication preserves result IDs. HTML metadata enriches existing RSS rows without blocking downloads. Episode terms are source search keywords, never inferred bindings. Recent search results are bounded across both views. `test/resource_search_test.dart`, `test/ui/resource_search_test.dart`, `test/data_test.dart`. |
| Torrent lifecycle | `lib/data/downloads.dart`, `vendor/libtorrent_flutter/` | Application policy admits downloads/seeders; native defaults handle transfer. Polls include idle intervals for seeding accounting and native per-file verified progress. Record writes recover after individual failures; snapshots do not share nested mutable state with queued writes. Closing the engine preserves files. Removal and re-import of the same torrent are ordered. `integration_test/torrent_test.dart`. |
| Media and resume | `lib/data/playback_library.dart`, `lib/ui/player/playback.dart` | Download-backed episode shortcuts revalidate their task. Deleted task associations can resolve a replacement download. Unknown-duration saves do not erase useful progress; positions are bounded by duration. Failed media replacement stops prior playback and can recover. `test/media_repository_test.dart`, `integration_test/playback_recovery_test.dart`. |
| Danmaku | `lib/data/danmaku_repository.dart`, `playback_library.dart` | XML uses `xml`, HTML uses a DOM parser, and binary wire decoding uses Google's Dart `protobuf` runtime. Playback starts matching without awaiting provider requests. Missing or ambiguous matches have an unmatched state; API failures remain errors. Replacing a source clears obsolete comments even when the new fetch fails; stale requests cannot replace a newer selection. `test/danmaku_matching_test.dart`, `test/data_test.dart`, `test/media_repository_test.dart`, `integration_test/playback_recovery_test.dart`. |

## Catalogue responsiveness

The homepage requests eight recommendations instead of waiting for every seasonal
page. Larger catalogue reads advance by the actual returned row count because the
upstream provider can cap the requested page size. Persistent freshness windows are
one hour for recommendations, subject details and the weekly schedule, fifteen
minutes for today's schedule, and five minutes for search results. Schedule keys
use the API's Asia/Shanghai date so yesterday's cache is not labelled as today.

Expired homepage, calendar and subject snapshots can render before their shared
network refresh finishes. Navigating back keeps the view usable while reloading an
unfinished detail request. Manual refresh retains content and reports failures at
its control. A cold empty schedule displays a loading state until its request ends.

Public subject detail and account episode synchronization run concurrently. The
detail view can use locally stored progress as soon as public detail is available;
the final result overlays synchronized progress without mixing account identities
or overriding queued local edits. `integration_test/catalog_loading_test.dart`
exercises cached display, navigation during refresh, the brand's home action, and
the settings view in the native Windows shell.

The client requests `/v1/subjects/{id}?includeHtml=false`. Melon API supports this
as a complete structured detail response, including episodes, characters, staff,
infobox and related subjects, without the unused live comment/discussion HTML.
An older API deployment ignores the option and retains its previous latency;
deploying the corresponding API change is required for the cold-detail benefit.

Remaining server optimization opportunities are concentrated in cache misses:
serve expired public snapshots while refreshing, combine concurrent loads for the
same key, reuse R2 hits in memory, and reuse schedule enrichment between requests.
Auxiliary HTML fetches should have an independent timeout budget when requested.
These changes need server-side failure and freshness tests before rollout; no
additional client cache framework or database replacement is required.

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

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../integrations/bangumi/account.dart';
import '../integrations/bangumi/community.dart';
import '../integrations/catalog.dart';
import '../core/content_cache.dart';
import '../core/credentials.dart';
import '../core/error_message.dart';
import '../core/network.dart';
import '../core/proxy.dart';
import '../core/service_configuration.dart';
import '../core/store.dart';
import '../core/storage_locations.dart';
import '../features/tracking/tracking_repository.dart';
import '../features/acquisition/release_search.dart';
import '../features/acquisition/source_registry.dart';
import '../features/danmaku/danmaku_controller.dart';
import '../features/danmaku/danmaku_preferences.dart';
import '../features/danmaku/danmaku_repository.dart';
import '../features/discovery/discovery_controller.dart';
import '../features/network/connectivity.dart';
import '../features/downloads/download_repository.dart';
import '../features/downloads/downloads_controller.dart';
import '../features/playback/play_selection.dart';
import '../features/playback/playback.dart';
import '../features/playback/playback_coordinator.dart';
import '../features/playback/playback_library.dart';
import '../features/playback/resource_search.dart';
import '../features/playback/resume_controller.dart';
import '../features/tracking/subject_controller.dart';
import '../features/tracking/tracking_controller.dart';
import '../features/update/app_update.dart';
import '../features/update/uninstall.dart';
import '../integrations/danmaku/bahamut.dart';
import '../integrations/danmaku/bilibili.dart';
import '../integrations/danmaku/dandanplay.dart';
import '../integrations/danmaku/melon.dart';
import '../integrations/danmaku/local.dart';
import '../integrations/melon_api/source_rules.dart';
import '../integrations/sources/engines.dart';
import '../integrations/transfer/libtorrent.dart';
import '../integrations/transfer/online.dart';
import '../integrations/transfer/pikpak.dart';
import '../integrations/transfer/pikpak_client.dart';
export '../core/json.dart';

/// Application-owned Dart services. No subprocess, IPC, or legacy runtime.
class AppServices {
  AppServices({
    this.directory,
    this.credentials,
    this.configuration = const ServiceConfiguration(),
    this.proxy,
    ApiClient? api,
  }) : api = api ?? ApiClient();
  final String? directory;

  /// Routes HTTP and online playback; installed before any client exists.
  final NetworkProxy? proxy;
  Credentials? credentials;
  final ServiceConfiguration configuration;
  final ApiClient api;
  String? dataDirectory;
  StorageLocations? storage;
  final startupStatus = ValueNotifier<String>('正在启动…');
  final downloadsAvailable = ValueNotifier<bool>(false);
  final downloadIssue = ValueNotifier<String?>(null);
  Future<void>? _restoringDownloads;
  Future<void> get downloadsReady async {
    await start();
    await _restoringDownloads;
  }

  late final AppStore store;
  late final AccountRepository account;
  late final CatalogRepository catalog;
  late final ContentCache cache;
  late final TrackingRepository tracking;
  late final BangumiPrivateClient community;
  late final DownloadRepository downloads;
  late final LibtorrentTransfer bt;
  late final PikPakTransfer pikpakTransfer;
  late final ReleaseSearch releases;
  late final DanmakuController danmaku;
  late final PlaybackLibrary library;
  late final SourceRegistry sources;
  late final PlaySelectionRepository selection;
  late final Playback playback;
  late final PlaybackCoordinator coordinator;
  late final DiscoveryController discovery;
  late final TrackingController personal;
  late final SubjectController subjects;
  late final AppUpdate update;
  late final ConnectivityCheck connectivity;
  late final AppUninstall uninstall;

  /// The search shown on the resources page.
  late final ResourceSearchController resources;
  late final DownloadsController downloadList;
  late final ResumeController resume;
  Future<void>? _starting;
  Future<void>? _closing;
  final _dispose = <Future<void> Function()>[];
  Future<void> start() {
    if (_closing != null) return Future.error(StateError('应用服务已关闭'));
    return _starting ??= _start();
  }

  /// The configured locations; null when a data directory override is set.
  Future<StorageLocations?> locate() => _locating ??= _locate();
  Future<StorageLocations?>? _locating;
  Future<StorageLocations?> _locate() async {
    if ((directory ?? Platform.environment['MELONBANG_DATA_DIR']) != null) {
      return null;
    }
    final support = (await getApplicationSupportDirectory()).path;
    final locations = StorageLocations(
      File(p.join(support, 'storage.json')),
      p.join(support, 'native'),
      // A released Windows copy keeps media beside the program, on the drive
      // picked at install, instead of filling the system drive.
      Platform.isWindows && AppUpdate.version.isNotEmpty
          ? p.join(AppUninstall.installation, 'downloads')
          : p.join(support, 'native', 'downloads'),
    );
    locations.onProgress = (message) => startupStatus.value = message;
    await locations.load();
    return storage = locations;
  }

  Future<void> _start() async {
    final override = directory ?? Platform.environment['MELONBANG_DATA_DIR'];
    if (override != null) {
      dataDirectory = override;
    } else {
      await locate();
      await storage!.migrate();
      dataDirectory = storage!.data;
    }
    await Directory(dataDirectory!).create(recursive: true);
    store = await AppStore.open(p.join(dataDirectory!, 'melonbang.sqlite'));
    _dispose.add(store.close);
    cache = ContentCache(api, store);
    _dispose.add(cache.close);
    await cache.initialize();
    credentials ??= platformCredentials(
      Platform.isMacOS
          ? storage?.credentialIdentity ?? p.join(dataDirectory!, 'credentials')
          : p.join(dataDirectory!, 'credentials'),
    );
    account = AccountRepository(
      api,
      credentials!,
      store: store,
      configuration: configuration,
    );
    _dispose.add(account.close);
    catalog = CatalogRepository(api, store, cache);
    _dispose.add(catalog.close);
    tracking = TrackingRepository(store, account, catalog);
    community = BangumiPrivateClient(account);
    _dispose.add(tracking.close);
    final pikpak = PikPakClient(credentials!);
    _dispose.add(() async => pikpak.close());
    await pikpak.initialize();
    final mediaDirectory =
        storage?.media ?? p.join(dataDirectory!, 'downloads');
    bt = LibtorrentTransfer(store, mediaDirectory);
    pikpakTransfer = PikPakTransfer(store, mediaDirectory, pikpak);
    // Sources are set up below; tasks resolve entries only once running.
    final online = OnlineDownloads(
      store,
      mediaDirectory,
      api,
      (ref) => sources.resolve(ref),
    );
    downloads = DownloadRepository([bt, pikpakTransfer, online]);
    _dispose.add(downloads.close);
    await bt.loadPreferences();
    library = PlaybackLibrary(store, downloads, catalog);
    final preferences = await SharedPreferences.getInstance();
    update = AppUpdate(api, preferences);
    await update.initialize();
    danmaku = DanmakuController(
      DanmakuRepository(store, catalog, [
        MelonDanmaku(
          api,
          token: account.accessToken,
          signedIn: () => account.profile != null,
        ),
        DandanplayDanmaku(api, configuration),
        BilibiliDanmaku(api),
        BahamutDanmaku(api),
      ], const LocalDanmaku()),
      DanmakuPreferences(preferences),
    );
    sources = SourceRegistry(
      api,
      preferences,
      SourceRulesClient(api),
      sourceEngines(api),
    );
    _dispose.add(() async => sources.dispose());
    await sources.initialize();
    connectivity = ConnectivityCheck(sources, proxy);
    final support = (await getApplicationSupportDirectory()).path;
    final folders = <String>[];
    for (final folder in [support, dataDirectory!, mediaDirectory]) {
      if (folders.any(
        (kept) => p.equals(kept, folder) || p.isWithin(kept, folder),
      )) {
        continue;
      }
      folders.removeWhere((kept) => p.isWithin(folder, kept));
      folders.add(folder);
    }
    uninstall = AppUninstall(
      dataFolders: folders,
      keychainService: Platform.isMacOS
          ? MacOSCredentials.serviceFor(
              storage?.credentialIdentity ??
                  p.join(dataDirectory!, 'credentials'),
            )
          : null,
    );
    releases = ReleaseSearch(api, sources, downloads);
    selection = PlaySelectionRepository(
      store,
      library,
      downloads,
      releases,
      sources,
      pikpakTransfer,
    );
    playback = Playback(library, downloads, danmaku, preferences, proxy: proxy);
    selection.remember = () => playback.settings.rememberSource;
    coordinator = PlaybackCoordinator(
      playback,
      selection,
      library,
      tracking,
      downloads,
    );
    _dispose.add(coordinator.close);
    discovery = DiscoveryController(catalog);
    personal = TrackingController(account, tracking);
    subjects = SubjectController(tracking);
    resources = newResourceSearch();
    downloadList = DownloadsController(
      downloads,
      ready: () => downloadsReady,
      stopSeeding: bt.stopSeeding,
    );
    _dispose.add(downloadList.close);
    resume = ResumeController(library, tracking);
    await account.initialize();
    tracking.start();
    _restoringDownloads = downloads.initialize();
    unawaited(
      _restoringDownloads!.then(
        (_) {
          downloadsAvailable.value = true;
        },
        onError: (Object error) {
          downloadIssue.value = errorMessage(error);
        },
      ),
    );
  }

  /// A separate search, e.g. for the player's resource sheet.
  ResourceSearchController newResourceSearch() =>
      ResourceSearchController(selection, playback, () => downloadsReady);

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    if (_starting == null) {
      api.close();
      return;
    }
    try {
      await _starting;
    } catch (_) {
      // Partially initialized services still own resources that need closing.
    }
    api.close();
    try {
      await _restoringDownloads;
    } catch (_) {
      // The local recovery error remains available to the downloads page.
    }
    Object? failure;
    StackTrace? stack;
    for (final dispose in _dispose.reversed) {
      try {
        await dispose();
      } catch (e, s) {
        failure ??= e;
        stack ??= s;
      }
    }
    if (failure != null) Error.throwWithStackTrace(failure, stack!);
  }
}

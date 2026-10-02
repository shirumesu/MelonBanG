import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/account.dart';
import 'data/catalog.dart';
import 'data/credentials.dart';
import 'data/danmaku_repository.dart';
import 'data/downloads.dart';
import 'data/network.dart';
import 'data/online_sources/repository.dart';
import 'data/play_selection.dart';
import 'data/playback_library.dart';
import 'data/pikpak.dart';
import 'data/pikpak_downloads.dart';
import 'data/service_configuration.dart';
import 'data/sources.dart';
import 'data/store.dart';
import 'data/storage_locations.dart';
import 'data/tracking.dart';
export 'data/json.dart';

/// Application-owned Dart services. No subprocess, IPC, or legacy runtime.
class AppServices {
  AppServices({
    this.directory,
    this.credentials,
    this.configuration = const ServiceConfiguration(),
    ApiClient? api,
  }) : api = api ?? ApiClient();
  final String? directory;
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

  bool _downloadsCreated = false;

  void releasePlaybackStreams(int? keep) {
    if (_downloadsCreated) downloads.releaseStreamsExcept(keep);
  }

  late final AppStore store;
  late final AccountRepository account;
  late final CatalogRepository catalog;
  late final TrackingRepository tracking;
  late final DownloadRepository downloads;
  late final PikPakClient pikpak;
  late final SourceRepository sources;
  late final DanmakuRepository danmaku;
  late final PlaybackLibrary library;
  late final OnlineSourceRepository online;
  late final PlaySelectionRepository selection;
  Future<void>? _starting;
  Future<void>? _closing;
  final _dispose = <Future<void> Function()>[];
  Future<void> start() {
    if (_closing != null) return Future.error(StateError('应用服务已关闭'));
    return _starting ??= _start();
  }

  Future<void> _start() async {
    final override = directory ?? Platform.environment['MELONBANG_DATA_DIR'];
    if (override != null) {
      dataDirectory = override;
    } else {
      final support = (await getApplicationSupportDirectory()).path;
      storage = StorageLocations(
        File(p.join(support, 'storage.json')),
        p.join(support, 'native'),
      );
      storage!.onProgress = (message) => startupStatus.value = message;
      await storage!.load();
      await storage!.migrate();
      dataDirectory = storage!.data;
    }
    await Directory(dataDirectory!).create(recursive: true);
    store = await AppStore.open(p.join(dataDirectory!, 'melonbang.sqlite'));
    _dispose.add(store.close);
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
    catalog = CatalogRepository(api, store);
    _dispose.add(catalog.close);
    tracking = TrackingRepository(store, account, catalog);
    _dispose.add(tracking.close);
    pikpak = PikPakClient(credentials!);
    _dispose.add(() async => pikpak.close());
    await pikpak.initialize();
    final mediaDirectory =
        storage?.media ?? p.join(dataDirectory!, 'downloads');
    downloads = DownloadRepository(
      store,
      mediaDirectory,
      pikpak: PikPakDownloadRepository(store, mediaDirectory, pikpak),
    );
    _downloadsCreated = true;
    _dispose.add(downloads.close);
    await downloads.loadPreferences();
    sources = SourceRepository(api, downloads);
    danmaku = DanmakuRepository(api, configuration: configuration);
    library = PlaybackLibrary(store, downloads, danmaku, catalog);
    _dispose.add(library.close);
    online = OnlineSourceRepository(api, await SharedPreferences.getInstance());
    _dispose.add(() async => online.dispose());
    await online.initialize();
    sources.providerEnabled = online.isEnabled;
    selection = PlaySelectionRepository(
      store,
      library,
      downloads,
      sources,
      online,
    );
    await account.initialize();
    tracking.start();
    _restoringDownloads = downloads.initialize();
    unawaited(
      _restoringDownloads!.then(
        (_) {
          downloadsAvailable.value = true;
        },
        onError: (Object error) {
          downloadIssue.value = error.toString();
        },
      ),
    );
  }

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

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'data/account.dart';
import 'data/catalog.dart';
import 'data/credentials.dart';
import 'data/danmaku_repository.dart';
import 'data/downloads.dart';
import 'data/network.dart';
import 'data/playback_library.dart';
import 'data/sources.dart';
import 'data/store.dart';
import 'data/tracking.dart';
export 'data/json.dart';

/// Application-owned Dart services. No subprocess, IPC, or legacy runtime.
class AppServices {
  AppServices({this.directory, this.credentials, ApiClient? api})
    : api = api ?? ApiClient();
  final String? directory;
  Credentials? credentials;
  final ApiClient api;
  String? dataDirectory;
  late final AppStore store;
  late final AccountRepository account;
  late final CatalogRepository catalog;
  late final TrackingRepository tracking;
  late final DownloadRepository downloads;
  late final SourceRepository sources;
  late final DanmakuRepository danmaku;
  late final PlaybackLibrary library;
  Future<void>? _starting;
  Future<void>? _closing;
  Future<void> start() => _starting ??= _start();
  Future<void> _start() async {
    dataDirectory =
        directory ??
        Platform.environment['MELONBANG_DATA_DIR'] ??
        p.join((await getApplicationSupportDirectory()).path, 'native');
    await Directory(dataDirectory!).create(recursive: true);
    store = await AppStore.open(p.join(dataDirectory!, 'melonbang.sqlite'));
    credentials ??= WindowsCredentials(p.join(dataDirectory!, 'credentials'));
    account = AccountRepository(api, credentials!);
    catalog = CatalogRepository(api, store);
    tracking = TrackingRepository(store, account, catalog);
    downloads = DownloadRepository(store, p.join(dataDirectory!, 'downloads'));
    sources = SourceRepository(api, downloads);
    danmaku = DanmakuRepository(api, credentials!);
    library = PlaybackLibrary(store, downloads, danmaku, catalog);
    await account.initialize();
    await downloads.initialize();
    tracking.start();
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    if (_starting == null) {
      api.close();
      return;
    }
    await _starting;
    await library.close();
    await account.close();
    api.close();
    await tracking.close();
    await downloads.close();
    await store.close();
  }
}

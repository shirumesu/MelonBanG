import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/error_message.dart';
import '../../core/json.dart';
import '../../core/network.dart';
import '../../integrations/github/app_releases.dart';

enum UpdatePhase { idle, checking, available, downloading, ready, failed }

/// Keeps the installed copy current: finds a newer release, downloads and
/// unpacks it beside the program while the app runs, and swaps it in once the
/// app has exited: `updater.exe` on Windows, a shell script on macOS.
class AppUpdate extends ChangeNotifier {
  AppUpdate(this.api, this.preferences) : releases = AppReleases(api);
  static const version = String.fromEnvironment('MELONBANG_VERSION');
  static final _platform = Platform.isMacOS ? 'macos-arm64' : 'windows-x64';
  final ApiClient api;
  final SharedPreferences preferences;
  final AppReleases releases;

  UpdatePhase phase = UpdatePhase.idle;
  AppRelease? release;

  /// The version unpacked and waiting for the next exit.
  String? readyVersion;
  double progress = 0;
  String? error;
  DateTime? checkedAt;

  /// Why this copy cannot update itself; null when it can.
  String? unavailable;

  bool get autoCheck => preferences.getBool('update-auto-check') ?? true;
  bool get autoDownload => preferences.getBool('update-auto-download') ?? true;

  Future<void> setAutoCheck(bool value) async {
    await preferences.setBool('update-auto-check', value);
    notifyListeners();
  }

  Future<void> setAutoDownload(bool value) async {
    await preferences.setBool('update-auto-download', value);
    notifyListeners();
  }

  /// The install directory on Windows, the app bundle on macOS.
  String get _installation => Platform.isMacOS
      ? p.dirname(p.dirname(p.dirname(Platform.resolvedExecutable)))
      : File(Platform.resolvedExecutable).parent.path;

  /// On the program's volume, so the swap is a rename. A bundle cannot hold
  /// it without breaking its signature, so macOS keeps it beside the bundle.
  Directory get _pending => Directory(
    Platform.isMacOS
        ? p.join(
            p.dirname(_installation),
            '.${p.basenameWithoutExtension(_installation)}-update',
          )
        : p.join(_installation, '.pending'),
  );
  File get _readyMarker => File(p.join(_pending.path, 'ready.json'));

  Future<void> initialize() async {
    if (!(Platform.isWindows || Platform.isMacOS) || version.isEmpty) {
      unavailable = '开发版本不自动更新';
      return;
    }
    if (Platform.isWindows &&
        !await File(p.join(_installation, 'updater.exe')).exists()) {
      unavailable = '当前安装缺少更新程序，请到 GitHub 下载新版本';
      return;
    }
    // Gatekeeper runs a quarantined app from a read-only random location.
    if (Platform.isMacOS && _installation.contains('/AppTranslocation/')) {
      unavailable = '请先把 MelonBanG 拖到“应用程序”文件夹再打开，才能自动更新';
      return;
    }
    if (await _readyMarker.exists()) {
      final pending =
          '${object(jsonDecode(await _readyMarker.readAsString()))['version']}';
      if (SemanticVersion.parse(pending)
              .compareTo(SemanticVersion.parse(version)) >
          0) {
        readyVersion = pending;
        phase = UpdatePhase.ready;
        return;
      }
    }
    // Left by a finished swap, an interrupted download or an older update.
    if (await _pending.exists()) await _pending.delete(recursive: true);
    await for (final entry in Directory.systemTemp.list()) {
      if (entry is Directory &&
          p.basename(entry.path).startsWith('melonbang-updater-')) {
        try {
          await entry.delete(recursive: true);
        } on FileSystemException {
          // The updater that relaunched this app may not have exited yet.
        }
      }
    }
  }

  Future<void> check() async {
    if (unavailable != null ||
        const [
          UpdatePhase.checking,
          UpdatePhase.downloading,
          UpdatePhase.ready,
        ].contains(phase)) {
      return;
    }
    phase = UpdatePhase.checking;
    error = null;
    notifyListeners();
    try {
      release = await releases.newerThan(version, _platform);
      phase = release == null ? UpdatePhase.idle : UpdatePhase.available;
      checkedAt = DateTime.now();
    } catch (e) {
      phase = UpdatePhase.failed;
      error = '检查更新失败：${errorMessage(e)}';
    }
    notifyListeners();
    if (phase == UpdatePhase.available && autoDownload) await download();
  }

  Future<void> download() async {
    final release = this.release!;
    phase = UpdatePhase.downloading;
    progress = 0;
    error = null;
    notifyListeners();
    try {
      if (await _pending.exists()) await _pending.delete(recursive: true);
      await _pending.create();
      final archive = File(p.join(_pending.path, 'update.zip'));
      await _fetch(release.package, archive);
      final staging = Directory(p.join(_pending.path, release.version));
      await staging.create();
      // ditto keeps the bundle's symbolic links, which its signature covers.
      final unpacked = Platform.isMacOS
          ? await Process.run('/usr/bin/ditto', [
              '-x',
              '-k',
              archive.path,
              staging.path,
            ])
          : await Process.run(
              p.join(
                Platform.environment['SystemRoot']!,
                'System32',
                'tar.exe',
              ),
              ['-xf', archive.path, '-C', staging.path],
            );
      if (unpacked.exitCode != 0) {
        throw StateError('解压失败：${unpacked.stderr}'.trim());
      }
      if (Platform.isMacOS &&
          !await Directory(p.join(staging.path, _bundleName)).exists()) {
        throw StateError('更新包缺少 $_bundleName');
      }
      await archive.delete();
      // Renamed into place so an interrupted write never leaves a marker
      // that the next start cannot read.
      final marker = File('${_readyMarker.path}.tmp');
      await marker.writeAsString(
        jsonEncode({'version': release.version}),
        flush: true,
      );
      await marker.rename(_readyMarker.path);
      readyVersion = release.version;
      phase = UpdatePhase.ready;
    } on FileSystemException catch (e) {
      phase = UpdatePhase.failed;
      final location = Platform.isMacOS ? ' MelonBanG 所在的文件夹' : '安装目录';
      error =
          '无法写入$location（${e.osError?.message ?? e.message}），请到 GitHub 手动下载新版本';
    } catch (e) {
      phase = UpdatePhase.failed;
      error = '下载更新失败：${errorMessage(e)}';
    }
    notifyListeners();
  }

  Future<void> _fetch(ReleaseFile file, File target) async {
    Object? failure;
    for (final url in file.urls) {
      try {
        final response = await api.client.send(http.Request('GET', url));
        if (response.statusCode != 200) {
          throw ApiException(response.statusCode, url.host);
        }
        final digest = _DigestSink();
        final hashing = sha256.startChunkedConversion(digest);
        final output = await target.open(mode: FileMode.write);
        var received = 0;
        try {
          await for (final chunk in response.stream) {
            await output.writeFrom(chunk);
            hashing.add(chunk);
            received += chunk.length;
            final percent = file.size == 0 ? 0 : received * 100 ~/ file.size;
            if (percent != (progress * 100).floor()) {
              progress = percent / 100;
              notifyListeners();
            }
          }
        } finally {
          await output.close();
        }
        hashing.close();
        if (received != file.size || '${digest.value}' != file.sha256) {
          throw StateError('更新包校验失败');
        }
        return;
      } catch (e) {
        failure = e;
      }
    }
    throw failure!;
  }

  /// Starts the updater for an unpacked update; the caller exits right after.
  Future<void> applyOnExit({required bool restart}) async {
    if (phase != UpdatePhase.ready) return;
    final staging = p.join(_pending.path, readyVersion!);
    if (Platform.isMacOS) {
      await Process.start('/bin/sh', [
        '-c',
        _macOSSwap,
        'melonbang-update',
        '$pid',
        _installation,
        p.join(staging, _bundleName),
        _pending.path,
        if (restart) 'restart',
      ], mode: ProcessStartMode.detached);
      return;
    }
    // The new updater handles the swap, and a temporary copy lets it replace
    // the one inside the install directory.
    final temporary = await Directory.systemTemp.createTemp(
      'melonbang-updater-',
    );
    final updater = await File(p.join(staging, 'updater.exe'))
        .copy(p.join(temporary.path, 'updater.exe'));
    await Process.start(
      updater.path,
      [
        '--pid',
        '$pid',
        '--app-dir',
        _installation,
        '--staging',
        staging,
        '--version',
        readyVersion!,
        if (restart) '--restart',
      ],
      workingDirectory: temporary.path,
      mode: ProcessStartMode.detached,
    );
  }
}

/// The bundle inside the macOS update package.
const _bundleName = 'MelonBanG.app';

/// Arguments: app process, installed bundle, staged bundle, pending
/// directory, and `restart` to open the app again. Waits for the app to
/// exit, then renames the staged bundle over the installed one and puts the
/// old one back if that fails; a failed swap keeps the update for the next
/// exit. The installed bundle keeps whatever name the person gave it.
const _macOSSwap = r'''
while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
previous="$4/previous.app"
rm -rf "$previous"
if mv "$2" "$previous"; then
  if mv "$3" "$2"; then
    rm -rf "$4"
  else
    mv "$previous" "$2"
  fi
fi
if [ -n "$5" ]; then open "$2"; fi
''';

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

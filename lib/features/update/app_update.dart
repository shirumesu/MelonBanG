import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/error_message.dart';
import '../../core/json.dart';
import '../../core/network.dart';
import '../../integrations/github/app_releases.dart';
import 'uninstall.dart';

enum UpdatePhase { idle, checking, available, downloading, ready, failed }

/// Keeps the installed copy current: finds a newer release, downloads and
/// unpacks it beside the program while the app runs, and swaps it in once the
/// app has exited: `updater.exe` on Windows, a shell script on macOS and for
/// the Linux AppImage.
class AppUpdate extends ChangeNotifier {
  AppUpdate(this.api, this.preferences) : releases = AppReleases(api);
  static const version = String.fromEnvironment('MELONBANG_VERSION');
  static final _platform = Platform.isMacOS
      ? 'macos-arm64'
      : Platform.isLinux
      ? 'linux-x64'
      : 'windows-x64';
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

  /// On the program's volume, so the swap is a rename. A bundle cannot hold
  /// it without breaking its signature, so macOS keeps it beside the bundle,
  /// and Linux beside the AppImage.
  Directory get _pending => Directory(
    !Platform.isWindows
        ? p.join(
            p.dirname(AppUninstall.installation),
            '.${p.basenameWithoutExtension(AppUninstall.installation)}-update',
          )
        : p.join(AppUninstall.installation, '.pending'),
  );
  File get _readyMarker => File(p.join(_pending.path, 'ready.json'));

  Future<void> initialize() async {
    if (version.isEmpty) {
      unavailable = '开发版本不自动更新';
      return;
    }
    if (Platform.isLinux && AppUninstall.appImage == null) {
      unavailable = '只有 AppImage 版本能自动更新';
      return;
    }
    if (Platform.isWindows &&
        !await File(p.join(AppUninstall.installation, 'updater.exe'))
            .exists()) {
      unavailable = '当前安装缺少更新程序，请到 GitHub 下载新版本';
      return;
    }
    // Gatekeeper runs a quarantined app from a read-only random location.
    if (Platform.isMacOS &&
        AppUninstall.installation.contains('/AppTranslocation/')) {
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
      final staging = Directory(p.join(_pending.path, release.version));
      await staging.create();
      if (Platform.isLinux) {
        // The AppImage is the package itself.
        final image = File(p.join(staging.path, _appImageName));
        await _fetch(release.package, image);
        final executable = await Process.run('chmod', ['755', image.path]);
        if (executable.exitCode != 0) {
          throw StateError('无法设置执行权限：${executable.stderr}'.trim());
        }
      } else {
        await _unpack(release.package, staging);
      }
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
      final location = Platform.isWindows ? '安装目录' : ' MelonBanG 所在的文件夹';
      error =
          '无法写入$location（${e.osError?.message ?? e.message}），请到 GitHub 手动下载新版本';
    } catch (e) {
      phase = UpdatePhase.failed;
      error = '下载更新失败：${errorMessage(e)}';
    }
    notifyListeners();
  }

  /// Downloads the archive of [package] and unpacks it into [staging].
  Future<void> _unpack(ReleaseFile package, Directory staging) async {
    final archive = File(p.join(_pending.path, 'update.zip'));
    await _fetch(package, archive);
    // ditto keeps the bundle's symbolic links, which its signature covers.
    final unpacked = Platform.isMacOS
        ? await Process.run('/usr/bin/ditto', [
            '-x',
            '-k',
            archive.path,
            staging.path,
          ])
        : await Process.run(
            p.join(Platform.environment['SystemRoot']!, 'System32', 'tar.exe'),
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
  }

  Future<void> _fetch(ReleaseFile file, File target) async {
    Object? failure;
    for (final url in file.urls) {
      try {
        // A stalled connection fails, so the next address gets its turn.
        final response = await api.client.sendAbortable(
          'GET',
          url,
          abort: Completer<void>(),
          timeout: _idle,
          message: '连接 ${url.host} 超时',
        );
        if (response.statusCode != 200) {
          await response.stream.listen(null).cancel();
          throw ApiException(response.statusCode, url.host);
        }
        final digest = _DigestSink();
        final hashing = sha256.startChunkedConversion(digest);
        final output = await target.open(mode: FileMode.write);
        var received = 0;
        try {
          await for (final chunk in response.stream.timeout(_idle)) {
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
    if (Platform.isLinux) {
      await Process.start('/bin/sh', [
        '-c',
        _linuxSwap,
        'melonbang-update',
        '$pid',
        AppUninstall.installation,
        p.join(staging, _appImageName),
        _pending.path,
        if (restart) 'restart',
      ], mode: ProcessStartMode.detached);
      return;
    }
    if (Platform.isMacOS) {
      await Process.start('/bin/sh', [
        '-c',
        _macOSSwap,
        'melonbang-update',
        '$pid',
        AppUninstall.installation,
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
        AppUninstall.installation,
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

/// Opens the app again once this process has exited, so every service starts
/// afresh; the caller exits right after.
Future<void> relaunchAfterExit() async {
  final executable = Platform.resolvedExecutable;
  if (Platform.isMacOS) {
    await Process.start('/bin/sh', [
      '-c',
      r'while kill -0 "$1" 2>/dev/null; do sleep 0.2; done; open "$2"',
      'melonbang-relaunch',
      '$pid',
      AppUninstall.installation,
    ], mode: ProcessStartMode.detached);
    return;
  }
  if (Platform.isLinux) {
    // An AppImage's own mount disappears with the app, so start the image.
    await Process.start('/bin/sh', [
      '-c',
      r'while kill -0 "$1" 2>/dev/null; do sleep 0.2; done; "$2" >/dev/null 2>&1 &',
      'melonbang-relaunch',
      '$pid',
      AppUninstall.appImage ?? executable,
    ], mode: ProcessStartMode.detached);
    return;
  }
  await Process.start('powershell', [
    '-NoProfile',
    '-WindowStyle',
    'Hidden',
    '-Command',
    'Wait-Process -Id $pid -ErrorAction SilentlyContinue; '
        "Start-Process -FilePath '${executable.replaceAll("'", "''")}'",
  ], mode: ProcessStartMode.detached);
}

/// The bundle inside the macOS update package.
const _bundleName = 'MelonBanG.app';

/// The staged Linux package.
const _appImageName = 'MelonBanG.AppImage';

/// How long a download may wait for its next bytes.
const _idle = Duration(seconds: 30);

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

/// Arguments: app process, installed AppImage, staged AppImage, pending
/// directory, and `restart`. A rename replaces the file in one step; the
/// AppImage keeps whatever name the person gave it.
const _linuxSwap = r'''
while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
if mv -f "$3" "$2"; then rm -rf "$4"; fi
if [ -n "$5" ]; then "$2" >/dev/null 2>&1 & fi
''';

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

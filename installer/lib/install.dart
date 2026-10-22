import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

const appVersion = String.fromEnvironment('MELONBANG_VERSION');

/// Bytes the installed program takes, measured when the package was built.
const installedSize = int.fromEnvironment('MELONBANG_INSTALLED_SIZE');

const _channel = MethodChannel('melonbang/setup');

Future<void> openLink(String target) =>
    _channel.invokeMethod('open', {'target': target});
Future<void> startDrag() => _channel.invokeMethod('startDrag');
Future<void> minimize() => _channel.invokeMethod('minimize');
Future<void> closeWindow() => _channel.invokeMethod('close');

/// A problem shown to the person installing.
class InstallError implements Exception {
  const InstallError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Installs the program archive the bootstrapper extracted next to this UI.
class Installer {
  Installer(this.payload);

  /// Started by the bootstrapper as `melonbang_setup.exe --payload <zip>`.
  factory Installer.fromArguments(List<String> arguments) =>
      Installer(arguments[arguments.indexOf('--payload') + 1]);

  final String payload;
  static final _tar = p.join(
    Platform.environment['SystemRoot']!,
    'System32',
    'tar.exe',
  );

  Future<Map<String, String>> _folders() async =>
      (await _channel.invokeMapMethod<String, String>('folders'))!;

  /// The current installation, or the per-user programs folder.
  Future<String> defaultLocation() async =>
      await _channel.invokeMethod<String>('installedLocation') ??
      p.join((await _folders())['localAppData']!, 'Programs', 'MelonBanG');

  Future<String?> pick(String current) async {
    var initial = current;
    while (!await Directory(initial).exists() &&
        p.dirname(initial) != initial) {
      initial = p.dirname(initial);
    }
    final picked = await _channel.invokeMethod<String>('pickFolder', {
      'initial': initial,
    });
    return picked == null ? null : target(picked);
  }

  /// The folder to install into for [chosen], whether picked or typed. One
  /// that already holds other files gets a MelonBanG subfolder, since
  /// uninstalling removes the install folder as a whole.
  Future<String> target(String chosen) async {
    final location = p.normalize(chosen);
    final folder = Directory(location);
    if (!await folder.exists() ||
        await isInstalled(location) ||
        await folder.list().isEmpty) {
      return location;
    }
    return p.join(location, 'MelonBanG');
  }

  Future<bool> isInstalled(String location) =>
      File(p.join(location, 'melonbang.exe')).exists();

  Future<void> install(
    String location, {
    required bool desktop,
    required bool startMenu,
    required void Function(double progress, String file) onProgress,
  }) async {
    final executable = p.join(location, 'melonbang.exe');
    if ((await _channel.invokeMethod<bool>('isRunning', {
      'directory': location,
    }))!) {
      throw const InstallError('MelonBanG 正在运行，请先关闭它再安装');
    }
    try {
      await Directory(location).create(recursive: true);
      final probe = File(p.join(location, '.melonbang-write-test'));
      await probe.writeAsString('');
      await probe.delete();
    } on FileSystemException {
      throw const InstallError('无法写入这个位置，请选择其他文件夹');
    }
    // An update the previous version had prepared would replace this one.
    final pending = Directory(p.join(location, '.pending'));
    if (await pending.exists()) await pending.delete(recursive: true);

    final listing = await Process.run(_tar, ['-tf', payload]);
    final total = const LineSplitter().convert('${listing.stdout}').length;
    final extracting = await Process.start(_tar, [
      '-xvf',
      payload,
      '-C',
      location,
    ]);
    var done = 0;
    final output = extracting.stdout.drain<void>();
    await for (final line
        in extracting.stderr
            .transform(systemEncoding.decoder)
            .transform(const LineSplitter())) {
      // bsdtar reports each extracted entry as "x <path>".
      if (!line.startsWith('x ')) continue;
      onProgress(++done / total, line.substring(2));
    }
    await output;
    if (await extracting.exitCode != 0) {
      throw const InstallError('解压程序文件失败，请重新运行安装程序');
    }

    final folders = await _folders();
    for (final (wanted, folder) in [
      (desktop, folders['desktop']!),
      (startMenu, folders['programs']!),
    ]) {
      final link = p.join(folder, 'MelonBanG.lnk');
      if (wanted) {
        await _channel.invokeMethod('createShortcut', {
          'link': link,
          'target': executable,
          'directory': location,
        });
      } else if (await File(link).exists()) {
        await File(link).delete();
      }
    }
    await _channel.invokeMethod('register', {
      'location': location,
      'version': appVersion,
      'sizeKb': installedSize ~/ 1024,
    });
  }

  Future<void> launch(String location) => Process.start(
    p.join(location, 'melonbang.exe'),
    const [],
    workingDirectory: location,
    mode: ProcessStartMode.detached,
  );
}

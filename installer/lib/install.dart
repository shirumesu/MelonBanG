import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

const appVersion = String.fromEnvironment('MELONBANG_VERSION');

const channel = MethodChannel('melonbang/setup');

final tar = p.join(Platform.environment['SystemRoot']!, 'System32', 'tar.exe');

Future<void> openLink(String target) =>
    channel.invokeMethod('open', {'target': target});
Future<void> startDrag() => channel.invokeMethod('startDrag');
Future<void> minimize() => channel.invokeMethod('minimize');
Future<void> closeWindow() => channel.invokeMethod('close');

Future<Map<String, String>> folders() async =>
    (await channel.invokeMapMethod<String, String>('folders'))!;

Future<bool> isRunning(String directory) async =>
    (await channel.invokeMethod<bool>('isRunning', {'directory': directory}))!;

/// Application support holds settings, the storage.json bootstrap and,
/// unless they were moved, the data folder.
final support = p.join(
  Platform.environment['APPDATA']!,
  'app.melonbang',
  'melonbang',
);

/// The app's storage.json bootstrap, empty before its first launch.
Future<Map<String, Object?>> storage() async {
  final bootstrap = File(p.join(support, 'storage.json'));
  if (!await bootstrap.exists()) return <String, Object?>{};
  return jsonDecode(await bootstrap.readAsString()) as Map<String, Object?>;
}

/// Where downloaded media goes.
String mediaIn(Map<String, Object?> storage) =>
    storage['media'] as String? ?? p.join(support, 'native', 'downloads');

/// The app has stored nothing yet, so its media location can still be chosen,
/// as its first launch would otherwise ask.
Future<bool> fresh() async =>
    !await File(p.join(support, 'storage.json')).exists() &&
    !await Directory(p.join(support, 'native')).exists();

/// Registers the program's rounded font from its [directory] of font files.
Future<void> loadFonts(String directory) async {
  final loader = FontLoader('Resource Han Rounded');
  for (final weight in ['Regular', 'Bold']) {
    loader.addFont(
      File(p.join(directory, 'ResourceHanRoundedCN-$weight.ttf'))
          .readAsBytes()
          .then(ByteData.sublistView),
    );
  }
  await loader.load();
}

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

  /// Unpacks the program's fonts beside the archive, in the bootstrapper's
  /// temporary directory, and returns their folder.
  Future<String> fonts() async {
    final directory = p.dirname(payload);
    final unpacked = await Process.run(tar, [
      '-xf',
      payload,
      '-C',
      directory,
      'data/flutter_assets/assets/fonts',
    ]);
    if (unpacked.exitCode != 0) throw StateError('${unpacked.stderr}');
    return p.join(directory, 'data', 'flutter_assets', 'assets', 'fonts');
  }

  /// The archive's entries and the bytes they take once unpacked.
  late final Future<({int entries, int bytes})> contents = () async {
    // bsdtar lists "mode links owner group size date name".
    final listing = await Process.run(tar, ['-tvf', payload]);
    final lines = const LineSplitter().convert('${listing.stdout}');
    return (
      entries: lines.length,
      bytes: lines.fold(
        0,
        (sum, line) => sum + int.parse(line.trim().split(RegExp(r'\s+'))[4]),
      ),
    );
  }();

  /// The current installation, or the per-user programs folder.
  Future<String> defaultLocation() async =>
      await channel.invokeMethod<String>('installedLocation') ??
      p.join((await folders())['localAppData']!, 'Programs', 'MelonBanG');

  Future<String?> pick(String current) async {
    final picked = await _pickFolder(current);
    return picked == null ? null : target(picked);
  }

  Future<String?> pickMedia(String current, String location) async {
    final picked = await _pickFolder(current);
    return picked == null ? null : mediaTarget(picked, location);
  }

  Future<String?> _pickFolder(String current) async {
    var initial = current;
    while (!await Directory(initial).exists() &&
        p.dirname(initial) != initial) {
      initial = p.dirname(initial);
    }
    return channel.invokeMethod<String>('pickFolder', {'initial': initial});
  }

  /// The folder to install into for [chosen], whether picked or typed. One
  /// that already holds other files gets a MelonBanG subfolder, since
  /// uninstalling removes the install folder as a whole. Media an uninstall
  /// kept there does not count.
  Future<String> target(String chosen) async {
    final location = p.normalize(chosen);
    final folder = Directory(location);
    final media = mediaIn(await storage());
    if (!await folder.exists() ||
        await isInstalled(location) ||
        await folder.list().every((entry) => p.equals(entry.path, media))) {
      return location;
    }
    return p.join(location, 'MelonBanG');
  }

  Future<bool> isInstalled(String location) =>
      File(p.join(location, 'melonbang.exe')).exists();

  /// The media folder for [chosen] next to an install at [location], by the
  /// app's own rules (`storageTarget`): a drive's root or a folder that
  /// already holds other files gets a MelonBanG Media subfolder, and the
  /// install folder its downloads one, which updates leave in place.
  Future<String> mediaTarget(String chosen, String location) async {
    var media = p.normalize(chosen);
    if (p.dirname(media) == media ||
        await Directory(media).exists() && !await _empty(media)) {
      media = p.join(media, 'MelonBanG Media');
    }
    final downloads = p.join(location, 'downloads');
    if (!p.equals(location, media) && !p.isWithin(location, media) ||
        p.equals(downloads, media) ||
        p.isWithin(downloads, media)) {
      return media;
    }
    return downloads;
  }

  /// Whether [path] holds nothing but files Explorer leaves in folders it
  /// shows, as the app's `isEmptyFolder` counts it.
  Future<bool> _empty(String path) => Directory(path).list().every(
    (entry) => const {
      '.DS_Store',
      '.localized',
      'desktop.ini',
      'Thumbs.db',
    }.contains(p.basename(entry.path)),
  );

  Future<void> install(
    String location, {
    String? media,
    required bool desktop,
    required bool startMenu,
    required void Function(double progress, String file) onProgress,
  }) async {
    final executable = p.join(location, 'melonbang.exe');
    if (await isRunning(location)) {
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
    if (media != null) await _recordMedia(media);
    // An update the previous version had prepared would replace this one.
    final pending = Directory(p.join(location, '.pending'));
    if (await pending.exists()) await pending.delete(recursive: true);

    final (:entries, :bytes) = await contents;
    final extracting = await Process.start(tar, [
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
      onProgress(++done / entries, line.substring(2));
    }
    await output;
    if (await extracting.exitCode != 0) {
      throw const InstallError('解压程序文件失败，请重新运行安装程序');
    }

    final places = await folders();
    for (final (wanted, folder) in [
      (desktop, places['desktop']!),
      (startMenu, places['programs']!),
    ]) {
      final link = p.join(folder, 'MelonBanG.lnk');
      if (wanted) {
        await channel.invokeMethod('createShortcut', {
          'link': link,
          'target': executable,
          'directory': location,
        });
      } else if (await File(link).exists()) {
        await File(link).delete();
      }
    }
    await channel.invokeMethod('register', {
      'location': location,
      'version': appVersion,
      'sizeKb': bytes ~/ 1024,
    });
  }

  /// Writes the app's storage.json as its first launch would
  /// (`StorageLocations.choose`), so it starts with this media folder.
  Future<void> _recordMedia(String media) async {
    final folder = Directory(media);
    try {
      await folder.create(recursive: true);
      if (!await _empty(media)) {
        throw const InstallError('下载位置必须是空文件夹，请重新选择');
      }
      final probe = File(p.join(media, '.melonbang-write-check'));
      await probe.writeAsString('');
      await probe.delete();
    } on FileSystemException {
      throw const InstallError('无法写入下载位置，请选择其他文件夹');
    }
    final bootstrap = File(p.join(support, 'storage.json'));
    await bootstrap.parent.create(recursive: true);
    final temporary = File('${bootstrap.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({'media': p.normalize(p.absolute(media))}),
      flush: true,
    );
    await temporary.rename(bootstrap.path);
  }

  Future<void> launch(String location) => Process.start(
    p.join(location, 'melonbang.exe'),
    const [],
    workingDirectory: location,
    mode: ProcessStartMode.detached,
  );
}

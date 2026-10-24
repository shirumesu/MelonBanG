import 'dart:io';

import 'package:path/path.dart' as p;

import 'install.dart';

/// Removes an installed MelonBanG. uninstall.exe in the install directory
/// starts a temporary copy of this UI as `uninstall.exe --uninstall <dir>`,
/// so the install directory can be deleted while it runs.
class Uninstaller {
  Uninstaller(this.location);

  factory Uninstaller.fromArguments(List<String> arguments) =>
      Uninstaller(arguments[arguments.indexOf('--uninstall') + 1]);

  final String location;

  /// The installed program's own fonts.
  String get fonts =>
      p.join(location, 'data', 'flutter_assets', 'assets', 'fonts');

  late final Future<Map<String, Object?>> _storage = storage();

  /// Every existing folder of the program's data, none inside another.
  late final Future<List<String>> data = () async {
    final storage = await _storage;
    final kept = <String>[];
    for (final folder in [
      support,
      storage['data'],
      storage['media'],
    ].whereType<String>()) {
      if (kept.any(
        (other) => p.equals(other, folder) || p.isWithin(other, folder),
      )) {
        continue;
      }
      if (await Directory(folder).exists()) kept.add(folder);
    }
    return kept;
  }();

  /// Bytes the program's data takes.
  late final Future<int> dataSize = () async {
    var total = 0;
    for (final folder in await data) {
      await for (final entry in Directory(folder).list(recursive: true)) {
        if (entry is File) total += await entry.length();
      }
    }
    return total;
  }();

  /// Removes shortcuts, program files and, with [wipe], all data. Returns
  /// the folders that could not be removed completely; the installed apps
  /// entry is only removed with the program files.
  Future<List<String>> uninstall({
    required bool wipe,
    required void Function(double progress, String task) onProgress,
  }) async {
    onProgress(0, '移除快捷方式');
    final places = await folders();
    for (final folder in [places['desktop']!, places['programs']!]) {
      final link = File(p.join(folder, 'MelonBanG.lnk'));
      if (await link.exists()) await link.delete();
    }

    final media = mediaIn(await _storage);
    // Media is kept beside the program by default; keeping data keeps it.
    final kept = !wipe && p.isWithin(location, media) ? media : null;
    final roots = [
      location,
      if (wipe)
        ...(await data).where((folder) => !p.isWithin(location, folder)),
    ];
    final files = [
      for (final root in roots)
        await for (final entry in Directory(root).list(recursive: true))
          if (entry is File && (kept == null || !p.isWithin(kept, entry.path)))
            (root, entry),
    ];
    final left = <String>{};
    for (final (index, (root, file)) in files.indexed) {
      onProgress(
        (index + 1) / (files.length + 1),
        p.isWithin(media, file.path)
            ? '删除已下载的番剧'
            : root == location
            ? '删除程序文件'
            : '删除追番记录和设置',
      );
      try {
        await file.delete();
      } on FileSystemException {
        // Held open by another program, such as an antivirus scan.
        left.add(root);
      }
    }
    for (final root in roots) {
      if (left.contains(root)) continue;
      if (root == location && kept != null) {
        await for (final entry in Directory(root).list()) {
          if (!p.equals(entry.path, kept) && !p.isWithin(entry.path, kept)) {
            await entry.delete(recursive: true);
          }
        }
      } else {
        await Directory(root).delete(recursive: true);
      }
    }
    // Application support sits in a folder named after the company.
    final company = Directory(p.dirname(support));
    if (wipe && await company.exists() && await company.list().isEmpty) {
      await company.delete();
    }
    if (!left.contains(location)) {
      onProgress(1, '清理安装记录');
      await channel.invokeMethod('unregister');
    }
    return [
      for (final root in roots)
        if (left.contains(root)) root,
    ];
  }
}

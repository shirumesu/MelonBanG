import 'dart:io';

import 'package:path/path.dart' as p;

/// [name] with the characters Windows, macOS and Linux refuse in a file
/// name replaced by spaces, and without the dots and spaces Windows drops
/// from its ends.
String safeFileName(String name) {
  final cleaned = name
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^[. ]+|[. ]+$'), '');
  return cleaned.isEmpty ? 'MelonBanG' : cleaned;
}

/// What the system's file manager is called where a button opens it.
final String showInFileManagerLabel = Platform.isMacOS
    ? '在访达中显示'
    : Platform.isWindows
    ? '在资源管理器中显示'
    : '在文件管理器中显示';

/// Opens [path] in the system's file manager: with it selected in its
/// folder when [select], else the folder itself.
Future<void> showInFileManager(String path, {bool select = false}) async {
  if (Platform.isMacOS) {
    await Process.run('open', [if (select) '-R', path]);
  } else if (Platform.isLinux) {
    // Nautilus, Dolphin and Nemo select a file through this interface.
    if (select) {
      final shown = await Process.run('gdbus', [
        'call',
        '--session',
        '--dest=org.freedesktop.FileManager1',
        '--object-path=/org/freedesktop/FileManager1',
        '--method=org.freedesktop.FileManager1.ShowItems',
        // A quote would end the GVariant string; it is valid escaped.
        "['${Uri.file(path).toString().replaceAll("'", '%27')}']",
        '',
      ]);
      if (shown.exitCode == 0) return;
    }
    await Process.start('xdg-open', [
      select ? p.dirname(path) : path,
    ], mode: ProcessStartMode.detached);
  } else {
    // Explorer exits with 1 even when it opened the window.
    await Process.start('explorer.exe', [
      if (select) '/select,',
      path,
    ], mode: ProcessStartMode.detached);
  }
}

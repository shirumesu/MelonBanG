import 'dart:io';

import 'package:path/path.dart' as p;

import 'app_update.dart';

enum UninstallKind {
  /// The installer's `uninstall.exe`, which asks whether to keep the data.
  windowsInstaller,

  /// The app bundle goes to the Trash once the app has quit.
  macOSBundle,

  /// A portable Windows copy: deleting its folder removes it.
  portable,

  /// A development build or a copy macOS runs from a temporary location.
  unavailable,
}

/// Removes this copy of MelonBanG from inside the app, so nobody has to look
/// for the uninstaller. Data folders are only deleted on request.
class AppUninstall {
  AppUninstall({required this.dataFolders, this.keychainService});

  /// Settings, records and downloaded media, none inside another.
  final List<String> dataFolders;

  /// macOS keychain items of the account sign-ins.
  final String? keychainService;

  static const _bundleIdentifier = 'org.melonbang.melonbang';

  /// The install directory on Windows, the app bundle on macOS.
  static String get installation => Platform.isMacOS
      ? p.dirname(p.dirname(p.dirname(Platform.resolvedExecutable)))
      : File(Platform.resolvedExecutable).parent.path;

  UninstallKind get kind {
    if (AppUpdate.version.isEmpty) return UninstallKind.unavailable;
    if (Platform.isWindows) {
      return File(p.join(installation, 'uninstall.exe')).existsSync()
          ? UninstallKind.windowsInstaller
          : UninstallKind.portable;
    }
    if (Platform.isMacOS &&
        installation.endsWith('.app') &&
        !installation.contains('/AppTranslocation/')) {
      return UninstallKind.macOSBundle;
    }
    return UninstallKind.unavailable;
  }

  /// Starts the uninstaller or the removal; the caller quits right after.
  /// The Windows uninstaller waits for the app to exit and asks about the
  /// data itself; on macOS [wipe] decides.
  Future<void> start({bool wipe = false}) async {
    switch (kind) {
      case UninstallKind.windowsInstaller:
        await Process.start(
          p.join(installation, 'uninstall.exe'),
          const [],
          workingDirectory: Directory.systemTemp.path,
          mode: ProcessStartMode.detached,
        );
      case UninstallKind.macOSBundle:
        await Process.start('/bin/sh', [
          '-c',
          _macOSRemoval,
          'melonbang-uninstall',
          '$pid',
          installation,
          wipe ? '1' : '0',
          _bundleIdentifier,
          keychainService ?? '',
          ...dataFolders,
        ], mode: ProcessStartMode.detached);
      case UninstallKind.portable || UninstallKind.unavailable:
        throw StateError('这个副本不能在应用内卸载');
    }
  }
}

/// Arguments: app process, bundle, `1` to delete data, bundle identifier,
/// keychain service, then the data folders. Waits for the app to exit, puts
/// the bundle in the Trash (deleting it when that fails) and, when asked,
/// removes the data folders, preferences, caches and keychain items.
const _macOSRemoval = r'''
while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
bundle="$2"; wipe="$3"; id="$4"; service="$5"
shift 5
name=$(basename "$bundle" .app)
target="$HOME/.Trash/$name.app"
if [ -e "$target" ]; then target="$HOME/.Trash/$name $(date +%H.%M.%S).app"; fi
mv "$bundle" "$target" 2>/dev/null || rm -rf "$bundle"
if [ "$wipe" = 1 ]; then
  for folder in "$@"; do rm -rf "$folder"; done
  defaults delete "$id" 2>/dev/null
  rm -rf "$HOME/Library/Caches/$id" "$HOME/Library/HTTPStorages/$id" \
    "$HOME/Library/Saved Application State/$id.savedState"
  if [ -n "$service" ]; then
    while security delete-generic-password -s "$service" >/dev/null 2>&1; do :; done
  fi
fi
''';

import 'dart:async';
import 'dart:io';

import 'package:tray_manager/tray_manager.dart' as tray;

/// The tray icon (menu bar on macOS) shown while there are subscriptions,
/// with a way back to the window, to check them now, and to quit.
class AppTray with tray.TrayListener {
  AppTray({required this.onOpen, required this.onCheck, required this.onQuit});
  final void Function() onOpen, onCheck, onQuit;
  bool _shown = false;
  String? _menu;

  /// Shows the icon, or updates its menu: how many shows are [subscribed]
  /// and how many cache tasks are [caching].
  Future<void> show({required int subscribed, required int caching}) async {
    try {
      if (!_shown) {
        tray.trayManager.addListener(this);
        await tray.trayManager.setIcon(
          Platform.isWindows
              ? 'assets/images/tray.ico'
              : 'assets/images/mark.png',
        );
        if (!Platform.isLinux) {
          await tray.trayManager.setToolTip('MelonBanG · 后台检查订阅更新');
        }
        _shown = true;
      }
      final signature = '$subscribed:$caching';
      if (signature == _menu) return;
      _menu = signature;
      await tray.trayManager.setContextMenu(
        tray.Menu(
          items: [
            tray.MenuItem(label: '打开 MelonBanG', onClick: (_) => onOpen()),
            tray.MenuItem.separator(),
            tray.MenuItem(label: '订阅了 $subscribed 部番', disabled: true),
            tray.MenuItem(label: '立即检查更新', onClick: (_) => onCheck()),
            if (caching > 0)
              tray.MenuItem(label: '缓存中 $caching 个', disabled: true),
            tray.MenuItem.separator(),
            tray.MenuItem(label: '退出', onClick: (_) => onQuit()),
          ],
        ),
      );
    } catch (_) {
      // A desktop without a tray keeps the window's own way back.
    }
  }

  Future<void> hide() async {
    if (!_shown) return;
    _shown = false;
    _menu = null;
    tray.trayManager.removeListener(this);
    try {
      await tray.trayManager.destroy();
    } catch (_) {
      // Already gone with the desktop's tray.
    }
  }

  // Windows opens the window on a click and the menu on a right click; the
  // menu bar opens the menu either way.
  @override
  void onTrayIconMouseDown() {
    if (Platform.isMacOS) {
      unawaited(tray.trayManager.popUpContextMenu());
    } else {
      onOpen();
    }
  }

  @override
  void onTrayIconRightMouseDown() =>
      unawaited(tray.trayManager.popUpContextMenu());
}

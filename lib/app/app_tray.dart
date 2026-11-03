import 'dart:io';

import 'package:tray_manager/tray_manager.dart' as tray;

/// The tray icon (menu bar on macOS) shown while there are subscriptions,
/// with a way back to the window, to check them now, and to quit.
class AppTray {
  AppTray({required this.onOpen, required this.onCheck, required this.onQuit});
  final void Function() onOpen, onCheck, onQuit;
  tray.TrayIcon? _icon;
  String? _signature;

  /// The shown menu and its items, kept along with their click listeners
  /// until a new menu replaces them.
  tray.Menu? _menu;
  List<tray.MenuItem> _items = const [];

  /// Shows the icon, or updates its menu: how many shows are [subscribed]
  /// and how many cache tasks are [caching].
  void show({required int subscribed, required int caching}) {
    // A desktop without a tray keeps the window's own way back.
    final icon = _icon ??= _create();
    if (icon == null) return;
    final signature = '$subscribed:$caching';
    if (signature == _signature) return;
    final menu = tray.Menu.create();
    if (menu == null) return;
    _signature = signature;
    final items = <tray.MenuItem>[];
    void add(String label, [void Function()? onClick]) {
      final item = tray.MenuItem.createWithLabelAndType(
        label,
        tray.MenuItemType.normal,
      );
      if (item == null) return;
      if (onClick == null) {
        item.isEnabled = false;
      } else {
        item.addListener((event) {
          if (event is tray.MenuItemClickedEvent) onClick();
        });
      }
      menu.addItem(item);
      items.add(item);
    }

    add('打开 MelonBanG', onOpen);
    menu.addSeparator();
    add('订阅了 $subscribed 部番');
    add('立即检查更新', onCheck);
    if (caching > 0) add('缓存中 $caching 个');
    menu.addSeparator();
    add('退出', onQuit);
    icon.setContextMenu(menu);
    _release();
    _menu = menu;
    _items = items;
  }

  void hide() {
    final icon = _icon;
    if (icon == null) return;
    _icon = null;
    _signature = null;
    icon
      ..setVisible(false)
      ..dispose();
    _release();
  }

  void _release() {
    for (final item in _items) {
      item.dispose();
    }
    _menu?.dispose();
    _menu = null;
    _items = const [];
  }

  tray.TrayIcon? _create() {
    final icon = tray.TrayIcon.create();
    if (icon == null) return null;
    icon
      ..icon = tray.ImageAsset.fromAsset(
        Platform.isWindows
            ? 'assets/images/tray.ico'
            : 'assets/images/mark.png',
      )
      ..setTooltip('MelonBanG · 后台检查订阅更新')
      // Windows opens the window on a click and the menu on a right click;
      // the menu bar opens the menu either way. Linux panels open the menu
      // themselves and report no clicks.
      ..setContextMenuTrigger(
        Platform.isWindows
            ? tray.ContextMenuTrigger.rightClicked
            : tray.ContextMenuTrigger.clicked,
      )
      ..addListener((event) {
        switch (event) {
          case tray.TrayIconClickedEvent() when Platform.isWindows:
            onOpen();
          case tray.TrayIconRightClickedEvent() when Platform.isMacOS:
            icon.openContextMenu();
          default:
        }
      })
      ..setVisible(true);
    return icon;
  }
}

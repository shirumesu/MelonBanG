import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';
import 'app/app_services.dart';
import 'core/proxy.dart';
import 'core/service_configuration.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kReleaseMode) {
    // A part that fails to build says so instead of leaving a grey box.
    ErrorWidget.builder = (_) => const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: Text(
          '这部分内容显示失败',
          style: TextStyle(color: Color(0xff8a8f98), fontSize: 12),
        ),
      ),
    );
  }
  if (kDebugMode && (Platform.isWindows || Platform.isMacOS)) {
    // Hot restart replaces Dart isolates, but keeps the native video plugin.
    // Release its old outputs before media_kit sends quit to the old players.
    await const MethodChannel('com.alexmercerind/media_kit_video')
        .invokeMethod<void>('VideoOutputManager.Reset');
  }
  final preferences = await SharedPreferences.getInstance();
  // Before any HTTP client is created: each one asks the proxy per request.
  final proxy = NetworkProxy(preferences);
  await proxy.initialize();
  final configuration = await ServiceConfiguration.load();
  MediaKit.ensureInitialized(libmpv: Platform.isLinux ? _linkedLibmpv() : null);
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(1360, 860),
      minimumSize: Size(960, 640),
      center: true,
      title: 'Melonbang',
      backgroundColor: Color(0xfff4f5f7),
      titleBarStyle: TitleBarStyle.hidden,
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
  runApp(
    MelonApp(
      service: AppServices(
        configuration: configuration,
        proxy: proxy,
        preferences: preferences,
      ),
      preferences: preferences,
    ),
  );
}

/// The libmpv the video plugin links, already loaded. media_kit would
/// otherwise open `libmpv.so`, which can be the system's copy beside the
/// AppImage's, and mpv aborts when handles cross the two.
String? _linkedLibmpv() {
  final library = RegExp(r'\s(/\S*/libmpv\.so[.\d]*)$');
  for (final line in File('/proc/self/maps').readAsLinesSync()) {
    if (library.firstMatch(line) case final match?) return match[1];
  }
  return null;
}

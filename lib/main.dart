import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'app_services.dart';
import 'data/service_configuration.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final configuration = await ServiceConfiguration.load();
  MediaKit.ensureInitialized();
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
      service: AppServices(configuration: configuration),
      preferences: await SharedPreferences.getInstance(),
      initialMedia: args
          .where((arg) => !arg.startsWith('-') && File(arg).existsSync())
          .firstOrNull,
    ),
  );
}

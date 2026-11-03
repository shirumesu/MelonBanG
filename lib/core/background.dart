import 'dart:io';

import 'package:flutter/services.dart';

/// What the desktop does for the app while its window is closed to the
/// background: system notifications, keeping macOS from napping, and the
/// runner's requests to quit or to open a notification.
abstract final class Background {
  static const _channel = MethodChannel('org.melonbang/system');

  /// Takes the macOS runner's requests: [onQuit] for Command-Q, the Dock or
  /// the menu bar, [onOpenSubject] for a clicked notification.
  static void listen({
    required void Function() onQuit,
    required void Function(int subjectId) onOpenSubject,
  }) {
    if (!Platform.isMacOS) return;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'quit':
          onQuit();
        case 'openNotification':
          if (call.arguments case final int id) onOpenSubject(id);
        default:
          throw MissingPluginException();
      }
    });
  }

  /// Shows a system notification; clicking one about [subjectId] opens it
  /// on macOS. Windows shows none.
  static Future<void> notify(
    String title,
    String body, {
    int? subjectId,
  }) async {
    try {
      if (Platform.isMacOS) {
        await _channel.invokeMethod<void>('notify', {
          'title': title,
          'body': body,
          'subjectId': ?subjectId,
        });
      } else if (Platform.isLinux) {
        await Process.run('notify-send', ['--app-name=Melonbang', title, body]);
      }
    } catch (_) {
      // A desktop without a notification service shows nothing.
    }
  }

  /// Keeps macOS App Nap from stretching timers to minutes while [on];
  /// the computer may still sleep.
  static Future<void> keepAwake(bool on) async {
    if (!Platform.isMacOS) return;
    await _channel.invokeMethod<void>('keepAwake', on);
  }

  /// Quits the macOS runner, once the services are closed.
  static Future<void> quit() async {
    if (!Platform.isMacOS) return;
    await _channel.invokeMethod<void>('quit');
  }
}

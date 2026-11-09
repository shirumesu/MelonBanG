import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

/// What the desktop does for the app while its window is closed to the
/// background: system notifications, keeping macOS from napping, and the
/// runner's requests to quit, to open a notification or to end the session.
abstract final class Background {
  static const _channel = MethodChannel('org.melonbang/system');

  /// Takes the macOS and Windows runners' requests: [onQuit] for macOS
  /// Command-Q, the Dock, the menu bar, logging out and shutting down,
  /// [onOpenSubject] for a clicked notification, and [onEndSession] while
  /// Windows logs out or shuts down, which ends the process once it returns.
  static void listen({
    required void Function() onQuit,
    required void Function(int subjectId) onOpenSubject,
    required Future<void> Function() onEndSession,
  }) {
    if (!Platform.isMacOS && !Platform.isWindows) return;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'quit':
          onQuit();
        case 'openNotification':
          if (call.arguments case final int id) onOpenSubject(id);
        case 'endSession':
          await onEndSession();
        default:
          throw MissingPluginException();
      }
    });
  }

  /// Shows a system notification about [subjectId]; clicking it calls
  /// [listen]'s `onOpenSubject`. Windows shows it as a tray balloon, a
  /// toast on Windows 10 and later.
  static Future<void> notify(
    String title,
    String body, {
    int? subjectId,
  }) async {
    try {
      if (Platform.isMacOS || Platform.isWindows) {
        await _channel.invokeMethod<void>('notify', {
          'title': title,
          'body': body,
          'subjectId': ?subjectId,
        });
      } else if (Platform.isLinux) {
        await Process.run('notify-send', ['--app-name=MelonBanG', title, body]);
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

  /// On Windows, runs the process in efficiency mode (EcoQoS) at background
  /// CPU, disk and memory priority while [on], so games and other foreground
  /// apps come first; downloads continue, only slower when contended.
  static void yieldResources(bool on) {
    if (!Platform.isWindows || _yielding == on) return;
    _yielding = on;
    final process = _getCurrentProcess();
    _setPriorityClass(process, on ? 0x00100000 : 0x00200000);
    final throttling = calloc<Uint32>(3);
    // PROCESS_POWER_THROTTLING_STATE: version 1, execution speed.
    throttling[0] = 1;
    throttling[1] = 1;
    throttling[2] = on ? 1 : 0;
    _setProcessInformation(process, 4, throttling.cast(), 12);
    calloc.free(throttling);
  }

  static bool _yielding = false;
  static final _kernel32 = DynamicLibrary.open('kernel32.dll');
  static final _getCurrentProcess = _kernel32
      .lookupFunction<IntPtr Function(), int Function()>('GetCurrentProcess');
  static final _setPriorityClass = _kernel32
      .lookupFunction<
        Int32 Function(IntPtr, Uint32),
        int Function(int, int)
      >('SetPriorityClass');
  static final _setProcessInformation = _kernel32
      .lookupFunction<
        Int32 Function(IntPtr, Int32, Pointer<Void>, Uint32),
        int Function(int, int, Pointer<Void>, int)
      >('SetProcessInformation');

  /// Quits the macOS or Windows runner, once the services are closed. The
  /// runner quits after this call returns, since closing the window shuts
  /// the engine down, which cannot happen while Dart runs.
  static Future<void> quit() async {
    if (!Platform.isMacOS && !Platform.isWindows) return;
    await _channel.invokeMethod<void>('quit');
  }
}

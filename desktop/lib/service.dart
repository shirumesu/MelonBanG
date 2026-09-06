import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef Json = Map<String, dynamic>;
Json object(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
List<Json> objects(dynamic value) =>
    value is List ? value.map(object).toList() : [];
String titleOf(Json value) =>
    '${value['nameCn'] ?? value['displayName'] ?? value['name'] ?? value['title'] ?? '未命名'}';
double number(dynamic value) => value is num ? value.toDouble() : 0;

class Service {
  Process? _process;
  final events = StreamController<Json>.broadcast();
  final _pending = <int, Completer<dynamic>>{};
  int _next = 0;
  String? dataDirectory;
  String? failure;
  bool _closed = false;

  Future<void> start() async {
    final bundled = p.join(p.dirname(Platform.resolvedExecutable), 'service');
    final host =
        Platform.environment['MELONBANG_SERVICE'] ??
        p.join(bundled, 'host.cjs');
    final node =
        Platform.environment['MELONBANG_NODE'] ?? p.join(bundled, 'node.exe');
    if (!File(host).existsSync()) {
      throw StateError('找不到应用服务，请使用 native:dev 启动或使用完整构建目录。');
    }
    dataDirectory =
        Platform.environment['MELONBANG_DATA_DIR'] ??
        p.join((await getApplicationSupportDirectory()).path, 'data');
    await Directory(dataDirectory!).create(recursive: true);
    _process = await Process.start(
      node,
      [host],
      workingDirectory: p.dirname(host),
      environment: {
        'MELONBANG_DATA_DIR': dataDirectory!,
        'MELONBANG_CONFIG_DIR':
            Platform.environment['MELONBANG_CONFIG_DIR'] ??
            (await getApplicationSupportDirectory()).path,
      },
    );
    _process!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          try {
            final message = object(jsonDecode(line));
            if (message.containsKey('event')) {
              events.add(message);
              return;
            }
            final pending = _pending.remove(message['id']);
            if (pending == null) return;
            if (message['error'] != null) {
              pending.completeError(StateError(message['error'].toString()));
            } else {
              pending.complete(message['result']);
            }
          } catch (_) {
            /* A dependency may emit a diagnostic before initialization. */
          }
        });
    _process!.stderr.transform(utf8.decoder).listen((text) {
      stderr.write(text);
    });
    unawaited(
      _process!.exitCode.then((code) {
        failure = '应用服务已退出（$code），请重新启动应用。';
        for (final pending in _pending.values) {
          pending.completeError(StateError(failure!));
        }
        _pending.clear();
        if (!events.isClosed) {
          events.add({'event': 'serviceError', 'data': failure});
        }
      }),
    );
    await call('health');
  }

  Future<dynamic> call(String method, [List<dynamic> args = const []]) async {
    if (_process == null || failure != null) {
      throw StateError(failure ?? '应用服务未启动。');
    }
    final id = ++_next;
    final result = Completer<dynamic>();
    _pending[id] = result;
    _process!.stdin.writeln(
      jsonEncode({'id': id, 'method': method, 'args': args}),
    );
    try {
      return await result.future.timeout(
        Duration(seconds: method == 'bangumi.signIn' ? 300 : 90),
      );
    } finally {
      _pending.remove(id);
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _process?.stdin.close();
    if (_process != null) {
      try {
        await _process!.exitCode.timeout(const Duration(seconds: 3));
      } on TimeoutException {
        _process!.kill();
      }
    }
    await events.close();
  }
}

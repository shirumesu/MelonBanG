import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/error_message.dart';
import '../../core/network.dart';
import '../../core/proxy.dart';
import '../../domain/sources.dart';
import '../../integrations/melon_api/source_rules.dart';
import '../acquisition/source_registry.dart';

/// A service the app talks to.
class ProbeTarget {
  const ProbeTarget(this.id, this.name, this.group, this.url);
  final String id, name, group;
  final Uri url;
}

enum ProbeState { waiting, running, reachable, limited, failed }

class ProbeResult {
  const ProbeResult(this.state, {this.elapsed, this.status, this.error});
  final ProbeState state;
  final Duration? elapsed;
  final int? status;
  final String? error;
}

/// Checks whether each service answers, through the current proxy setting.
/// Any HTTP response counts as reachable; 403, 451 and 5xx usually mean a
/// block or an outage and are reported as limited.
class ConnectivityCheck extends ChangeNotifier {
  ConnectivityCheck(this.sources, this.proxy);
  final SourceRegistry sources;
  final NetworkProxy? proxy;
  final results = <String, ProbeResult>{};
  bool running = false;
  int _run = 0;

  List<ProbeTarget> get targets => [
    ProbeTarget(
      'bangumi-api',
      'Bangumi API',
      'Bangumi',
      Uri.https('api.bgm.tv', '/v0/subjects/8'),
    ),
    ProbeTarget('bangumi-web', 'Bangumi 网站与登录', 'Bangumi', Uri.https('bgm.tv')),
    ProbeTarget(
      'bangumi-next',
      'Bangumi 社区',
      'Bangumi',
      Uri.https('next.bgm.tv'),
    ),
    ProbeTarget(
      'bangumi-image',
      'Bangumi 图片',
      'Bangumi',
      Uri.https('lain.bgm.tv'),
    ),
    ProbeTarget('melon-api', 'Melon API', '服务', Uri.parse('$melonApiOrigin/')),
    ProbeTarget('github', 'GitHub（更新）', '服务', Uri.https('api.github.com')),
    ProbeTarget('dandanplay', '弹弹play', '弹幕', Uri.https('api.dandanplay.net')),
    ProbeTarget('bilibili', 'Bilibili', '弹幕', Uri.https('api.bilibili.com')),
    ProbeTarget('bahamut', '巴哈姆特', '弹幕', Uri.https('api.gamer.com.tw')),
    for (final kind in SourceKind.values)
      for (final source in sources.instancesOf(kind))
        if (sources.isEnabled(source.id))
          if (Uri.tryParse(sources.currentDomain(source.id)) case final url?
              when url.hasScheme && url.host.isNotEmpty)
            ProbeTarget(
              'source:${source.id}',
              source.name,
              kind == SourceKind.online ? '在线源' : 'BT 索引',
              url,
            ),
    ProbeTarget('pikpak', 'PikPak', '网盘', Uri.https('api-drive.mypikpak.com')),
  ];

  /// The target probing [id], if it is checked.
  ProbeTarget? target(String id) =>
      targets.where((target) => target.id == id).firstOrNull;

  /// Probes one target, unless a full test is running.
  Future<ProbeResult?> probe(String id) async {
    final target = this.target(id);
    if (target == null || running) return null;
    final run = _run;
    results[id] = const ProbeResult(ProbeState.running);
    notifyListeners();
    final client = ApiClient(timeout: const Duration(seconds: 10));
    try {
      final result = await _probe(client, target);
      if (run == _run) {
        results[id] = result;
        notifyListeners();
      }
      return result;
    } finally {
      client.close();
    }
  }

  /// Probes every target, four at a time.
  Future<void> runAll() async {
    final run = ++_run;
    final list = targets;
    results
      ..clear()
      ..addAll({
        for (final target in list)
          target.id: const ProbeResult(ProbeState.waiting),
      });
    running = true;
    notifyListeners();
    final client = ApiClient(timeout: const Duration(seconds: 10));
    var next = 0;
    Future<void> worker() async {
      while (next < list.length && run == _run) {
        final target = list[next++];
        results[target.id] = const ProbeResult(ProbeState.running);
        notifyListeners();
        final result = await _probe(client, target);
        if (run != _run) return;
        results[target.id] = result;
        notifyListeners();
      }
    }

    try {
      await Future.wait([for (var i = 0; i < 4; i++) worker()]);
    } finally {
      client.close();
      if (run == _run) {
        running = false;
        notifyListeners();
      }
    }
  }

  static final _anyStatus = {for (var code = 100; code < 600; code++) code};

  Future<ProbeResult> _probe(ApiClient client, ProbeTarget target) async {
    final clock = Stopwatch()..start();
    try {
      final response = await client.send(
        target.url,
        headers: const {'Accept': '*/*'},
        acceptedStatuses: _anyStatus,
      );
      final status = response.statusCode;
      return ProbeResult(
        status == 403 || status == 451 || status >= 500
            ? ProbeState.limited
            : ProbeState.reachable,
        elapsed: clock.elapsed,
        status: status,
      );
    } on TimeoutException {
      return const ProbeResult(ProbeState.failed, error: '超时（10 秒）');
    } catch (e) {
      return ProbeResult(ProbeState.failed, error: describeNetworkError(e));
    }
  }
}

/// A short reason for a failed connection; the diagnostic itself when the
/// cause is unknown.
String describeNetworkError(Object error) {
  if (networkFailure(error) case final reason?) return reason;
  final text = '$error';
  return text.length > 80 ? '${text.substring(0, 80)}…' : text;
}

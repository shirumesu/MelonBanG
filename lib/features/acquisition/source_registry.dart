import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/error_message.dart';
import '../../core/hls_playlist.dart';
import '../../core/json.dart';
import '../../core/network.dart';
import '../../domain/sources.dart';

class _SourceRead {
  final cancel = RequestCancellation();
  late Future<List<Object>> value;
  int users = 0;
}

/// Maintained sources of this run: the rule snapshot, per-source enablement
/// and health, engine instances and shared, briefly cached reads.
class SourceRegistry extends ChangeNotifier {
  SourceRegistry(this.api, this.preferences, this.rules, this.engines);
  final ApiClient api;
  final SharedPreferences preferences;
  final SourceRules rules;
  final Map<String, SourceEngineFactory> engines;
  final health = <String, SourceHealth>{};
  final errors = <String, String>{};
  final _engines = <String, SourceEngine>{};
  final _reads = <String, _SourceRead>{};
  final _cache = <String, ({DateTime expires, List<Object> rows})>{};
  late SourceSnapshot snapshot = rules.bundled;
  String ruleOrigin = '安装包内置';
  String? updateIssue;
  DateTime? checkedAt;
  bool _closed = false;
  Future<void>? _refreshing;

  List<SourceInstance> get instances => snapshot.instances;
  List<SourceInstance> instancesOf(SourceKind kind) =>
      instances.where((instance) => instance.kind == kind).toList();
  SourceInstance instance(String id) =>
      instances.firstWhere((instance) => instance.id == id);
  String get version => snapshot.version;
  bool get needsUpdate => instances.any((instance) => !instance.supported);
  bool get warning => health.entries.any(
    (e) =>
        isEnabled(e.key) &&
        const [SourceHealth.error, SourceHealth.verification].contains(e.value),
  );

  /// Also covers the PikPak transfer, which shares the Sources page switch.
  bool isEnabled(String id) =>
      preferences.getBool('source-enabled-$id') ?? true;
  bool usable(SourceInstance instance) =>
      isEnabled(instance.id) &&
      !instance.disabled &&
      instance.supported &&
      health[instance.id] != SourceHealth.verification;
  List<SourceInstance> usableOf(SourceKind kind) =>
      instancesOf(kind).where(usable).toList();

  SourceHealth status(String id) {
    final rule = instances.where((e) => e.id == id).firstOrNull;
    if (!isEnabled(id) || rule?.disabled == true) return SourceHealth.disabled;
    if (rule != null && !rule.supported) return SourceHealth.update;
    return health[id] ?? SourceHealth.enabled;
  }

  Future<void> setEnabled(String id, bool enabled) async {
    await preferences.setBool('source-enabled-$id', enabled);
    if (enabled && health[id] == SourceHealth.verification) health.remove(id);
    _clearReads();
    _notify();
  }

  void _notify() {
    if (!_closed) notifyListeners();
  }

  SourceEngine engine(String id) => _engines.putIfAbsent(id, () {
    final rule = instance(id);
    return engines[rule.engine]!(rule);
  });
  OnlineSourceEngine online(String id) => engine(id) as OnlineSourceEngine;
  TorrentSourceEngine torrent(String id) => engine(id) as TorrentSourceEngine;
  String currentDomain(String id) =>
      _engines[id]?.currentBase ?? instance(id).baseUrls.firstOrNull ?? '';

  Future<void> initialize() async {
    final cached = preferences.getString('online-source-rules');
    if (cached != null) {
      try {
        final value = object(jsonDecode(cached));
        // A snapshot cached by an older engine lacks rules this client runs.
        if (value['clientEngine'] == sourceEngineVersion) {
          snapshot = SourceSnapshot.fromJson(value);
          ruleOrigin = '本地缓存';
        }
      } catch (_) {
        /* Keep the bundled snapshot if the cache cannot be read. */
      }
    }
    unawaited(refreshRules().catchError((Object _) {}));
  }

  Future<void> refreshRules() =>
      _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  Future<void> _refresh() async {
    try {
      final result = await rules.fetch(
        etag: ruleOrigin == '安装包内置'
            ? null
            : preferences.getString('online-source-etag'),
      );
      if (_closed) return;
      checkedAt = DateTime.now();
      updateIssue = null;
      if (result != null) {
        await preferences.setString(
          'online-source-rules',
          jsonEncode(result.snapshot.json),
        );
        if (result.etag != null) {
          await preferences.setString('online-source-etag', result.etag!);
        } else {
          await preferences.remove('online-source-etag');
        }
        snapshot = result.snapshot;
        ruleOrigin = 'Melon API';
        _engines.clear();
        _clearReads();
      }
      _notify();
    } catch (error) {
      updateIssue = '规则更新失败，继续使用$ruleOrigin：${errorMessage(error)}';
      _notify();
      rethrow;
    }
  }

  void succeeded(String id) {
    health.remove(id);
    errors.remove(id);
    _notify();
  }

  void failed(String id, Object error) {
    health[id] = error is SourceVerificationRequired
        ? SourceHealth.verification
        : SourceHealth.error;
    errors[id] = errorMessage(error);
    _notify();
  }

  /// Searches every name concurrently, or in order until [enough] accepts the
  /// merged rows. One failing name does not discard the others.
  Future<List<SourceSubject>> searchSubjects(
    String id,
    Iterable<String> names, {
    bool refresh = false,
    RequestCancellation? cancel,
    bool Function(List<SourceSubject>)? enough,
  }) async {
    try {
      final rows = <String, SourceSubject>{};
      Object? failure;
      var completed = false;
      Future<List<SourceSubject>?> read(String name) async {
        final key = '$version:search:$id:$name';
        if (refresh) _cache.remove(key);
        try {
          final values = await _cachedRead(
            key,
            (token) => online(id).searchSubjects(name, cancel: token),
            cancel: cancel,
          );
          return values.cast<SourceSubject>();
        } on SourceVerificationRequired {
          rethrow;
        } catch (error) {
          cancel?.throwIfCancelled();
          failure = error;
          return null;
        }
      }

      void merge(List<SourceSubject>? values) {
        if (values == null) return;
        completed = true;
        for (final row in values) {
          rows[row.id] = row;
        }
      }

      final unique = names
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet();
      if (enough == null) {
        (await Future.wait(unique.map(read))).forEach(merge);
      } else {
        for (final name in unique) {
          cancel?.throwIfCancelled();
          merge(await read(name));
          if (enough(rows.values.toList())) break;
        }
      }
      if (!completed && failure != null) throw failure!;
      succeeded(id);
      return rows.values.toList();
    } catch (error) {
      cancel?.throwIfCancelled();
      failed(id, error);
      rethrow;
    }
  }

  Future<List<SourceEpisode>> episodes(
    String id,
    SourceSubject subject, {
    RequestCancellation? cancel,
  }) async {
    try {
      final values = await _cachedRead(
        '$version:episodes:$id:${subject.id}',
        (token) => online(id).episodes(subject, cancel: token),
        cancel: cancel,
      );
      return values.cast<SourceEpisode>();
    } catch (error) {
      cancel?.throwIfCancelled();
      failed(id, error);
      rethrow;
    }
  }

  /// Reads a fresh address; inserted HLS advertisements are filtered when the
  /// rule declares them.
  Future<ResolvedStream> resolve(
    StreamRef ref, {
    RequestCancellation? cancel,
  }) async {
    cancel?.throwIfCancelled();
    final id = ref.sourceId;
    if (!isEnabled(id)) throw StateError('视频源已停用');
    final rule = instance(id);
    if (rule.disabled) throw StateError('维护者已停用该视频源');
    if (!rule.supported) throw StateError('该视频源需要更新应用');
    try {
      var resolved = await online(id).resolve(ref, cancel: cancel);
      if (resolved.format == StreamFormat.hls && _filtersAds(rule)) {
        final manifest = await fetchPlaylist(
          api,
          Uri.parse(resolved.url),
          resolved.headers,
          filter: true,
          cancel: cancel,
        );
        resolved = resolved.withPlaylist(manifest.$1);
      }
      succeeded(id);
      return resolved;
    } catch (error) {
      if (cancel?.isCancelled != true) failed(id, error);
      rethrow;
    }
  }

  bool _filtersAds(SourceInstance rule) =>
      object(rule.config['playlistFilter'])['foreignPathBlocks'] == true;

  Future<List<Object>> _cachedRead(
    String key,
    Future<List<Object>> Function(RequestCancellation) load, {
    RequestCancellation? cancel,
  }) async {
    cancel?.throwIfCancelled();
    final cached = _cache.remove(key);
    if (cached != null && cached.expires.isAfter(DateTime.now())) {
      _cache[key] = cached;
      return cached.rows;
    }
    var read = _reads[key];
    if (read == null || read.cancel.isCancelled) {
      final created = _SourceRead();
      read = created;
      _reads[key] = created;
      created.value = load(created.cancel)
          .then((rows) {
            created.cancel.throwIfCancelled();
            _cache[key] = (
              expires: DateTime.now().add(const Duration(minutes: 5)),
              rows: rows,
            );
            while (_cache.length > 64) {
              _cache.remove(_cache.keys.first);
            }
            return rows;
          })
          .whenComplete(() {
            if (identical(_reads[key], created)) _reads.remove(key);
          });
    }
    final active = read;
    active.users++;
    final cancelled = Completer<List<Object>>();
    final stop = cancel?.listen(() {
      if (!cancelled.isCompleted) {
        cancelled.completeError(const RequestCancelled());
      }
    });
    try {
      return await Future.any([
        active.value,
        if (cancel != null) cancelled.future,
      ]);
    } finally {
      stop?.call();
      active.users--;
      if (active.users == 0 && identical(_reads[key], active)) {
        active.cancel.cancel();
      }
    }
  }

  void _clearReads() {
    for (final read in _reads.values) {
      read.cancel.cancel();
    }
    _reads.clear();
    _cache.clear();
  }

  @override
  void dispose() {
    _clearReads();
    _closed = true;
    super.dispose();
  }
}

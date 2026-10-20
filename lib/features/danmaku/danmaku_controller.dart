import 'package:flutter/foundation.dart';

import '../../domain/danmaku.dart';
import 'danmaku_preferences.dart';
import 'danmaku_repository.dart';

enum DanmakuStatus { idle, loading, ready, unmatched, error }

class DanmakuSourceState {
  DanmakuSourceState(this.id, this.label, {required this.enabled});
  final String id, label;
  bool enabled;
  DanmakuStatus status = DanmakuStatus.idle;
  int count = 0;

  /// Why an unmatched source loaded nothing.
  String? message;
  String? error;
  List<DanmakuCandidate> candidates = const [];
}

/// The current session's danmaku: per-source state and merged comments.
/// Each load holds a per-source ticket; a newer load or a new
/// session discards older results.
class DanmakuController extends ChangeNotifier {
  DanmakuController(this.repository, this.preferences) {
    preferences.addListener(_refresh);
  }
  final DanmakuRepository repository;
  final DanmakuPreferences preferences;
  DanmakuTarget? _target;
  List<DanmakuSourceState> sources = [];

  /// Enabled sources' comments, merged by time.
  List<DanmakuComment> comments = const [];

  /// [comments] after preferences.
  List<DanmakuComment> visible = const [];
  final _comments = <String, List<DanmakuComment>>{};
  final _loads = <String, Object>{};

  /// Starts a session with each provider's saved default enable state.
  void begin(DanmakuTarget target) {
    _target = target;
    _comments.clear();
    _loads.clear();
    sources = [
      for (final provider in repository.matchers)
        DanmakuSourceState(
          provider.id,
          provider.label,
          enabled: preferences.sourceEnabled(provider.id),
        ),
    ];
    _merge();
  }

  /// Loads every enabled automatic source: the stream's own locator, then a
  /// saved manual match, then the provider's own matching.
  Future<void> autoMatch(double duration, {DanmakuTarget? target}) async {
    final current = _target;
    if (current == null || (target != null && !identical(target, current))) {
      return;
    }
    Future<DanmakuEpisode>? episode;
    final query = DanmakuQuery(
      episode: () => episode ??= repository.episode(current),
      file: current.path == null
          ? null
          : DanmakuFile(
              path: current.path!,
              duration: duration,
              size: current.fileSize,
              filenameOnly: current.remote,
            ),
    );
    await Future.wait([
      for (final source in sources)
        if (source.enabled && source.id != repository.local.id)
          _load(source.id, () async {
            final provider = repository.matcher(source.id);
            if (current.embedded case (final id, final locator)
                when id == source.id) {
              return provider.load(locator);
            }
            final saved = current.matchKey == null
                ? null
                : await repository.savedLocator(current.matchKey!, source.id);
            if (saved != null) return provider.load(saved);
            final match = await provider.match(query);
            if (match.locator case final locator?) {
              return provider.load(locator);
            }
            throw _NoMatch(match);
          }),
    ]);
  }

  /// Loads a chosen or typed locator and remembers it for this media.
  Future<void> load(String provider, String locator) => _load(
    provider,
    () => repository.provider(provider).load(locator),
    save: locator,
  );

  bool searchable(String provider) =>
      repository.provider(provider) is DanmakuSearch;
  Future<List<DanmakuCandidate>> search(String provider, String title) =>
      (repository.provider(provider) as DanmakuSearch).search(title);

  /// Imports a local JSON file into this session only, replacing an earlier
  /// import; failure leaves the existing local comments intact.
  Future<void> importLocal(String path) async {
    final target = _target;
    if (target == null) return;
    final local = repository.local;
    final ticket = Object();
    _loads[local.id] = ticket;
    final comments = await local.load(path);
    if (!identical(_target, target) || _loads[local.id] != ticket) return;
    _comments[local.id] = comments;
    final source =
        sources.where((source) => source.id == local.id).firstOrNull ??
        DanmakuSourceState(local.id, local.label, enabled: true);
    if (!sources.contains(source)) sources = [...sources, source];
    source
      ..enabled = true
      ..status = DanmakuStatus.ready
      ..count = comments.length;
    _merge();
  }

  Future<void> _load(
    String provider,
    Future<List<DanmakuComment>> Function() fetch, {
    String? save,
  }) async {
    final target = _target;
    if (target == null) return;
    final source = sources.firstWhere((source) => source.id == provider);
    final ticket = Object();
    _loads[provider] = ticket;
    _comments.remove(provider);
    source
      ..status = DanmakuStatus.loading
      ..count = 0
      ..error = null
      ..message = null
      ..candidates = const [];
    _merge();
    bool current() =>
        identical(_target, target) && identical(_loads[provider], ticket);
    try {
      final comments = await fetch();
      if (!current()) return;
      if (save != null && target.matchKey != null) {
        await repository.saveLocator(target.matchKey!, provider, save);
        if (!current()) return;
      }
      _comments[provider] = comments;
      source
        ..status = DanmakuStatus.ready
        ..count = comments.length;
    } on _NoMatch catch (e) {
      if (!current()) return;
      source
        ..status = DanmakuStatus.unmatched
        ..message = e.match.message
        ..candidates = e.match.candidates;
    } on DanmakuUnmatched catch (e) {
      if (!current()) return;
      source
        ..status = DanmakuStatus.unmatched
        ..message = e.message;
    } catch (e) {
      if (!current()) return;
      source
        ..status = DanmakuStatus.error
        ..error = e.toString();
    }
    _merge();
  }

  void enable(String provider, bool enabled) {
    sources.firstWhere((source) => source.id == provider).enabled = enabled;
    _merge();
    preferences.setProvider(provider, enabled);
  }

  /// Linear multiway merge of the enabled sources' sorted lists.
  void _merge() {
    final lists = [
      for (final source in sources)
        if (source.enabled) _comments[source.id] ?? const <DanmakuComment>[],
    ];
    final positions = List<int>.filled(lists.length, 0);
    final merged = <DanmakuComment>[];
    while (true) {
      var earliest = -1;
      for (var i = 0; i < lists.length; i++) {
        if (positions[i] >= lists[i].length) continue;
        if (earliest == -1 ||
            lists[i][positions[i]].time <
                lists[earliest][positions[earliest]].time) {
          earliest = i;
        }
      }
      if (earliest == -1) break;
      merged.add(lists[earliest][positions[earliest]++]);
    }
    comments = merged;
    _refresh();
  }

  void _refresh() {
    visible = preferences.visible(comments);
    notifyListeners();
  }

  @override
  void dispose() {
    preferences.removeListener(_refresh);
    super.dispose();
  }
}

class _NoMatch implements Exception {
  const _NoMatch(this.match);
  final DanmakuMatch match;
}

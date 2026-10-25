import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/error_message.dart';
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

  /// The loaded episode, where sent comments go.
  String? locator;

  /// The episode carried over from one picked for another episode.
  String? followed;

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

  /// Enabled sources' comments, merged by time, without copies one source
  /// took from another.
  List<DanmakuComment> comments = const [];

  /// How many copies merging dropped from [comments].
  int duplicates = 0;

  /// [comments] after preferences.
  List<DanmakuComment> visible = const [];
  final _comments = <String, List<DanmakuComment>>{};
  final _loads = <String, Object>{};

  /// Changes whenever [visible] changes, except by a sent comment, which
  /// the player places itself on [sent] without laying out the rest again.
  int revision = 0;
  final _sent = StreamController<DanmakuComment>.broadcast();
  Stream<DanmakuComment> get sent => _sent.stream;

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
  /// saved manual match, then the episode following one picked for another
  /// episode of the subject, then the provider's own matching.
  Future<void> autoMatch(double duration, {DanmakuTarget? target}) async {
    final current = _target;
    if (current == null || (target != null && !identical(target, current))) {
      return;
    }
    Future<DanmakuEpisode>? episode;
    final query = DanmakuQuery(
      episode: () => episode ??= repository.episode(current),
      episodeId: current.episodeId,
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
            Future<_Loaded> load(String locator, {String? followed}) async =>
                (locator, await provider.load(locator), followed);
            if (current.embedded case (final id, final locator)
                when id == source.id) {
              return load(locator);
            }
            final saved = current.matchKey == null
                ? null
                : await repository.savedLocator(current.matchKey!, source.id);
            if (saved != null) return load(saved);
            String? missed;
            if ((provider, current.subjectId) case (
              final DanmakuFollower follower,
              final subjectId?,
            )) {
              if (await repository.followed(subjectId, source.id)
                  case (final locator, final from)?) {
                final to = (await query.episode()).number;
                if (to == from) return load(locator);
                if (await follower.follow(locator, from, to) case final row?) {
                  return load(row.locator!, followed: row.title);
                }
                missed =
                    '之前为第 ${from % 1 == 0 ? from.toInt() : from} 集选的视频里'
                    '没有找到唯一的第 '
                    '${to % 1 == 0 ? to.toInt() : to} 集，请手动匹配';
              }
            }
            final match = await provider.match(query);
            if (match.locator case final locator?) return load(locator);
            throw _NoMatch(
              missed != null && match.candidates.isEmpty
                  ? DanmakuMatch.none(missed)
                  : match,
            );
          }),
    ]);
  }

  /// Loads a chosen locator and remembers it for this media and, by episode
  /// number, for the subject's other episodes to follow.
  Future<void> load(String provider, String locator) => _load(
    provider,
    () async =>
        (locator, await repository.provider(provider).load(locator), null),
    save: true,
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
    Future<_Loaded> Function() fetch, {
    bool save = false,
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
      ..locator = null
      ..followed = null
      ..error = null
      ..message = null
      ..candidates = const [];
    _merge();
    bool current() =>
        identical(_target, target) && identical(_loads[provider], ticket);
    try {
      final (locator, comments, followed) = await fetch();
      if (!current()) return;
      if (save) {
        if (target.matchKey != null) {
          await repository.saveLocator(target.matchKey!, provider, locator);
        }
        await _saveFollowed(target, provider, locator);
        if (!current()) return;
      }
      _comments[provider] = comments;
      source
        ..status = DanmakuStatus.ready
        ..count = comments.length
        ..locator = locator
        ..followed = followed;
      if (repository.provider(provider) case final DanmakuSender sender) {
        unawaited(_refreshQuota(sender));
      }
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
        ..error = errorMessage(e);
    }
    _merge();
  }

  Future<void> _saveFollowed(
    DanmakuTarget target,
    String provider,
    String locator,
  ) async {
    final subjectId = target.subjectId;
    if (subjectId == null ||
        repository.provider(provider) is! DanmakuFollower) {
      return;
    }
    final DanmakuEpisode episode;
    try {
      episode = await repository.episode(target);
    } on DanmakuUnmatched {
      return; // No episode number for others to follow from.
    }
    await repository.saveFollowed(subjectId, provider, locator, episode.number);
  }

  /// Whether any source takes comments.
  bool get sendable =>
      repository.matchers.any((provider) => provider is DanmakuSender);

  /// What the viewer may still send, once known.
  DanmakuQuota? quota;

  /// The next comment may go from then on.
  DateTime? sendAfter;

  /// The source comments are sent to: an enabled source, loaded for this
  /// episode, whose provider takes them now.
  DanmakuSourceState? get sendSource => sources
      .where(
        (source) =>
            source.enabled &&
            source.locator != null &&
            source.status == DanmakuStatus.ready &&
            switch (repository.provider(source.id)) {
              DanmakuSender(:final unavailable) => unavailable == null,
              _ => false,
            },
      )
      .firstOrNull;

  /// Why nothing can be sent now; null when [sendSource] can take a
  /// comment. Waiting between comments does not block.
  String? get sendBlocked {
    if (_target == null) return '播放视频后发送弹幕';
    final senders = [
      for (final source in sources)
        if (repository.provider(source.id) is DanmakuSender) source,
    ];
    if (senders.isEmpty) return '暂不能发送弹幕';
    final sender = senders.first;
    if ((repository.provider(sender.id) as DanmakuSender).unavailable
        case final reason?) {
      return reason;
    }
    if (quota case DanmakuQuota(:final limit, remaining: <= 0)) {
      return '为防滥用，每天最多发送 $limit 条弹幕';
    }
    if (sendSource != null) return null;
    if (!sender.enabled) return '${sender.label} 弹幕已关闭';
    if (sender.status == DanmakuStatus.loading) {
      return '正在加载${sender.label} 弹幕…';
    }
    return sender.status == DanmakuStatus.error
        ? '${sender.label} 弹幕加载失败'
        : '本集没有关联 Bangumi 章节，无法发送';
  }

  Future<void> _refreshQuota(DanmakuSender sender) async {
    if (sender.unavailable != null) return;
    try {
      _applyQuota(await sender.quota());
      notifyListeners();
    } catch (_) {
      // Sending reports the limit itself.
    }
  }

  void _applyQuota(DanmakuQuota value) {
    quota = value;
    sendAfter = DateTime.now().add(value.wait);
  }

  /// Sends [text] at [time] in the saved look and shows it at once, framed
  /// as the viewer's own.
  Future<void> send(double time, String text) async {
    final target = _target;
    final source = sendSource;
    final blocked = sendBlocked;
    if (target == null || source == null || blocked != null) {
      throw StateError(blocked ?? '暂不能发送弹幕');
    }
    final comment = DanmakuComment(
      time,
      text.trim(),
      source: source.id,
      mode: preferences.sendStyle.value.mode,
      color: preferences.sendStyle.value.color,
      own: true,
    );
    final sender = repository.provider(source.id) as DanmakuSender;
    try {
      _applyQuota(await sender.send(source.locator!, comment));
    } on DanmakuSendRejected catch (e) {
      if (e.quota case final value?) _applyQuota(value);
      notifyListeners();
      throw StateError(e.message);
    }
    if (!identical(_target, target)) {
      notifyListeners();
      return;
    }
    final list = [...?_comments[source.id]];
    var index = list.length;
    while (index > 0 && list[index - 1].time > time) {
      index--;
    }
    _comments[source.id] = list..insert(index, comment);
    source.count++;
    _merge(sent: comment);
  }

  /// Whether new sessions load [provider]; the current session follows.
  void setDefault(String provider, bool enabled) {
    preferences.setProvider(provider, enabled);
    final source = sources.where((source) => source.id == provider);
    if (source.firstOrNull case final source? when source.enabled != enabled) {
      source.enabled = enabled;
      _merge();
    } else {
      notifyListeners();
    }
  }

  /// Reads what the viewer may still send, for the data sources page.
  Future<void> refreshQuota() async {
    for (final provider in repository.matchers) {
      if (provider case final DanmakuSender sender) {
        await _refreshQuota(sender);
      }
    }
  }

  void enable(String provider, bool enabled) {
    sources.firstWhere((source) => source.id == provider).enabled = enabled;
    _merge();
    preferences.setProvider(provider, enabled);
  }

  /// Linear multiway merge of the enabled sources' sorted lists. A comment
  /// with the same text as one from another source within [copyWindow]
  /// seconds is a synced copy and dropped.
  void _merge({DanmakuComment? sent}) {
    final lists = [
      for (final source in sources)
        if (source.enabled) _comments[source.id] ?? const <DanmakuComment>[],
    ];
    final positions = List<int>.filled(lists.length, 0);
    final merged = <DanmakuComment>[];
    // Text → kept comments with it in the last [copyWindow] seconds.
    final recent = <String, List<DanmakuComment>>{};
    var dropped = 0;
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
      final item = lists[earliest][positions[earliest]++];
      if (!item.own) {
        final kept = (recent[item.text] ??= [])
          ..removeWhere((other) => item.time - other.time > copyWindow);
        if (kept.any((other) => other.source != item.source)) {
          dropped++;
          continue;
        }
        kept.add(item);
      }
      merged.add(item);
    }
    comments = merged;
    duplicates = dropped;
    _refresh(sent: sent);
  }

  /// Sources store times at different precision (Bahamut in tenths), so a
  /// copy lands up to this far from its original.
  static const copyWindow = .5;

  void _refresh({DanmakuComment? sent}) {
    visible = preferences.visible(comments);
    if (sent == null) {
      revision++;
    } else {
      _sent.add(sent);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    preferences.removeListener(_refresh);
    unawaited(_sent.close());
    super.dispose();
  }
}

/// A load's locator, comments and, when carried over, the episode's title.
typedef _Loaded = (String, List<DanmakuComment>, String?);

class _NoMatch implements Exception {
  const _NoMatch(this.match);
  final DanmakuMatch match;
}

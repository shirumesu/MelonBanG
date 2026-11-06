import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/error_message.dart';
import '../../core/network.dart';
import '../../core/store.dart';
import '../../domain/catalog.dart';
import '../../domain/episode_release.dart';
import '../../domain/release_traits.dart';
import '../../domain/sources.dart';
import '../../domain/transfer.dart';
import '../acquisition/release_search.dart';
import '../acquisition/resource_metadata.dart';
import '../acquisition/title_matching.dart';
import '../downloads/download_repository.dart';
import '../playback/playback_library.dart';
import '../tracking/tracking_repository.dart';
import 'subscription.dart';
import 'subscription_matcher.dart';
import 'subscription_preferences.dart';

export 'subscription.dart';
export 'subscription_preferences.dart';

/// Main [episodes] in a few words: `第 1–4 话`, `第 1、3 话` or `7 话`.
String episodeRange(List<Episode> episodes) {
  final numbers = [for (final episode in episodes) episode.number];
  final sorts = [for (final episode in episodes) episode.sort];
  final runs = [
    for (var i = 1; i < sorts.length; i++) sorts[i] - sorts[i - 1] == 1,
  ];
  return switch (numbers) {
    [] => '',
    [final only] => '第 $only 话',
    [final first, ..., final last] when runs.every((run) => run) =>
      '第 $first–$last 话',
    _ when numbers.length <= 4 => '第 ${numbers.join('、')} 话',
    _ => '${numbers.length} 话',
  };
}

/// Something about a subscription the user has to act on.
class SubscriptionIssue {
  const SubscriptionIssue(this.text, {this.episode, this.late});

  /// The whole story, such as why checking failed.
  final String text;

  /// The episode no matching release came out for.
  final Episode? episode;

  /// How long [episode] has waited, as 等字幕组 26 小时.
  final String? late;
}

/// The shows followed as they air: checks the release sites for new
/// episodes, caches the first release of each that meets a subscription's
/// filter and keeps its book. Checks come often right after an episode
/// airs and seldom later; nothing is checked before an episode airs.
class SubscriptionController extends ChangeNotifier {
  SubscriptionController({
    required this.store,
    required this.catalog,
    required this.releases,
    required this.downloads,
    required this.tracking,
    required this.library,
    required this.preferences,
    required this.preferredGroups,
  });
  final AppStore store;
  final Catalog catalog;
  final ReleaseSearch releases;
  final DownloadRepository downloads;
  final TrackingRepository tracking;
  final PlaybackLibrary library;
  final SubscriptionPreferences preferences;

  /// The preferred groups of the settings, as they stand.
  final List<String> Function() preferredGroups;

  /// Announces an episode once its cache finishes.
  void Function(Subscription subscription, Episode? episode)? onCached;

  /// Announces a subscription ending by itself, and why.
  void Function(Subscription subscription, String reason)? onEnded;

  static const _scope = 'subscriptions';

  /// By subject id.
  final subscriptions = <int, Subscription>{};

  /// Subjects being checked now.
  final _checking = <int>{};

  /// Each show's broadcasts in the coming week's schedule.
  Map<int, List<DateTime>> airings = {};
  final _details = <int, Subject>{};

  /// Subscriptions to check at once, before their turn.
  final _soon = <int>{};
  DateTime? _scheduledAt, _ticked, _watchedAt;
  Timer? _timer;
  StreamSubscription<TransferSnapshot>? _downloadChanges;
  bool _pumping = false, _closed = false, _started = false;

  /// Whether any subscription still waits for episodes.
  bool get active => subscriptions.values.any(
    (subscription) => subscription.finishedAt == null,
  );

  Future<void> start() async {
    for (final row in await store.list(_scope)) {
      final subscription = Subscription.fromJson(row);
      subscriptions[subscription.subjectId] = subscription;
    }
    _started = true;
    notifyListeners();
    _downloadChanges = downloads.changes.stream.listen(_downloadsChanged);
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
    // Launching counts as waking: everything due is checked now.
    _soon.addAll(subscriptions.keys);
    unawaited(_refreshSchedule().whenComplete(_tick));
  }

  /// Checks every subscription now.
  void checkNow() {
    _soon.addAll(subscriptions.keys);
    unawaited(_pump());
  }

  /// The detail with episodes of [id], loaded once an hour.
  Future<Subject> detail(int id) async {
    final subject = await catalog.subject(id, forPlayback: true);
    _details[id] = subject;
    return subject;
  }

  List<DateTime> airingsOf(int id) => airings[id] ?? const [];

  /// When [episode] airs. The schedule covers one week and a show keeps
  /// its weekly slot, so the slot is carried to the weeks around it, back
  /// over a season for the episodes aired; a skipped week then still finds
  /// its hour.
  Release? releaseOf(Episode episode) => episodeRelease(episode, [
    for (final at in airingsOf(episode.subjectId))
      for (var week = -13; week <= 4; week++) at.add(Duration(days: 7 * week)),
  ]);

  /// When [episode] aired, where the schedule gives the hour.
  DateTime? airedAt(Episode episode) => switch (releaseOf(episode)) {
    (:final at, timed: true) => at,
    _ => null,
  };

  Future<void> _refreshSchedule() async {
    try {
      final calendar = await catalog.calendar();
      airings = {};
      for (final day in calendar) {
        for (final item in day.items) {
          if (item.airingAt case final at?) {
            (airings[item.id] ??= []).add(at);
          }
        }
      }
      _scheduledAt = DateTime.now();
    } catch (_) {
      // Without the schedule, episodes are timed by their air dates alone.
    }
  }

  void _tick() {
    if (_closed) return;
    final now = DateTime.now();
    final last = _ticked;
    _ticked = now;
    // A minute timer that fired much later means the computer slept.
    if (last != null && now.difference(last) > const Duration(minutes: 3)) {
      _soon.addAll(subscriptions.keys);
    }
    if (_watchedAt == null ||
        now.difference(_watchedAt!) > const Duration(hours: 1)) {
      _watchedAt = now;
      unawaited(_endUnwatched());
    }
    if (_scheduledAt == null ||
        now.difference(_scheduledAt!) > const Duration(hours: 1)) {
      unawaited(_refreshSchedule());
    }
    unawaited(_pump());
  }

  /// Checks the subscriptions that are due one after another, half a minute
  /// apart so the sites are not asked for every show at once.
  Future<void> _pump() async {
    if (_pumping || _closed || !_started) return;
    _pumping = true;
    try {
      while (!_closed) {
        final now = DateTime.now();
        final due = <(Subscription, DateTime)>[
          for (final subscription in subscriptions.values)
            if (subscription.finishedAt == null)
              if (_soon.contains(subscription.subjectId))
                (subscription, DateTime(0))
              else if (_nextCheck(subscription) case final at?
                  when !at.isAfter(now))
                (subscription, at),
        ]..sort((a, b) => a.$2.compareTo(b.$2));
        if (due.isEmpty) break;
        final subscription = due.first.$1;
        _soon.remove(subscription.subjectId);
        await check(subscription.subjectId);
        if (due.length > 1) await Future.delayed(const Duration(seconds: 30));
      }
    } finally {
      _pumping = false;
    }
  }

  /// When [subscription] is checked next: at an episode's broadcast, every
  /// 10 minutes for 6 hours after it, every 30 minutes until 3 days after
  /// it, then every 6 hours; hourly when the schedule gives no hour. Failed
  /// checks wait 5 minutes, 15 minutes, then an hour.
  DateTime? _nextCheck(Subscription subscription) {
    if (subscription.finishedAt != null) return null;
    final checked = subscription.checkedAt;
    final backoff = switch (subscription.failures) {
      0 => Duration.zero,
      1 => const Duration(minutes: 5),
      2 => const Duration(minutes: 15),
      _ => const Duration(hours: 1),
    };
    final subject = _details[subscription.subjectId];
    if (subject == null) {
      return checked?.add(
        backoff > const Duration(minutes: 10)
            ? backoff
            : const Duration(minutes: 10),
      );
    }
    final now = DateTime.now();
    final waiting = _pendingEpisodes(subscription, subject);
    if (waiting.isEmpty) {
      // Bangumi has yet to list the next episode; look again now and then.
      return (checked ?? DateTime(0)).add(const Duration(hours: 6));
    }
    final aired = [
      for (final episode in waiting)
        if (releaseOf(episode) case final release?
            when !release.at.isAfter(now))
          release,
    ]..sort((a, b) => a.at.compareTo(b.at));
    if (aired.isEmpty) {
      final next = waiting
          .map((episode) => releaseOf(episode)?.at)
          .nonNulls
          .fold<DateTime?>(
            null,
            (soonest, at) =>
                soonest == null || at.isBefore(soonest) ? at : soonest,
          );
      return next ?? (checked ?? DateTime(0)).add(const Duration(hours: 1));
    }
    final latest = aired.last;
    final age = now.difference(latest.at);
    var interval = !latest.timed
        ? const Duration(hours: 1)
        : age < const Duration(hours: 6)
        ? const Duration(minutes: 10)
        : age < const Duration(hours: 72)
        ? const Duration(minutes: 30)
        : const Duration(hours: 6);
    if (backoff > interval) interval = backoff;
    if (checked == null || checked.isBefore(latest.at)) return latest.at;
    return checked.add(interval);
  }

  /// Whether [subscription] caches [episode]: a main episode airing from
  /// the day before it was made, or chosen among the [earlier] ones.
  bool _wanted(Subscription subscription, Subject subject, Episode episode) =>
      episode.main &&
      (subscription.earlier.contains(episode.id) ||
          _since(subscription.createdAt, subject, episode));

  /// Whether [episode] airs from the day before [at], or without an air
  /// date is listed after those before.
  bool _since(DateTime at, Subject subject, Episode episode) {
    final start = at.subtract(const Duration(days: 1));
    final day = DateTime(start.year, start.month, start.day);
    bool before(Release release) => release.timed
        ? release.at.isBefore(start)
        : DateTime(
            release.at.year,
            release.at.month,
            release.at.day,
          ).isBefore(day);
    if (releaseOf(episode) case final release?) return !before(release);
    final index = subject.episodes.indexOf(episode);
    final last = subject.episodes.lastIndexWhere((other) {
      final release = releaseOf(other);
      return release != null && before(release);
    });
    return index > last;
  }

  /// Episodes of [subject] with a cache: by a subscription or by hand,
  /// finished or not.
  Set<int> _held(Subscription? subscription, Subject subject) => {
    ...?subscription?.ledger.keys,
    ..._cachesOf(subject).keys,
  };

  /// The cache task of each episode of [subject], a finished one first.
  Map<int, DownloadTask> _cachesOf(Subject subject) {
    final found = <int, DownloadTask>{};
    for (final task in downloads.snapshot().forSubject(subject.id)) {
      for (final id in {?task.episodeId, ...episodeFiles(subject, task).keys}) {
        if (found[id] == null || (!found[id]!.complete && task.complete)) {
          found[id] = task;
        }
      }
    }
    return found;
  }

  /// Wanted episodes without a cache, in broadcast order.
  List<Episode> _pendingEpisodes(Subscription subscription, Subject subject) {
    final have = _held(subscription, subject);
    return [
      for (final episode in subject.episodes)
        if (!have.contains(episode.id) &&
            _wanted(subscription, subject, episode))
          episode,
    ];
  }

  /// The next episode [subscription] waits for, and when it airs, while the
  /// show's episodes are known; earlier episodes it also caches are left.
  (Episode, Release?)? nextOf(Subscription subscription) {
    final subject = _details[subscription.subjectId];
    if (subject == null || subscription.finishedAt != null) return null;
    final next = _pendingEpisodes(subscription, subject)
        .where((episode) => !subscription.earlier.contains(episode.id))
        .firstOrNull;
    return next == null ? null : (next, releaseOf(next));
  }

  /// Main episodes of [subject] that aired before its subscription, or
  /// before one made now, and that it could cache too: without a cache,
  /// not watched and not chosen already.
  List<Episode> earlierEpisodes(Subject subject) {
    final subscription = subscriptions[subject.id];
    final held = _held(subscription, subject);
    final now = DateTime.now();
    return [
      for (final episode in subject.episodes)
        if (episode.main &&
            !episode.watched &&
            !held.contains(episode.id) &&
            !(subscription?.earlier.contains(episode.id) ?? false) &&
            !_since(subscription?.createdAt ?? now, subject, episode) &&
            !(releaseOf(episode)?.at.isAfter(now) ?? true))
          episode,
    ];
  }

  /// What [subscription] needs from the user: a failure, or an episode no
  /// matching release came out for a day after it aired.
  SubscriptionIssue? issueOf(Subscription subscription) {
    if (subscription.finishedAt != null) return null;
    if (subscription.issue case final issue?) return SubscriptionIssue(issue);
    final subject = _details[subscription.subjectId];
    if (subject == null) return null;
    final now = DateTime.now();
    final since = subscription.createdAt.subtract(const Duration(days: 1));
    for (final episode in _pendingEpisodes(subscription, subject)) {
      final release = releaseOf(episode);
      if (release == null || release.at.isBefore(since)) continue;
      final late = release.at.add(Duration(hours: release.timed ? 24 : 48));
      if (now.isBefore(late)) continue;
      if (subscription.waiting[episode.id]?.isAfter(now) ?? false) continue;
      final hours = now.difference(release.at).inHours;
      return SubscriptionIssue(
        '${episode.label}播出 $hours 小时了，还没有符合筛选的文件',
        episode: episode,
        late: '等字幕组 $hours 小时',
      );
    }
    return null;
  }

  /// Subscriptions needing the user.
  int get attention => subscriptions.values
      .where((subscription) => issueOf(subscription) != null)
      .length;

  /// Searches [subscription]'s show once and caches what it judges new.
  Future<void> check(int id) async {
    final subscription = subscriptions[id];
    if (subscription == null || !_checking.add(id)) return;
    notifyListeners();
    try {
      // Restored tasks tell which episodes are cached already.
      await downloads.ready;
      final subject = await detail(id);
      final result = await _search(subject);
      if (result.sources.isEmpty) {
        throw StateError('没有可用的 BT 资源站，去数据源页启用一个');
      }
      if (result.sources.every(
        (source) => source.status == SearchStatus.error,
      )) {
        throw StateError('资源站都没有响应，稍后会再试');
      }
      subscription.failures = 0;
      subscription.issue = null;
      await _apply(subscription, subject, result.candidates);
    } catch (e) {
      subscription.failures++;
      // A site down for a while is common; three failures in a row show.
      if (subscription.failures >= 3) {
        subscription.issue = '检查更新失败：${errorMessage(e)}';
      }
    } finally {
      subscription.checkedAt = DateTime.now();
      _checking.remove(id);
      if (subscriptions[id] == subscription) await _save(subscription);
      notifyListeners();
    }
  }

  Future<void> _apply(
    Subscription subscription,
    Subject subject,
    List<ReleaseCandidate> candidates,
  ) async {
    final revisions = preferences.revisions;
    final groups = preferredGroups();
    var replaceable = <int, String>{};
    if (revisions == RevisionPolicy.replaceUnwatched) {
      try {
        final progress = await tracking.withProgress(subject);
        replaceable = {
          for (final episode in progress.episodes)
            if (!episode.watched)
              if (subscription.ledger[episode.id] case final entry?
                  when !entry.revision && entry.taskId != null)
                episode.id: entry.title,
        };
      } catch (_) {
        // Without watch progress, nothing counts as unwatched.
      }
    }
    final judged = judgeReleases(
      subject: subject,
      filter: subscription.filter,
      preferredGroups: groups,
      aired: airedAt,
      candidates: candidates,
      wanted: (episode) => _wanted(subscription, subject, episode),
      revisions: revisions,
      held: _held(subscription, subject),
      replaceable: replaceable,
      known: {for (final entry in subscription.ledger.values) entry.identity},
    );
    for (final judgement in judged) {
      final episode = judgement.episode;
      if (judgement.download && episode != null) {
        final previous = subscription.ledger[episode.id];
        try {
          final task = await releases.enqueue(
            judgement.candidate,
            method: preferences.method,
            episodeId: episode.id,
          );
          final title = judgement.candidate.release.title;
          subscription.ledger[episode.id] = LedgerEntry(
            identity: judgement.identity,
            title: title,
            at: DateTime.now(),
            taskId: task.id,
            replaces: judgement.replaces ? previous?.taskId : null,
            revision: releaseRevision(title),
          );
          subscription.judged(judgement.identity);
          subscription.note(
            '${judgement.replaces ? '换成修正版' : '开始缓存'}${episode.label}：$title',
            kind: SubscriptionEventKind.started,
          );
        } catch (e) {
          subscription.issue = '${episode.label}没能开始缓存：${errorMessage(e)}';
          subscription.note(
            subscription.issue!,
            kind: SubscriptionEventKind.failed,
          );
        }
        continue;
      }
      if (!judgement.ours || !subscription.judged(judgement.identity)) continue;
      // Releases of episodes before the subscription go unmentioned, and so
      // do other groups' files when any group counts.
      if (subscription.filter.anyGroup &&
          const [
            Verdict.filtered,
            Verdict.duplicate,
          ].contains(judgement.verdict)) {
        continue;
      }
      final relevant = episode == null
          ? (releasePublished(judgement.candidate.release.publishedAt)
                    ?.isAfter(subscription.createdAt) ??
                false)
          : _wanted(subscription, subject, episode);
      if (relevant) {
        subscription.note(
          '跳过 ${judgement.candidate.release.title}：${judgement.reason}',
          kind: SubscriptionEventKind.skipped,
        );
      }
    }
    _checkFinished(subscription, subject);
  }

  /// Marks [subscription] finished once every episode has aired and is
  /// cached, and ends it when the settings say so. Shows without a known
  /// episode count never finish.
  void _checkFinished(Subscription subscription, Subject subject) {
    if (subscription.finishedAt != null) return;
    final total = subject.episodeTotal ?? 0;
    final main = subject.episodes.where((episode) => episode.main).toList();
    if (total == 0 || main.length < total) return;
    final now = DateTime.now();
    if (main.any((episode) => releaseOf(episode)?.at.isAfter(now) ?? true)) {
      return;
    }
    if (_pendingEpisodes(subscription, subject).isNotEmpty) return;
    final caches = _cachesOf(subject);
    for (final episode in main) {
      if (_wanted(subscription, subject, episode) &&
          !(caches[episode.id]?.complete ?? false)) {
        return;
      }
    }
    subscription.finishedAt = now;
    subscription.note('已完结，剧集都缓存好了');
    if (preferences.autoUnsubscribe == AutoUnsubscribe.finished) {
      unawaited(_end(subscription, '已完结，剧集都缓存好了'));
    }
  }

  /// Ends the subscriptions of shows not played for three weeks, or those
  /// already finished, when the settings say so; a subscription younger
  /// than three weeks is left.
  Future<void> _endUnwatched() async {
    // Those finished while the settings kept them end once they no longer do.
    if (preferences.autoUnsubscribe == AutoUnsubscribe.finished) {
      for (final subscription in subscriptions.values.toList()) {
        if (subscription.finishedAt != null) {
          await _end(subscription, '已完结，剧集都缓存好了');
        }
      }
      return;
    }
    if (preferences.autoUnsubscribe != AutoUnsubscribe.unwatched) return;
    final Map<int, DateTime> played;
    try {
      played = await library.playedSubjects();
    } catch (_) {
      return;
    }
    final limit = DateTime.now().subtract(const Duration(days: 21));
    for (final subscription in subscriptions.values.toList()) {
      final last = played[subscription.subjectId];
      if (subscription.createdAt.isBefore(limit) &&
          (last == null || last.isBefore(limit))) {
        await _end(subscription, '超过三周没有观看');
      }
    }
  }

  Future<void> _end(Subscription subscription, String reason) async {
    await unsubscribe(subscription.subjectId);
    onEnded?.call(subscription, reason);
  }

  void _downloadsChanged(TransferSnapshot snapshot) {
    var any = false;
    for (final subscription in subscriptions.values.toList()) {
      var changed = false;
      for (final MapEntry(key: id, value: entry)
          in subscription.ledger.entries) {
        if (entry.notified || entry.taskId == null) continue;
        final task = snapshot.task(entry.taskId!);
        if (task == null || !task.complete) continue;
        entry.notified = true;
        changed = true;
        final episode = _details[subscription.subjectId]?.episode(id);
        subscription.note(
          '${episode?.label ?? '一集'}缓存好了',
          kind: SubscriptionEventKind.cached,
        );
        onCached?.call(subscription, episode);
        if (entry.replaces case final old? when snapshot.task(old) != null) {
          unawaited(downloads.remove(old).catchError((Object _) {}));
          subscription.note('删掉了${episode?.label ?? '这一集'}被修正版替换的旧文件');
        }
      }
      if (!changed) continue;
      any = true;
      if (_details[subscription.subjectId] case final subject?) {
        _checkFinished(subscription, subject);
      }
      // One finished and ended stays gone.
      if (subscriptions[subscription.subjectId] == subscription) {
        unawaited(_save(subscription));
      }
    }
    if (any) notifyListeners();
  }

  /// Subscribes to [subject] with [filter], or changes its subscription
  /// to it, keeping what it cached; the next subscription starts from the
  /// same filter. [earlier] episodes, of [earlierEpisodes], are cached too;
  /// null when none were offered. With [markWatching] the show is also
  /// marked 在看 on Bangumi.
  Future<void> subscribe(
    Subject subject,
    SubscriptionFilter filter, {
    List<Episode>? earlier,
    bool markWatching = false,
  }) async {
    if (markWatching) {
      await tracking.setCollection(
        subject.id,
        const CollectionChange(status: CollectionStatus.watching),
      );
    }
    final existing = subscriptions[subject.id];
    if (existing == null && earlier != null) {
      await preferences.setCacheEarlier(earlier.isNotEmpty);
    }
    if (existing != null && earlier != null && earlier.isNotEmpty) {
      existing.earlier.addAll(earlier.map((episode) => episode.id));
      existing.note('补缓存已播出的${episodeRange(earlier)}');
      if (existing.filter == filter) {
        await _save(existing);
        notifyListeners();
        _soon.add(subject.id);
        unawaited(_pump());
        return;
      }
    }
    if (existing != null && existing.filter == filter) return;
    final subscription =
        existing ??
        Subscription(
          subjectId: subject.id,
          title: subject.title,
          coverUrl: subject.coverUrl,
          filter: filter,
          createdAt: DateTime.now(),
        );
    subscription
      ..filter = filter
      ..issue = null
      ..failures = 0;
    // Releases judged by another filter are judged again.
    subscription.seen.clear();
    subscription.waiting.clear();
    subscription.note('${existing == null ? '订阅' : '改为'} ${filter.label}');
    if (existing == null && earlier != null && earlier.isNotEmpty) {
      subscription.earlier.addAll(earlier.map((episode) => episode.id));
      subscription.note('同时缓存已播出的${episodeRange(earlier)}');
    }
    subscriptions[subject.id] = subscription;
    _details[subject.id] = subject;
    await _save(subscription);
    await preferences.setDefaultFilter(filter);
    notifyListeners();
    _soon.add(subject.id);
    unawaited(_pump());
  }

  /// Keeps waiting a day more for [episode] of [id].
  Future<void> keepWaiting(int id, Episode episode) async {
    final subscription = subscriptions[id];
    if (subscription == null) return;
    subscription.waiting[episode.id] = DateTime.now().add(
      const Duration(hours: 24),
    );
    subscription.note('继续等${episode.label}，明天再提醒');
    await _save(subscription);
    notifyListeners();
  }

  /// Clears a failure the user has seen; the next check tries again.
  Future<void> retry(int id) async {
    final subscription = subscriptions[id];
    if (subscription == null) return;
    subscription
      ..issue = null
      ..failures = 0;
    await _save(subscription);
    notifyListeners();
    _soon.add(id);
    unawaited(_pump());
  }

  /// Ends the subscription of [id]; what it cached stays.
  Future<void> unsubscribe(int id) async {
    if (subscriptions.remove(id) == null) return;
    _soon.remove(id);
    await store.remove(_scope, '$id');
    notifyListeners();
  }

  /// Every release the BT sites list for [subject], as a check would find
  /// them, for choosing a filter.
  Future<ReleaseSearchResult> browse(
    Subject subject, {
    void Function(ReleaseSearchResult)? onUpdate,
    RequestCancellation? cancel,
  }) => _search(subject, onUpdate: onUpdate, cancel: cancel);

  /// The BT sites' releases of [subject], searched by every catalogue name
  /// as 查找资源 searches the whole show.
  Future<ReleaseSearchResult> _search(
    Subject subject, {
    void Function(ReleaseSearchResult)? onUpdate,
    RequestCancellation? cancel,
  }) => releases.search(
    subject.id,
    ResourceTerms.of(subject, null),
    coverUrl: subject.coverUrl,
    onUpdate: onUpdate,
    cancel: cancel,
  );

  Future<void> _save(Subscription subscription) =>
      store.put(_scope, '${subscription.subjectId}', subscription.toJson());

  Future<void> close() async {
    _closed = true;
    _timer?.cancel();
    await _downloadChanges?.cancel();
  }
}

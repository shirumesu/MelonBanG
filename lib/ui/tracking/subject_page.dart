import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/error_message.dart';
import '../../domain/collection_edit.dart';
import '../../domain/catalog.dart';
import '../../features/playback/playback_library.dart';
import '../../features/playback/resume_controller.dart';
import '../../features/tracking/subject_controller.dart';
import '../../features/tracking/tracking_controller.dart';
import '../core/action_feedback.dart';
import '../core/external_link.dart';
import '../core/motion.dart';
import '../core/page_widgets.dart';
import '../core/selection_controls.dart';
import '../core/subject_posters.dart';
import '../core/theme.dart';
import 'collection_editor.dart';
import 'collection_labels.dart';
import 'episode_grid.dart';
import 'subject_community.dart';
import 'subject_people.dart';

/// Content width at which the collection and statistics cards sit in a
/// right column beside the main panel.
const _wideLayout = 860.0;

class SubjectPage extends StatelessWidget {
  const SubjectPage({
    super.key,
    required this.subjects,
    required this.personal,
    required this.resume,
    required this.airings,
    required this.community,
    required this.onFindResources,
    required this.onPlayEpisode,
    required this.onOpenEpisode,
    required this.onOpenSubject,
    required this.onError,
  });
  final SubjectController subjects;
  final TrackingController personal;
  final ResumeController resume;

  /// The subject's broadcasts in the coming week's schedule.
  final List<DateTime> airings;
  final SubjectCommunitySource community;
  final ValueChanged<Episode?> onFindResources;
  final ValueChanged<Episode> onPlayEpisode;

  /// An episode cell clicked: plays its cache, or lets the user pick a source.
  final ValueChanged<Episode> onOpenEpisode;
  final ValueChanged<Subject> onOpenSubject;
  final ValueChanged<Object> onError;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([subjects, personal, resume]),
    builder: (context, _) {
      final subject = subjects.subject;
      return _SubjectDetail(
        subject: subject,
        loading: subjects.loading,
        signedIn: personal.signedIn,
        community: community,
        collectionSyncError: personal.lastSyncError,
        onRetryCollectionSync: personal.flush,
        resume: resume.resumeOf(subject?.id),
        airings: airings,
        cachedEpisodeIds: resume.playableOf(subject?.id),
        onSaveCollection: (change) async {
          await subjects.saveCollection(change);
          unawaited(subjects.reload().catchError(onError));
        },
        onSaveEpisodes: (ids, status) async {
          await subjects.saveEpisodes(ids, status);
          unawaited(subjects.reload().catchError(onError));
        },
        onFindResources: onFindResources,
        onPlayEpisode: onPlayEpisode,
        onOpenEpisode: onOpenEpisode,
        onOpenSubject: onOpenSubject,
        onRetry: () => unawaited(subjects.open(subject!).catchError(onError)),
      );
    },
  );
}

class _SubjectDetail extends StatefulWidget {
  const _SubjectDetail({
    required this.subject,
    required this.community,
    required this.onSaveCollection,
    required this.onSaveEpisodes,
    required this.onFindResources,
    required this.onPlayEpisode,
    required this.onOpenEpisode,
    required this.onOpenSubject,
    required this.onRetry,
    this.resume,
    this.airings = const [],
    this.cachedEpisodeIds,
    this.loading = false,
    this.signedIn = false,
    this.collectionSyncError,
    this.onRetryCollectionSync,
  });
  final Subject? subject;
  final List<DateTime> airings;
  final bool loading;
  final bool signedIn;
  final SubjectCommunitySource community;
  final String? collectionSyncError;
  final Future<void> Function()? onRetryCollectionSync;
  final PlaybackResume? resume;
  final Set<int>? cachedEpisodeIds;
  final Future<void> Function(CollectionChange) onSaveCollection;
  final Future<void> Function(List<int>, EpisodeStatus) onSaveEpisodes;
  final ValueChanged<Episode?> onFindResources;
  final ValueChanged<Episode> onPlayEpisode, onOpenEpisode;
  final ValueChanged<Subject> onOpenSubject;

  /// Loads the parts that failed again.
  final VoidCallback onRetry;
  @override
  State<_SubjectDetail> createState() => _SubjectDetailState();
}

class _SubjectDetailState extends State<_SubjectDetail> {
  CollectionStatus? _selectedStatus;
  String? _feedback, _collectionError, _nudge;

  /// Fields that restore the collection before the last quick edit.
  CollectionChange? _undo;

  /// Unwatched main episodes offered for completion after choosing 看过.
  int _completeOffer = 0;
  int _nudges = 0;
  bool _savingCollection = false;
  bool _summaryExpanded = false, _infoExpanded = false;
  Timer? _feedbackTimer;
  final _episodeOverrides = <int, EpisodeStatus>{};
  String? _episodeError;
  Episode? _hoverEpisode;
  final _collectionIssue = ActionFeedback();

  @override
  void initState() {
    super.initState();
    _collectionIssue.issue = widget.collectionSyncError;
  }

  bool _loadingPart(String part) {
    if (!widget.loading) return false;
    final pending = widget.subject?.pending;
    return pending == null
        ? widget.subject?.detailed != true
        : pending.contains(part);
  }

  bool _failedPart(String part) =>
      !widget.loading && widget.subject?.pending?.contains(part) == true;

  bool get _episodesLoading =>
      _loadingPart('episodes') && (widget.subject?.episodes.isEmpty ?? true);

  SubjectCollection get _collection {
    final saved = widget.subject?.collection ?? const SubjectCollection();
    return SubjectCollection(
      status: _selectedStatus ?? saved.status,
      score: saved.score,
      tags: saved.tags,
      comment: saved.comment,
    );
  }

  CollectionStatus? get _status => _collection.status;

  String get _draftKey =>
      CollectionDrafts.key(widget.community.userId, widget.subject?.id);

  @override
  void didUpdateWidget(covariant _SubjectDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.collectionSyncError != oldWidget.collectionSyncError) {
      _collectionIssue.issue = widget.collectionSyncError;
    }
    if (oldWidget.subject?.id != widget.subject?.id) {
      _feedbackTimer?.cancel();
      _selectedStatus = _feedback = _collectionError = _nudge = null;
      _undo = _hoverEpisode = null;
      _episodeError = null;
      _completeOffer = 0;
      _savingCollection = _summaryExpanded = _infoExpanded = false;
      _episodeOverrides.clear();
    } else if (!_savingCollection &&
        oldWidget.subject?.status != widget.subject?.status) {
      _selectedStatus = null;
    }
  }

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    _releaseTimer?.cancel();
    _collectionIssue.dispose();
    super.dispose();
  }

  DateTime? _releaseAt;
  Timer? _releaseTimer;

  /// Rebuilds when the next episode airs, so it becomes playable.
  void _rebuildAt(DateTime? at) {
    if (at == _releaseAt) return;
    _releaseAt = at;
    _releaseTimer?.cancel();
    if (at == null) return;
    final wait = at.difference(DateTime.now());
    // Long waits check again daily rather than holding a far timer.
    final day = const Duration(days: 1);
    _releaseTimer = Timer(wait < day ? wait : day, () {
      if (mounted) setState(() => _releaseAt = null);
    });
  }

  /// When [episode] airs. Bangumi's air date decides the day, so a skipped
  /// week stays right; the schedule, a weekly rule, only adds the time when
  /// one of its broadcasts falls within a day of that date.
  _Release? _release(Episode episode) {
    final date = episode.aired;
    if (date == null) return null;
    final day = DateTime.utc(date.year, date.month, date.day);
    DateTime? timed;
    var nearest = 2;
    for (final at in widget.airings) {
      final gap = _shanghaiDay(at).difference(day).inDays.abs();
      if (gap < nearest) {
        nearest = gap;
        timed = at;
      }
    }
    return timed == null ? (at: date, timed: false) : (at: timed, timed: true);
  }

  bool _aired(Episode episode) =>
      !(_release(episode)?.at.isAfter(DateTime.now()) ?? false);

  Future<bool> _saveFields(
    CollectionChange fields, {
    required String label,
    CollectionChange? undo,
    int completeOffer = 0,
  }) async {
    if (_savingCollection) return false;
    final subjectId = widget.subject?.id;
    final previousStatus = _selectedStatus;
    _feedbackTimer?.cancel();
    setState(() {
      if (fields.status case final status?) _selectedStatus = status;
      _savingCollection = true;
      _collectionError = _nudge = null;
      _feedback = '正在保存…';
      _undo = null;
      _completeOffer = 0;
    });
    try {
      await widget.onSaveCollection(fields);
      if (!mounted || widget.subject?.id != subjectId) return true;
      setState(() {
        _savingCollection = false;
        _feedback = label;
        _undo = undo;
        _completeOffer = completeOffer;
      });
      _feedbackTimer = Timer(Duration(seconds: completeOffer > 0 ? 10 : 5), () {
        if (mounted) {
          setState(() {
            _feedback = null;
            _undo = null;
            _completeOffer = 0;
          });
        }
      });
      return true;
    } catch (error) {
      if (!mounted || widget.subject?.id != subjectId) return false;
      setState(() {
        _selectedStatus = previousStatus;
        _savingCollection = false;
        _feedback = null;
        _collectionError = '保存失败：${errorMessage(error)}';
      });
      return false;
    }
  }

  void _nudgeStatus(String message) {
    _feedbackTimer?.cancel();
    setState(() {
      _nudges++;
      _nudge = message;
      _feedback = null;
      _undo = null;
    });
  }

  Future<void> _saveStatus(CollectionStatus status) async {
    final previous = _status;
    if (status == previous) return;
    final previousScore = _collection.score;
    final unwatched = status == CollectionStatus.completed
        ? (widget.subject?.episodes ?? const <Episode>[])
              .where((e) => e.main && !e.watched)
              .length
        : 0;
    await _saveFields(
      CollectionChange(status: status),
      label: previous == null
          ? '已加入${collectionLabels[status]}'
          : '已改为${collectionLabels[status]}',
      undo: previous == null
          ? null
          : CollectionChange(
              status: previous,
              score: status == CollectionStatus.wish && previousScore > 0
                  ? previousScore
                  : null,
            ),
      completeOffer: unwatched,
    );
  }

  void _saveScore(int score) {
    if (_status == null) {
      _nudgeStatus('先选择收藏状态，再评分');
      return;
    }
    if (_status == CollectionStatus.wish) {
      _nudgeStatus('想看状态不能评分，先改成在看或看过');
      return;
    }
    final previous = _collection.score;
    if (score == previous) return;
    unawaited(
      _saveFields(
        CollectionChange(score: score),
        label: score == 0 ? '已清除评分' : '已评 $score 分',
        undo: CollectionChange(score: previous),
      ),
    );
  }

  List<String> get _tags => _collection.tags;

  Future<String?> _saveTags(List<String> tags) async {
    if (_status == null) {
      _nudgeStatus('先选择收藏状态，再加标签');
      return null;
    }
    try {
      tags = normalizeCollectionTags(tags);
    } on FormatException catch (error) {
      return error.message;
    }
    // The typed tags stay in the field when they were not saved.
    if (_savingCollection) return '正在保存上一项修改，请稍后再添加';
    final previous = _tags;
    final saved = await _saveFields(
      CollectionChange(tags: tags),
      label: '已保存标签',
      undo: CollectionChange(tags: previous),
    );
    return saved ? null : '标签未保存';
  }

  Future<void> _saveComment(String comment) =>
      widget.onSaveCollection(CollectionChange(comment: comment));

  Future<void> _openDrawer({bool focusComment = false}) async {
    final subjectId = widget.subject?.id;
    final user = widget.community.userId;
    final key = _draftKey;
    final mutation = await showCollectionDrawer(
      context,
      subject: widget.subject!.copyWith(collection: _collection),
      draftKey: key,
      focusComment: focusComment,
    );
    if (!mounted ||
        widget.subject?.id != subjectId ||
        widget.community.userId != user) {
      return;
    }
    if (mutation == null || mutation.isEmpty) {
      _feedbackTimer?.cancel();
      setState(() {
        _undo = null;
        _nudge = null;
        _feedback = CollectionDrafts.has(key) ? '已暂存草稿，下次打开编辑会恢复' : null;
      });
      return;
    }
    if (await _saveFields(mutation, label: '已保存收藏')) {
      CollectionDrafts.clear(key);
      if (mounted) setState(() {});
    }
  }

  Future<void> _markEpisodes(
    List<Episode> episodes,
    EpisodeStatus status,
  ) async {
    final subjectId = widget.subject?.id;
    final ids = [for (final episode in episodes) episode.id];
    if (ids.isEmpty) return;
    setState(() {
      for (final id in ids) {
        _episodeOverrides[id] = status;
      }
      _episodeError = null;
    });
    try {
      // Bangumi rejects episode progress for subjects outside the collection.
      if (_status == null &&
          !await _saveFields(
            const CollectionChange(status: CollectionStatus.watching),
            label: '已加入在看',
          )) {
        throw StateError('需要先加入收藏');
      }
      await widget.onSaveEpisodes(ids, status);
    } catch (error) {
      if (mounted && widget.subject?.id == subjectId) {
        _episodeError = '标记失败：${errorMessage(error)}';
      }
    } finally {
      if (mounted && widget.subject?.id == subjectId) {
        setState(() => ids.forEach(_episodeOverrides.remove));
      }
    }
  }

  Future<void> _retryCollection() => _collectionIssue.run(() async {
    await widget.onRetryCollectionSync?.call();
    return widget.collectionSyncError;
  });

  EpisodeStatus _episodeStatus(Episode episode) =>
      _episodeOverrides[episode.id] ?? episode.status;

  Episode? _nextEpisode(List<Episode> episodes) =>
      episodes.where(_isResume).firstOrNull ??
      episodes
          .where((e) => e.main && _episodeStatus(e) != EpisodeStatus.watched)
          .firstOrNull ??
      episodes.where((e) => e.main).lastOrNull ??
      episodes.firstOrNull;

  bool _isResume(Episode episode) =>
      widget.resume?.episodeId == episode.id &&
      (widget.resume?.position ?? 0) > 0;

  bool? _available(Episode episode) =>
      widget.cachedEpisodeIds?.contains(episode.id);

  String _timestamp(double seconds) {
    final value = seconds.toInt();
    return '${value ~/ 60}:${(value % 60).toString().padLeft(2, '0')}';
  }

  /// The episode's name, then its state and air date.
  TextSpan _episodeSummary(Episode episode) {
    final date = episode.airDate ?? '';
    return TextSpan(
      children: [
        TextSpan(
          text: '${episode.label}  ${episode.title}',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
        for (final detail in [
          if (_isResume(episode))
            '看到 ${_timestamp(widget.resume!.position)}'
          else if (!_aired(episode))
            '未更新'
          else if (_episodeStatus(episode) == EpisodeStatus.watched)
            '已看',
          if (_available(episode) ?? false) '已缓存',
          if (date.isNotEmpty) date,
        ])
          TextSpan(text: '    $detail'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.subject;
    if (item == null) return const Center(child: CircularProgressIndicator());
    return PageScroll(
      children: [
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final hero = _hero(item);
            final cards = [_collectionCard(item), ?_statsCard(item)];
            if (constraints.maxWidth >= _wideLayout) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: hero),
                  const SizedBox(width: Gap.lg),
                  SizedBox(
                    width: homeSideColumnWidth,
                    child: Column(
                      children: [
                        for (final (index, card) in cards.indexed) ...[
                          if (index > 0) const SizedBox(height: Gap.lg),
                          card,
                        ],
                      ],
                    ),
                  ),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                hero,
                const SizedBox(height: Gap.lg),
                if (constraints.maxWidth >= 600 && cards.length > 1)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: cards[0]),
                      const SizedBox(width: Gap.lg),
                      Expanded(child: cards[1]),
                    ],
                  )
                else
                  for (final (index, card) in cards.indexed) ...[
                    if (index > 0) const SizedBox(height: Gap.lg),
                    card,
                  ],
              ],
            );
          },
        ),
        const SizedBox(height: Gap.lg),
        PageSliver(child: _lower(item)),
      ],
    );
  }

  Widget _lower(Subject item) {
    final subjectId = item.id;
    final user = widget.community.userId;
    final main = [?_charactersPanel(item), ?_staffPanel(item)];
    final side = [
      ?_infoPanel(item),
      SubjectRelations(
        key: ValueKey('relations:$subjectId:$user'),
        client: widget.community,
        subjectId: subjectId,
        onOpenSubject: widget.onOpenSubject,
      ),
    ];
    final community = SubjectCommunity(
      key: ValueKey('community:$subjectId:$user'),
      client: widget.community,
      subjectId: subjectId,
      collection: _collection,
      canWrite: widget.signedIn,
      onSaveComment: _saveComment,
    );
    Widget box(Widget child) => SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(bottom: Gap.lg),
        child: child,
      ),
    );
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        if (constraints.crossAxisExtent < _wideLayout) {
          return SliverMainAxisGroup(
            slivers: [...main.map(box), ...side.map(box), community],
          );
        }
        return SliverCrossAxisGroup(
          slivers: [
            SliverCrossAxisExpanded(
              flex: 1,
              sliver: SliverMainAxisGroup(
                slivers: [...main.map(box), community],
              ),
            ),
            SliverConstrainedCrossAxis(
              maxExtent: homeSideColumnWidth + Gap.lg,
              sliver: SliverPadding(
                padding: const EdgeInsets.only(left: Gap.lg),
                sliver: SliverMainAxisGroup(slivers: side.map(box).toList()),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _hero(Subject item) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final episodes = item.episodes;
    // Interludes are watched in place but counted with neither total.
    final main = episodes.where((e) => e.main).toList();
    final watched = main
        .where((e) => _episodeStatus(e) == EpisodeStatus.watched)
        .length;
    final total = math.max(item.episodeTotal ?? 0, main.length);
    final next = _nextEpisode(episodes);
    // Like Animeko, a finished subject offers its last episode quietly.
    final done =
        next != null &&
        !_episodesLoading &&
        !_isResume(next) &&
        main.isNotEmpty &&
        watched == main.length;
    final now = DateTime.now();
    _rebuildAt(
      ([
        for (final episode in episodes)
          if (_release(episode)?.at case final at? when at.isAfter(now)) at,
      ]..sort()).firstOrNull,
    );
    final upcoming = next == null || _isResume(next) || _aired(next)
        ? null
        : _release(next);
    final playLabel = _episodesLoading
        ? '加载剧集…'
        : next == null
        ? '暂无剧集'
        : _isResume(next)
        ? '继续观看${next.label}'
        : done
        ? '已看完'
        : '观看${next.label}';
    final date = DateTime.tryParse('${item.airDate}');
    final score = item.score ?? 0;
    final summary =
        item.summary ?? (_loadingPart('subject') ? '正在加载简介…' : '暂无简介');
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(item.title, style: text.titleLarge)),
            IconButton(
              tooltip: '在 Bangumi 打开',
              onPressed: () =>
                  openExternal(context, 'https://bgm.tv/subject/${item.id}'),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
            ),
          ],
        ),
        if ((item.name ?? '').isNotEmpty && item.name != item.title)
          Text(item.name!, style: text.bodySmall),
        const SizedBox(height: Gap.md),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            if (date != null)
              MelonBadge('${date.year}年${date.month}月', color: coral)
            else if (item.airDate case final airDate?)
              MelonBadge(airDate, color: coral),
            MelonBadge(item.platform ?? '动画', color: sky),
            for (final tag
                in item.tags
                    .where(
                      (tag) =>
                          tag.name != (item.platform ?? '动画') &&
                          !RegExp(r'^\d{4}年').hasMatch(tag.name),
                    )
                    .take(3))
              MelonBadge(tag.name, color: grape),
          ],
        ),
        const SizedBox(height: Gap.lg),
        Wrap(
          spacing: Gap.lg,
          runSpacing: Gap.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (score > 0)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star_rounded, color: gold, size: 26),
                  const SizedBox(width: 2),
                  Text(
                    scoreLabel(score),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      height: 1,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            if (item.rank != null || item.ratingCount != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (item.rank != null)
                    Text('排名 #${item.rank}', style: text.bodySmall),
                  if (item.ratingCount != null)
                    Text('${item.ratingCount} 人评分', style: text.bodySmall),
                ],
              ),
            SizedBox(
              width: 220,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _episodesLoading ? '正在加载剧集…' : '已看 $watched / 全 $total 话',
                    style: text.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: MotionValue(
                      value: total == 0 ? 0 : watched / total,
                      from: 0,
                      milliseconds: 600,
                      builder: (context, value) => LinearProgressIndicator(
                        value: value,
                        minHeight: 6,
                        color: accentOf(context).accent,
                        backgroundColor: scheme.surfaceContainerHigh,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.lg + 2),
        Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          children: [
            if (upcoming != null && !_episodesLoading)
              FilledButton.icon(
                onPressed: null,
                icon: const Icon(Icons.schedule_rounded, size: 18),
                label: _ReleaseCountdown(release: upcoming, episode: next!),
              )
            else if (done)
              FilledButton.tonalIcon(
                onPressed: () => widget.onPlayEpisode(next),
                icon: const Icon(Icons.play_arrow_rounded, size: 19),
                label: Text(playLabel),
              )
            else
              FilledButton.icon(
                onPressed: next == null || _episodesLoading
                    ? null
                    : () => widget.onPlayEpisode(next),
                icon: const Icon(Icons.play_arrow_rounded, size: 19),
                label: Text(playLabel),
              ),
            OutlinedButton.icon(
              onPressed: () => widget.onFindResources(null),
              icon: const Icon(Icons.download_outlined, size: 18),
              label: const Text('查找资源'),
            ),
          ],
        ),
        const SizedBox(height: Gap.lg),
        AnimatedSize(
          duration: motionDuration(context, 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topLeft,
          child: _summaryExpanded
              ? SelectableText(
                  key: PageStorageKey('subject-summary:${item.id}'),
                  summary,
                  style: const TextStyle(fontSize: 13, height: 1.75),
                )
              : Text(
                  summary.replaceAll(RegExp(r'\s+'), ' '),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, height: 1.75),
                ),
        ),
        if (summary.length > 90)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 30),
              ),
              onPressed: () =>
                  setState(() => _summaryExpanded = !_summaryExpanded),
              child: Text(_summaryExpanded ? '收起简介' : '展开简介'),
            ),
          ),
      ],
    );
    return MelonPanel(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 580;
              final cover = SizedBox(
                width: narrow ? 112 : 158,
                child: AspectRatio(
                  aspectRatio: .75,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: posterBorderRadius,
                      boxShadow: posterShadows(context),
                    ),
                    child: ClipRRect(
                      borderRadius: posterBorderRadius,
                      child: SubjectCover(
                        url: item.coverUrl,
                        title: item.title,
                        id: item.id,
                      ),
                    ),
                  ),
                ),
              );
              return narrow
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [cover, const SizedBox(height: 18), info],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        cover,
                        const SizedBox(width: Gap.xl),
                        Expanded(child: info),
                      ],
                    );
            },
          ),
          const Divider(height: 28),
          _episodeSection(episodes, next),
        ],
      ),
    );
  }

  Widget _episodeSection(List<Episode> episodes, Episode? next) {
    final text = Theme.of(context).textTheme;
    final hover = _hoverEpisode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('剧集', style: text.titleSmall),
            const SizedBox(width: Gap.md),
            if (hover ?? next case final shown?)
              Expanded(
                child: Text.rich(
                  _episodeSummary(shown),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall,
                ),
              ),
          ],
        ),
        const SizedBox(height: Gap.sm + 2),
        if (_episodesLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('正在加载剧集…'),
          )
        else if (episodes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: _failedPart('episodes')
                ? _failure('剧集加载失败')
                : const Text('暂无剧集信息'),
          )
        else
          EpisodeGrid(
            episodes: episodes,
            nextId: next?.id,
            statusOf: _episodeStatus,
            aired: _aired,
            onSelect: widget.onOpenEpisode,
            onOpen: (episode) => widget.onFindResources(episode),
            onPlay: widget.onPlayEpisode,
            onMark: (values, status) =>
                unawaited(_markEpisodes(values, status)),
            onHover: (episode) {
              if (episode?.id != _hoverEpisode?.id) {
                setState(() => _hoverEpisode = episode);
              }
            },
          ),
        if (_episodeError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _episodeError!,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }

  Widget _failure(String message) =>
      PartFailure(message: message, onRetry: widget.onRetry);

  Widget _collectionCard(Subject item) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final status = _status;
    final score = _collection.score;
    final comment = _collection.comment;
    final draft = widget.signedIn && CollectionDrafts.has(_draftKey);
    Widget field(String label, Widget child, {bool top = false}) => Padding(
      padding: const EdgeInsets.only(top: Gap.md),
      child: Row(
        crossAxisAlignment: top
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          Padding(
            padding: EdgeInsets.only(top: top ? 8 : 0),
            child: SizedBox(
              width: 34,
              child: Text(label, style: text.bodySmall),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
    return MelonPanel(
      padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('我的收藏', style: text.titleSmall),
              if (draft) ...[
                const SizedBox(width: Gap.sm),
                const MelonBadge('有草稿', color: coral),
              ],
              const Spacer(),
              if (widget.signedIn)
                TextButton.icon(
                  onPressed: _savingCollection ? null : () => _openDrawer(),
                  icon: const Icon(Icons.edit_outlined, size: 17),
                  label: Text(draft ? '继续编辑' : '编辑'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: _Nudge(
              trigger: _nudges,
              child: MelonSegmentedControl<CollectionStatus>(
                options: collectionLabels,
                value: status,
                onChanged: _savingCollection
                    ? null
                    : (value) => unawaited(_saveStatus(value)),
                allowDrag: true,
                semanticLabel: '收藏状态',
              ),
            ),
          ),
          if (widget.signedIn) ...[
            field(
              '评分',
              Row(
                children: [
                  StarRating(
                    value: score,
                    size: 16,
                    labelWidth: 64,
                    enabled: status != null && status != CollectionStatus.wish,
                    onTap: _saveScore,
                  ),
                  const Spacer(),
                  if (score > 0)
                    IconButton(
                      tooltip: '清除评分',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 28,
                        height: 28,
                      ),
                      onPressed: _savingCollection ? null : () => _saveScore(0),
                      icon: const Icon(Icons.close_rounded, size: 16),
                    ),
                ],
              ),
            ),
            field(
              '标签',
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final tag in _tags)
                    InputChip(
                      label: Text(tag),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      deleteButtonTooltipMessage: '移除 $tag',
                      onDeleted: _savingCollection
                          ? null
                          : () => unawaited(_saveTags([..._tags]..remove(tag))),
                    ),
                  _TagAdder(
                    tags: _tags,
                    popular: item.tags.map((tag) => tag.name).take(16).toList(),
                    blocked: status == null,
                    onBlocked: () => _nudgeStatus('先选择收藏状态，再加标签'),
                    onSave: _saveTags,
                  ),
                ],
              ),
              top: _tags.isNotEmpty,
            ),
            field(
              '吐槽',
              Material(
                color: scheme.surfaceContainer,
                borderRadius: controlBorderRadius,
                child: InkWell(
                  borderRadius: controlBorderRadius,
                  onTap: () => status == null
                      ? _nudgeStatus('先选择收藏状态，再写吐槽')
                      : _openDrawer(focusComment: true),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    child: Text(
                      comment.isEmpty ? '写一句吐槽…' : comment,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: comment.isEmpty
                          ? text.bodySmall
                          : const TextStyle(fontSize: 12, height: 1.6),
                    ),
                  ),
                ),
              ),
              top: true,
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: Gap.md),
              child: Text('登录 Bangumi 后可以评分、加标签和写吐槽', style: text.bodySmall),
            ),
          const SizedBox(height: 6),
          _collectionFeedback(),
          FeedbackIssue(
            feedback: _collectionIssue,
            onRetry: () => unawaited(_retryCollection()),
          ),
        ],
      ),
    );
  }

  Widget _collectionFeedback() {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    final Widget? content;
    if (_collectionError != null) {
      content = Text(
        _collectionError!,
        style: small?.copyWith(color: scheme.error),
      );
    } else if (_nudge != null) {
      content = Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 15, color: scheme.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(_nudge!, style: small?.copyWith(color: scheme.primary)),
          ),
        ],
      );
    } else if (_savingCollection ||
        _feedback != null ||
        _undo != null ||
        _completeOffer > 0) {
      content = Wrap(
        spacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (_savingCollection)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: SizedBox.square(
                dimension: 12,
                child: CircularProgressIndicator(strokeWidth: 1.5),
              ),
            ),
          if (_feedback != null) Text(_feedback!, style: small),
          if (_undo != null && !_savingCollection)
            TextButton(
              onPressed: () {
                final undo = _undo!;
                unawaited(_saveFields(undo, label: '已撤销'));
              },
              child: const Text('撤销'),
            ),
          if (_completeOffer > 0 && !_savingCollection)
            TextButton(
              onPressed: () => unawaited(
                _saveFields(
                  const CollectionChange(
                    status: CollectionStatus.completed,
                    completeEpisodes: true,
                  ),
                  label: '已将全部正片标为已看',
                ),
              ),
              child: Text('剩余 $_completeOffer 话标为已看'),
            ),
        ],
      );
    } else {
      content = null;
    }
    // Collapsed when idle so the card has no empty strip under 吐槽.
    return Semantics(
      liveRegion: true,
      child: AnimatedSize(
        duration: motionDuration(context, 180),
        alignment: Alignment.topLeft,
        child: content == null
            ? const SizedBox(width: double.infinity)
            : Padding(
                padding: const EdgeInsets.only(top: Gap.sm),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 30),
                  child: Align(alignment: Alignment.centerLeft, child: content),
                ),
              ),
      ),
    );
  }

  Widget? _statsCard(Subject item) {
    final stats = item.collectionStats;
    final total = collectionLabels.keys.fold<int>(
      0,
      (sum, key) => sum + (stats[key] ?? 0),
    );
    if (total == 0) return null;
    final small = Theme.of(context).textTheme.bodySmall;
    const tabular = [FontFeature.tabularFigures()];
    return MelonPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('收藏统计', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              Text('共 ${_thousands(total)} 人', style: small),
            ],
          ),
          const SizedBox(height: Gap.md),
          // The bar fills in from the left when the card first shows.
          MotionValue(
            value: 1,
            from: 0,
            milliseconds: 800,
            builder: (context, grown) => ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: Align(
                alignment: Alignment.centerLeft,
                widthFactor: grown,
                child: SizedBox(
                  height: 8,
                  child: Row(
                    children: [
                      for (final key in collectionLabels.keys)
                        if ((stats[key] ?? 0) > 0)
                          Expanded(
                            flex: math.max(1, stats[key]!),
                            child: Padding(
                              padding: const EdgeInsets.only(right: 2),
                              child: ColoredBox(
                                color: collectionColor(key),
                                child: const SizedBox.expand(),
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: Gap.md),
          for (final MapEntry(:key, :value) in collectionLabels.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: collectionColor(key),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: Text(value, style: const TextStyle(fontSize: 12)),
                  ),
                  Text(
                    _thousands(stats[key] ?? 0),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      fontFeatures: tabular,
                    ),
                  ),
                  SizedBox(
                    width: 52,
                    child: Text(
                      '${((stats[key] ?? 0) * 100 / total).toStringAsFixed(1)}%',
                      textAlign: TextAlign.right,
                      style: small?.copyWith(fontFeatures: tabular),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _thousands(int value) => value.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );

  Widget? _infoPanel(Subject item) {
    final rows = item.infoBox;
    if (rows.isEmpty) return null;
    final small = Theme.of(context).textTheme.bodySmall;
    final shown = _infoExpanded ? rows : rows.take(10);
    return MelonPanel(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('作品资料', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: Gap.sm),
          AnimatedSize(
            duration: motionDuration(context, 280),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topLeft,
            child: Column(
              children: [
                for (final row in shown)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3.5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 76, child: Text(row.key, style: small)),
                        Expanded(
                          child: SelectableText(
                            key: PageStorageKey(
                              'subject-info:${item.id}:${row.key}',
                            ),
                            row.value,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (rows.length > 10)
            TextButton(
              onPressed: () => setState(() => _infoExpanded = !_infoExpanded),
              child: Text(_infoExpanded ? '收起' : '展开全部 ${rows.length} 项'),
            ),
        ],
      ),
    );
  }

  Widget? _charactersPanel(Subject item) =>
      _peoplePanel(item, characters: true);

  Widget? _staffPanel(Subject item) => _peoplePanel(item, characters: false);

  Widget? _peoplePanel(Subject item, {required bool characters}) {
    final part = characters ? 'characters' : 'staff';
    final loading = _loadingPart(part);
    if ((characters ? item.characters : item.staff).isEmpty &&
        !loading &&
        !_failedPart(part)) {
      return null;
    }
    return SubjectPeoplePanel(
      subject: item,
      characters: characters,
      loading: loading,
      onRetry: widget.onRetry,
    );
  }
}

/// Shakes and outlines its child each time [trigger] changes.
class _Nudge extends StatelessWidget {
  const _Nudge({required this.trigger, required this.child});
  final int trigger;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return TweenAnimationBuilder<double>(
      key: ValueKey(trigger),
      tween: Tween(begin: trigger == 0 ? 1 : 0, end: 1),
      duration: motionDuration(context, 480),
      child: child,
      builder: (context, t, child) => Transform.translate(
        offset: Offset(math.sin(t * math.pi * 6) * (1 - t) * 6, 0),
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: controlBorderRadius,
            border: Border.all(
              color: color.withValues(alpha: (1 - t) * .8),
              width: 2,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// "+ 添加" chip opening a small tag menu: free input plus popular tags.
class _TagAdder extends StatefulWidget {
  const _TagAdder({
    required this.tags,
    required this.popular,
    required this.blocked,
    required this.onBlocked,
    required this.onSave,
  });
  final List<String> tags, popular;
  final bool blocked;
  final VoidCallback onBlocked;

  /// Returns a validation message, or null once saved.
  final Future<String?> Function(List<String>) onSave;

  @override
  State<_TagAdder> createState() => _TagAdderState();
}

class _TagAdderState extends State<_TagAdder> {
  final input = TextEditingController();
  String? error;

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> _save(List<String> tags) async {
    final message = await widget.onSave(tags);
    if (mounted) setState(() => error = message);
    if (message == null) input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(menuSurface(context)),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(12)),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: controlBorderRadius),
        ),
      ),
      onClose: () => setState(() => error = null),
      menuChildren: [
        SizedBox(
          width: 300,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: input,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: '输入标签，回车或逗号添加',
                  errorText: error,
                ),
                onSubmitted: (value) => unawaited(
                  _save([...widget.tags, ...value.split(RegExp('[,，]'))]),
                ),
                onChanged: (value) {
                  if (value.endsWith(',') || value.endsWith('，')) {
                    unawaited(
                      _save([...widget.tags, ...value.split(RegExp('[,，]'))]),
                    );
                  }
                },
              ),
              if (widget.popular.isNotEmpty) ...[
                const SizedBox(height: Gap.md),
                Text('大家常用', style: small),
                const SizedBox(height: 6),
                TagToggles(
                  tags: widget.popular,
                  selected: widget.tags.toSet(),
                  onToggle: (tag) => unawaited(
                    _save(
                      widget.tags.contains(tag)
                          ? ([...widget.tags]..remove(tag))
                          : [...widget.tags, tag],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: Gap.sm),
              Text('${widget.tags.length}/$collectionTagLimit', style: small),
            ],
          ),
        ),
      ],
      builder: (context, controller, _) => ActionChip(
        avatar: const Icon(Icons.add_rounded, size: 16),
        label: const Text('添加'),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onPressed: () {
          if (widget.blocked) {
            widget.onBlocked();
          } else if (controller.isOpen) {
            controller.close();
          } else {
            controller.open();
          }
        },
      ),
    );
  }
}

/// When an episode airs; [timed] when the schedule gives the hour, otherwise
/// [at] is the start of its air date.
typedef _Release = ({DateTime at, bool timed});

/// The calendar day of [instant] in UTC+8, the schedule's time zone.
DateTime _shanghaiDay(DateTime instant) {
  final time = instant.toUtc().add(const Duration(hours: 8));
  return DateTime.utc(time.year, time.month, time.day);
}

/// The play button's label while the next episode has not aired: minutes
/// within the last hour, then 今天 / 明天 / 周X with the hour within a week,
/// else the date.
class _ReleaseCountdown extends StatefulWidget {
  const _ReleaseCountdown({required this.release, required this.episode});
  final _Release release;
  final Episode episode;

  @override
  State<_ReleaseCountdown> createState() => _ReleaseCountdownState();
}

class _ReleaseCountdownState extends State<_ReleaseCountdown> {
  static const _weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (:at, :timed) = widget.release;
    final now = DateTime.now();
    final left = at.difference(now);
    final day = timed
        ? _shanghaiDay(at)
        : DateTime.utc(at.year, at.month, at.day);
    final today = _shanghaiDay(now);
    final shanghai = at.toUtc().add(const Duration(hours: 8));
    final clock = timed
        ? ' ${shanghai.hour.toString().padLeft(2, '0')}:${shanghai.minute.toString().padLeft(2, '0')} '
        : '';
    final when = timed && left < const Duration(hours: 1)
        ? left.inMinutes < 1
              ? '即将'
              : '${left.inMinutes} 分钟后'
        : switch (day.difference(today).inDays) {
            <= 0 => '今天$clock',
            1 => '明天$clock',
            < 7 => '${_weekdays[day.weekday - 1]}$clock',
            _ when day.year == today.year => '${day.month}月${day.day}日',
            _ => '${day.year}年${day.month}月${day.day}日',
          };
    return Text('$when更新');
  }
}

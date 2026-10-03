import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/bangumi_private.dart';
import '../../data/collection_edit.dart';
import '../../data/json.dart';
import '../../data/play_candidates.dart' show isMainEpisode;
import '../core/action_feedback.dart';
import '../core/cached_image.dart';
import '../core/motion.dart';
import '../core/page_widgets.dart';
import '../core/selection_controls.dart';
import '../core/subject_posters.dart';
import '../core/theme.dart';
import 'collection_editor.dart';
import 'collection_labels.dart';
import 'subject_community.dart';

/// Content width at which the collection and statistics cards sit in a
/// right column beside the main panel.
const _wideLayout = 860.0;

class SubjectPage extends StatefulWidget {
  const SubjectPage({
    super.key,
    required this.subject,
    required this.community,
    required this.onSaveTracking,
    required this.onFindResources,
    required this.onOpenEpisode,
    required this.onPlayEpisode,
    required this.onOpenSubject,
    this.resume,
    this.cachedEpisodeIds,
    this.loading = false,
    this.signedIn = false,
    this.collectionSyncError,
    this.onRetryCollectionSync,
  });
  final Json? subject;
  final bool loading;
  final bool signedIn;
  final BangumiPrivateClient community;
  final String? collectionSyncError;
  final Future<void> Function()? onRetryCollectionSync;
  final Json? resume;
  final Set<int>? cachedEpisodeIds;
  final Future<void> Function(Json) onSaveTracking;
  final ValueChanged<Json?> onFindResources;
  final ValueChanged<Json> onOpenEpisode, onPlayEpisode, onOpenSubject;
  @override
  State<SubjectPage> createState() => _SubjectPageState();
}

class _SubjectPageState extends State<SubjectPage> {
  String? _selectedStatus, _feedback, _collectionError, _nudge;

  /// Fields that restore the collection before the last quick edit.
  Json? _undo;

  /// Unwatched main episodes offered for completion after choosing 看过.
  int _completeOffer = 0;
  int _nudges = 0;
  bool _savingCollection = false;
  bool _summaryExpanded = false, _infoExpanded = false;
  Timer? _feedbackTimer;
  final _episodeOverrides = <int, String>{};
  String? _episodeError;
  Json? _hoverEpisode;
  final _collectionIssue = ActionFeedback();

  @override
  void initState() {
    super.initState();
    _collectionIssue.issue = widget.collectionSyncError;
  }

  bool _loadingPart(String part) {
    if (!widget.loading) return false;
    final pending = widget.subject?['_pending'] as List<dynamic>?;
    return pending == null
        ? widget.subject?.containsKey('episodes') != true
        : pending.contains(part);
  }

  bool _failedPart(String part) =>
      !widget.loading &&
      (widget.subject?['_pending'] as List<dynamic>?)?.contains(part) == true;

  bool get _episodesLoading =>
      _loadingPart('episodes') && objects(widget.subject?['episodes']).isEmpty;

  Json get _collection => {
    ...object(widget.subject?['collection']),
    'status': ?_selectedStatus,
  };

  String? get _status => _collection['status'] as String?;

  String get _draftKey => CollectionDrafts.key(
    widget.community.account.userId,
    widget.subject?['subjectId'],
  );

  @override
  void didUpdateWidget(covariant SubjectPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.collectionSyncError != oldWidget.collectionSyncError) {
      _collectionIssue.issue = widget.collectionSyncError;
    }
    if (oldWidget.subject?['subjectId'] != widget.subject?['subjectId']) {
      _feedbackTimer?.cancel();
      _selectedStatus = _feedback = _collectionError = _nudge = null;
      _undo = _hoverEpisode = null;
      _episodeError = null;
      _completeOffer = 0;
      _savingCollection = _summaryExpanded = _infoExpanded = false;
      _episodeOverrides.clear();
    } else if (!_savingCollection &&
        object(oldWidget.subject?['collection'])['status'] !=
            object(widget.subject?['collection'])['status']) {
      _selectedStatus = null;
    }
  }

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    _collectionIssue.dispose();
    super.dispose();
  }

  Future<bool> _saveFields(
    Json fields, {
    required String label,
    Json? undo,
    int completeOffer = 0,
  }) async {
    if (_savingCollection) return false;
    final subjectId = widget.subject?['subjectId'];
    final previousStatus = _selectedStatus;
    _feedbackTimer?.cancel();
    setState(() {
      if (fields['status'] case final String status) _selectedStatus = status;
      _savingCollection = true;
      _collectionError = _nudge = null;
      _feedback = '正在保存…';
      _undo = null;
      _completeOffer = 0;
    });
    try {
      await widget.onSaveTracking({
        'kind': 'subjectCollection',
        'subjectId': subjectId,
        ...fields,
      });
      if (!mounted || widget.subject?['subjectId'] != subjectId) return true;
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
      if (!mounted || widget.subject?['subjectId'] != subjectId) return false;
      setState(() {
        _selectedStatus = previousStatus;
        _savingCollection = false;
        _feedback = null;
        _collectionError = '保存失败：$error';
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

  Future<void> _saveStatus(String status) async {
    final previous = _status;
    if (status == previous) return;
    final previousScore = number(_collection['score']).toInt();
    final unwatched = status == 'completed'
        ? objects(widget.subject?['episodes'])
              .where((e) => isMainEpisode(e) && e['status'] != 'watched')
              .length
        : 0;
    await _saveFields(
      {'status': status},
      label: previous == null
          ? '已加入收藏 · ${collectionLabels[status]}'
          : '已保存 · ${collectionLabels[status]}',
      undo: previous == null
          ? null
          : {
              'status': previous,
              if (status == 'wish' && previousScore > 0) 'score': previousScore,
            },
      completeOffer: unwatched,
    );
  }

  void _saveScore(int score) {
    if (_status == null) {
      _nudgeStatus('先选择收藏状态，再评分');
      return;
    }
    if (_status == 'wish') {
      _nudgeStatus('想看状态不能评分，先改成在看或看过');
      return;
    }
    final previous = number(_collection['score']).toInt();
    if (score == previous) return;
    unawaited(
      _saveFields(
        {'score': score},
        label: score == 0 ? '已清除评分' : '已保存评分 $score · ${scoreLabels[score]}',
        undo: {'score': previous},
      ),
    );
  }

  List<String> get _tags =>
      (_collection['tags'] as List? ?? []).whereType<String>().toList();

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
    final previous = _tags;
    await _saveFields({'tags': tags}, label: '已保存标签', undo: {'tags': previous});
    return null;
  }

  Future<void> _saveComment(String comment) => widget.onSaveTracking({
    'kind': 'subjectCollection',
    'subjectId': widget.subject?['subjectId'],
    'comment': comment,
  });

  Future<void> _openDrawer({bool focusComment = false}) async {
    final subjectId = widget.subject?['subjectId'];
    final user = widget.community.account.userId;
    final key = _draftKey;
    final mutation = await showCollectionDrawer(
      context,
      subject: {...widget.subject!, 'collection': _collection},
      draftKey: key,
      focusComment: focusComment,
    );
    if (!mounted ||
        widget.subject?['subjectId'] != subjectId ||
        widget.community.account.userId != user) {
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

  Future<void> _markEpisodes(List<Json> episodes, String status) async {
    final subjectId = widget.subject?['subjectId'];
    final ids = [
      for (final episode in episodes) number(episode['episodeId']).toInt(),
    ];
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
          !await _saveFields({'status': 'watching'}, label: '已加入收藏 · 在看')) {
        throw StateError('需要先加入收藏');
      }
      await widget.onSaveTracking({
        'kind': 'episodeCollection',
        'subjectId': subjectId,
        'episodeIds': ids,
        'status': status,
      });
    } catch (error) {
      if (mounted && widget.subject?['subjectId'] == subjectId) {
        _episodeError = '标记失败：$error';
      }
    } finally {
      if (mounted && widget.subject?['subjectId'] == subjectId) {
        setState(() => ids.forEach(_episodeOverrides.remove));
      }
    }
  }

  Future<void> _retryCollection() => _collectionIssue.run(() async {
    await widget.onRetryCollectionSync?.call();
    return widget.collectionSyncError;
  });

  Future<void> _openLink(Uri url) async {
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw StateError('无法打开链接');
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('打开失败：$error')));
      }
    }
  }

  String _episodeStatus(Json episode) =>
      _episodeOverrides[number(episode['episodeId']).toInt()] ??
      '${episode['status'] ?? 'unwatched'}';

  Json? _nextEpisode(List<Json> episodes) =>
      episodes.where(_isResume).firstOrNull ??
      episodes.where((e) => _episodeStatus(e) != 'watched').firstOrNull ??
      episodes.firstOrNull;

  bool _isResume(Json episode) =>
      widget.resume?['subjectId'] == widget.subject?['subjectId'] &&
      widget.resume?['episodeId'] == episode['episodeId'] &&
      widget.resume?['completed'] != true &&
      number(widget.resume?['positionSeconds']) > 0;

  bool? _available(Json episode) =>
      widget.cachedEpisodeIds?.contains(number(episode['episodeId']).toInt());

  String _timestamp(double seconds) {
    final value = seconds.toInt();
    return '${value ~/ 60}:${(value % 60).toString().padLeft(2, '0')}';
  }

  String _episodeSummary(Json episode, {required bool next}) {
    final date = '${episode['airdate'] ?? episode['airDate'] ?? ''}';
    final available = _available(episode);
    return [
      '${next ? '下一话 ' : ''}EP${episode['sort']}',
      if (titleOf(episode).isNotEmpty) titleOf(episode),
      if (_isResume(episode))
        '续播 ${_timestamp(number(widget.resume?['positionSeconds']))}'
      else if (!_aired(episode))
        '未播出'
      else
        _episodeStatus(episode) == 'watched' ? '已看' : '未看',
      if (available != null) available ? '已缓存' : '未缓存',
      if (date.isNotEmpty) date,
    ].join(' · ');
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
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: cards[0]),
                        const SizedBox(width: Gap.lg),
                        Expanded(child: cards[1]),
                      ],
                    ),
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

  Widget _lower(Json item) {
    final subjectId = number(item['subjectId']).toInt();
    final user = widget.community.account.userId;
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

  Widget _hero(Json item) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final episodes = objects(item['episodes']);
    final watched = episodes
        .where((e) => _episodeStatus(e) == 'watched')
        .length;
    final total = number(item['episodeTotal'] ?? episodes.length).toInt();
    final next = _nextEpisode(episodes);
    final playLabel = _episodesLoading
        ? '加载剧集…'
        : next == null
        ? '暂无剧集'
        : '${_isResume(next)
              ? '继续播放'
              : episodes.isNotEmpty && watched == episodes.length
              ? '重看'
              : '播放'} EP${next['sort']}';
    final date = DateTime.tryParse('${item['airDate']}');
    const seasons = ['WINTER', 'SPRING', 'SUMMER', 'AUTUMN'];
    final score = number(item['score']);
    final summary =
        '${item['summary'] ?? (_loadingPart('subject') ? '正在加载简介…' : '暂无简介')}';
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(titleOf(item), style: text.titleLarge)),
            IconButton(
              tooltip: '在 Bangumi 打开',
              onPressed: () => _openLink(
                Uri.parse('https://bgm.tv/subject/${item['subjectId']}'),
              ),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
            ),
          ],
        ),
        if ('${item['name'] ?? ''}'.isNotEmpty && item['name'] != titleOf(item))
          Text('${item['name']}', style: text.bodySmall),
        const SizedBox(height: Gap.md),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            if (date != null) ...[
              MelonBadge('${date.year}', color: coral),
              MelonBadge(seasons[(date.month - 1) ~/ 3], color: coral),
            ] else if (item['airDate'] != null)
              MelonBadge('${item['airDate']}', color: coral),
            MelonBadge('${item['platform'] ?? '动画'}', color: sky),
            for (final tag in objects(
              item['tags'],
            ).where((tag) => tag['name'] != (item['platform'] ?? '动画')).take(3))
              MelonBadge('${tag['name']}', color: grape),
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
            if (item['rank'] != null || item['ratingCount'] != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (item['rank'] != null)
                    Text('#${item['rank']} Bangumi', style: text.bodySmall),
                  if (item['ratingCount'] != null)
                    Text('${item['ratingCount']} 人评分', style: text.bodySmall),
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
                    child: LinearProgressIndicator(
                      value: total == 0 ? 0 : watched / total,
                      minHeight: 6,
                      color: mint,
                      backgroundColor: scheme.surfaceContainerHigh,
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
        if (_summaryExpanded)
          SelectableText(
            summary,
            style: const TextStyle(fontSize: 13, height: 1.75),
          )
        else
          Text(
            summary.replaceAll(RegExp(r'\s+'), ' '),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, height: 1.75),
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
                        url: item['coverUrl'],
                        title: titleOf(item),
                        id: number(item['subjectId']).toInt(),
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

  Widget _episodeSection(List<Json> episodes, Json? next) {
    final text = Theme.of(context).textTheme;
    final hover = _hoverEpisode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('剧集', style: text.titleSmall),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Text(
                hover != null
                    ? _episodeSummary(hover, next: false)
                    : next != null
                    ? _episodeSummary(next, next: true)
                    : '',
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
            child: Text(
              _failedPart('episodes') ? '剧集加载失败，请重新打开详情重试。' : '暂无剧集信息',
            ),
          )
        else
          _EpisodeGrid(
            episodes: episodes,
            nextId: next?['episodeId'],
            statusOf: _episodeStatus,
            aired: _aired,
            onOpen: (episode) => widget.onFindResources(episode),
            onPlay: widget.onPlayEpisode,
            onLocal: widget.onOpenEpisode,
            onMark: (values, status) =>
                unawaited(_markEpisodes(values, status)),
            onHover: (episode) {
              if (episode?['episodeId'] != _hoverEpisode?['episodeId']) {
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

  static bool _aired(Json episode) {
    final date = DateTime.tryParse(
      '${episode['airdate'] ?? episode['airDate'] ?? ''}',
    );
    return date == null || !date.isAfter(DateTime.now());
  }

  Widget _collectionCard(Json item) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final status = _status;
    final score = number(_collection['score']).toInt();
    final comment = '${_collection['comment'] ?? ''}';
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
              child: MelonSegmentedControl<String>(
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
                    enabled: status != null && status != 'wish',
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
                    popular: objects(item['tags'])
                        .map((tag) => '${tag['name']}')
                        .take(16)
                        .toList(),
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
                _saveFields({
                  'status': 'completed',
                  'completeEpisodes': true,
                }, label: '已将全部正片标为已看'),
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

  Widget? _statsCard(Json item) {
    final stats = object(item['collectionStats']);
    final total = collectionLabels.keys.fold<int>(
      0,
      (sum, key) => sum + number(stats[key]).toInt(),
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
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 8,
              child: Row(
                children: [
                  for (final key in collectionLabels.keys)
                    if (number(stats[key]) > 0)
                      Expanded(
                        flex: math.max(1, number(stats[key]).toInt()),
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
                    _thousands(number(stats[key]).toInt()),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      fontFeatures: tabular,
                    ),
                  ),
                  SizedBox(
                    width: 52,
                    child: Text(
                      '${(number(stats[key]) * 100 / total).toStringAsFixed(1)}%',
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

  Widget? _infoPanel(Json item) {
    final rows = objects(item['infoBox']);
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
          for (final row in shown)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3.5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 76,
                    child: Text('${row['key']}', style: small),
                  ),
                  Expanded(
                    child: SelectableText(
                      key: PageStorageKey(
                        'subject-info:${item['subjectId']}:${row['key']}',
                      ),
                      '${row['value']}',
                      style: const TextStyle(fontSize: 12),
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

  Widget? _charactersPanel(Json item) => _peoplePanel(
    item,
    characters: true,
    loading: _loadingPart('characters'),
    failed: _failedPart('characters'),
  );

  Widget? _staffPanel(Json item) => _peoplePanel(
    item,
    characters: false,
    loading: _loadingPart('staff'),
    failed: _failedPart('staff'),
  );

  Widget? _peoplePanel(
    Json item, {
    required bool characters,
    required bool loading,
    required bool failed,
  }) {
    final people = _peopleList(item, characters);
    if (people.isEmpty && !loading && !failed) return null;
    final heading = characters ? '角色与配音' : '制作团队';
    final limit = characters ? 8 : 12;
    return MelonPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  heading,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (people.length > limit)
                TextButton(
                  onPressed: () => _allPeople(heading, people, characters),
                  child: Text('全部 ${people.length} 位'),
                ),
            ],
          ),
          const SizedBox(height: Gap.md),
          if (people.isEmpty)
            Text(
              loading ? '正在加载$heading…' : '$heading加载失败。',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final columns =
                    (constraints.maxWidth / (characters ? 210 : 230))
                        .floor()
                        .clamp(1, 4);
                final gap = characters ? 10.0 : 24.0;
                final width =
                    (constraints.maxWidth - (columns - 1) * gap) / columns -
                    .01;
                return Wrap(
                  spacing: gap,
                  runSpacing: characters ? 10 : 0,
                  children: [
                    for (final person in people.take(limit))
                      SizedBox(
                        width: width,
                        child: characters
                            ? _credit(person, character: true)
                            : _staffRow(person),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  void _allPeople(String heading, List<Json> people, bool characters) =>
      showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          child: SizedBox(
            width: 660,
            height: 600,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$heading · ${people.length} 位',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭人物列表',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      itemCount: people.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, index) => characters
                          ? _credit(people[index], character: true)
                          : _staffRow(people[index]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  List<Json> _peopleList(Json item, bool characters) {
    final values = objects(item[characters ? 'characters' : 'staff']);
    if (characters) {
      return [
        ...values.where((p) => p['role'] == '主角'),
        ...values.where((p) => p['role'] != '主角'),
      ];
    }
    const roles = ['原作', '导演', '系列构成', '人物设定', '音乐', '动画制作', '总作画监督', '脚本'];
    final combined = <String, Json>{};
    for (final person in values) {
      final key = '${person['personId'] ?? person['id'] ?? titleOf(person)}';
      final old = combined[key];
      final role = '${person['role'] ?? person['relation'] ?? ''}';
      if (old == null) {
        combined[key] = {
          ...person,
          'roles': <String>[if (role.isNotEmpty) role],
        };
      } else {
        final positions = old['roles'] as List<String>;
        if (role.isNotEmpty && !positions.contains(role)) positions.add(role);
        if (_image(old) == null && _image(person) != null) {
          old['imageUrl'] = _image(person);
        }
      }
    }
    int priority(String role) =>
        roles.contains(role) ? roles.indexOf(role) : roles.length;
    final people = combined.values.toList();
    for (final person in people) {
      final positions = person['roles'] as List<String>;
      positions.sort((a, b) => priority(a).compareTo(priority(b)));
      person['role'] = positions.join(' · ');
    }
    people.sort((a, b) {
      final aRoles = a['roles'] as List<String>,
          bRoles = b['roles'] as List<String>;
      return priority(aRoles.firstOrNull ?? '')
          .compareTo(priority(bRoles.firstOrNull ?? ''));
    });
    return people;
  }

  String? _image(Json person) {
    final images = object(person['images']);
    for (final value in [
      person['imageUrl'],
      person['coverUrl'],
      images['medium'],
      images['common'],
      images['large'],
      images['small'],
      images['grid'],
    ]) {
      if (value is String && value.isNotEmpty) return value;
    }
    return null;
  }

  Uri _personLink(Json person, {required bool character}) {
    final id = number(
      person[character ? 'characterId' : 'personId'] ?? person['id'],
    ).toInt();
    return id > 0
        ? Uri.parse('https://bgm.tv/${character ? 'character' : 'person'}/$id')
        : Uri.parse(
            'https://bgm.tv/subject/${widget.subject?['subjectId']}/${character ? 'characters' : 'persons'}',
          );
  }

  Widget _avatar(Json person, {bool character = false, double size = 42}) {
    final url = _image(person);
    final width = character ? 44.0 : size, height = character ? 60.0 : size;
    Widget placeholder(String label) => Tooltip(
      message: label,
      child: character
          ? MouseRegion(
              cursor: SystemMouseCursors.basic,
              child: GestureDetector(
                // Consume the tap instead of opening the surrounding card.
                onTap: () {},
                excludeFromSemantics: true,
                child: ArtPlaceholder(label: label),
              ),
            )
          : ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              child: Center(
                child: Icon(
                  character
                      ? Icons.face_outlined
                      : Icons.person_outline_rounded,
                  size: math.min(width, height) * .5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
    );
    Widget preview(Widget image) {
      if (!character || url == null) return image;
      return Tooltip(
        message: '查看${titleOf(person)}完整立绘',
        child: InkWell(
          borderRadius: badgeBorderRadius,
          onTap: () => showDialog<void>(
            context: context,
            builder: (context) => Dialog(
              child: SizedBox(
                width: 520,
                height: 620,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              titleOf(person),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          IconButton(
                            tooltip: '关闭图片',
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: InteractiveViewer(
                          child: Image(
                            image: cachedImageProvider(context, url),
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) =>
                                const Center(child: Text('图片加载失败')),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          child: image,
        ),
      );
    }

    return Semantics(
      label: '${titleOf(person)}${character ? '角色头像' : '人物头像'}',
      image: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(character ? 8 : size / 2),
        child: SizedBox(
          width: width,
          height: height,
          child: url == null
              ? placeholder('暂无头像')
              : Image(
                  image: cachedImageProvider(
                    context,
                    url,
                    cacheWidth: imageDecodeWidth(context, width),
                  ),
                  fit: character ? BoxFit.contain : BoxFit.cover,
                  alignment: character ? Alignment.topCenter : Alignment.center,
                  frameBuilder: (_, child, frame, synchronous) =>
                      frame == null && !synchronous
                      ? placeholder('正在加载头像')
                      : preview(child),
                  errorBuilder: (_, _, _) => placeholder('头像加载失败'),
                ),
        ),
      ),
    );
  }

  Widget _credit(Json person, {required bool character}) {
    final actors = objects(person['actors']);
    final role = '${person['role'] ?? person['relation'] ?? ''}';
    final small = Theme.of(context).textTheme.bodySmall;
    final actorName = actors.isNotEmpty
        ? actors.map(titleOf).join('、')
        : '${person['actorName'] ?? ''}';
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: controlBorderRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openLink(_personLink(person, character: character)),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _avatar(person, character: character),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titleOf(person),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      role.isEmpty ? '角色' : role,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: small,
                    ),
                    if (actorName.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (actors.isNotEmpty) ...[
                            _avatar(actors.first, size: 18),
                            const SizedBox(width: 5),
                          ],
                          Expanded(
                            child: Text(
                              actors.isEmpty ? 'CV $actorName' : actorName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: small,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _staffRow(Json person) {
    final role = '${person['role'] ?? person['relation'] ?? ''}';
    return InkWell(
      borderRadius: badgeBorderRadius,
      onTap: () => _openLink(_personLink(person, character: false)),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 92,
              child: Text(
                role.isEmpty ? '制作人员' : role,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Text(
                titleOf(person),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      ),
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
              Text(
                '${widget.tags.length} / $collectionTagLimit · 点一下添加或取消，立即保存',
                style: small,
              ),
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

/// All episodes as numbered cells. Click opens the episode's resources,
/// right-click offers more, and a long press marks; while still pressed,
/// dragging selects the range from the pressed cell to the pointer, so
/// dragging back shrinks it. Releasing well outside the cells, the right
/// button or Escape cancels the pending mark.
class _EpisodeGrid extends StatefulWidget {
  const _EpisodeGrid({
    required this.episodes,
    required this.nextId,
    required this.statusOf,
    required this.aired,
    required this.onOpen,
    required this.onPlay,
    required this.onLocal,
    required this.onMark,
    required this.onHover,
  });
  final List<Json> episodes;
  final Object? nextId;
  final String Function(Json) statusOf;
  final bool Function(Json) aired;
  final ValueChanged<Json> onOpen, onPlay, onLocal;
  final void Function(List<Json> episodes, String status) onMark;
  final ValueChanged<Json?> onHover;

  @override
  State<_EpisodeGrid> createState() => _EpisodeGridState();
}

class _EpisodeGridState extends State<_EpisodeGrid> {
  static const _gap = 6.0, _minWidth = 40.0, _height = 30.0, _rows = 4;
  static const _cancelMargin = 48.0;
  bool expanded = false;
  int? hovered;

  /// Pending mark while a long press is held: the range between the pressed
  /// and the current episode, by id so it survives data refreshes.
  String? dragStatus;
  int? anchorId, currentId;
  bool outside = false;

  Set<int> get dragIds {
    if (dragStatus == null) return const {};
    final ids = [for (final episode in widget.episodes) _id(episode)];
    final a = ids.indexOf(anchorId!), b = ids.indexOf(currentId!);
    if (a < 0 || b < 0) return const {};
    return ids.sublist(math.min(a, b), math.max(a, b) + 1).toSet();
  }

  static int _id(Json episode) => number(episode['episodeId']).toInt();

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _cancel();
      return true;
    }
    return false;
  }

  void _start(Json episode) {
    HardwareKeyboard.instance.addHandler(_onKey);
    setState(() {
      dragStatus = widget.statusOf(episode) == 'watched'
          ? 'unwatched'
          : 'watched';
      outside = false;
      anchorId = currentId = _id(episode);
    });
  }

  void _cancel() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    if (dragStatus == null) return;
    setState(() {
      dragStatus = null;
    });
  }

  void _end() {
    final status = dragStatus;
    final commit = status != null && !outside;
    final dragIds = this.dragIds;
    final episodes = [
      for (final episode in widget.episodes)
        if (dragIds.contains(_id(episode)) &&
            widget.statusOf(episode) != status)
          episode,
    ];
    _cancel();
    if (commit && episodes.isNotEmpty) widget.onMark(episodes, status);
  }

  Future<void> _menu(Offset position, Json episode) async {
    final watched = widget.statusOf(episode) == 'watched';
    final action = await showMenu<String>(
      context: context,
      color: menuSurface(context),
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem(value: 'play', child: Text('播放 EP${episode['sort']}')),
        const PopupMenuItem(value: 'resources', child: Text('查看资源')),
        PopupMenuItem(value: 'mark', child: Text(watched ? '标为未看' : '标为已看')),
        const PopupMenuItem(value: 'local', child: Text('打开本地文件并关联')),
      ],
    );
    switch (action) {
      case 'play':
        widget.onPlay(episode);
      case 'resources':
        widget.onOpen(episode);
      case 'mark':
        widget.onMark([episode], watched ? 'unwatched' : 'watched');
      case 'local':
        widget.onLocal(episode);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = math.max(
          1,
          ((constraints.maxWidth + _gap) / (_minWidth + _gap)).floor(),
        );
        final width =
            (constraints.maxWidth - _gap * (columns - 1)) / columns - .01;
        final episodes = widget.episodes;
        final rows = (episodes.length / columns).ceil();
        final collapsible = rows > _rows;
        var first = 0, count = episodes.length;
        if (collapsible && !expanded) {
          final next = episodes.indexWhere(
            (e) => e['episodeId'] == widget.nextId,
          );
          final row = ((next < 0 ? 0 : next) ~/ columns - 1).clamp(
            0,
            rows - _rows,
          );
          first = row * columns;
          count = math.min(episodes.length - first, _rows * columns);
        }
        final visible = episodes.sublist(first, first + count);
        final visibleRows = (visible.length / columns).ceil();
        final gridHeight = visibleRows * (_height + _gap) - _gap;
        int? indexAt(Offset position) {
          if (position.dx < 0 || position.dy < 0) return null;
          final column = (position.dx / (width + _gap)).floor();
          final row = (position.dy / (_height + _gap)).floor();
          if (column >= columns) return null;
          final index = row * columns + column;
          return index < visible.length ? index : null;
        }

        final selected = dragIds;
        void drag(Offset position) {
          if (dragStatus == null) return;
          final away =
              position.dx < -_cancelMargin ||
              position.dy < -_cancelMargin ||
              position.dx > constraints.maxWidth + _cancelMargin ||
              position.dy > gridHeight + _cancelMargin;
          final index = indexAt(position);
          final id = index == null || away ? currentId : _id(visible[index]);
          if (away == outside && id == currentId) return;
          setState(() {
            outside = away;
            currentId = id;
          });
        }

        Widget cell(int index) {
          final episode = visible[index];
          final status = selected.contains(_id(episode))
              ? dragStatus!
              : widget.statusOf(episode);
          final watched = status == 'watched';
          final next = !watched && episode['episodeId'] == widget.nextId;
          final aired = widget.aired(episode);
          final Color background, foreground;
          if (next) {
            background = scheme.primary;
            foreground = scheme.onPrimary;
          } else if (watched) {
            background = scheme.primaryContainer;
            foreground = scheme.onPrimaryContainer;
          } else {
            background = Colors.transparent;
            foreground = scheme.onSurfaceVariant.withValues(
              alpha: aired ? 1 : .45,
            );
          }
          final label = isMainEpisode(episode)
              ? '${episode['sort']}'
              : '${const {1: 'SP', 2: 'OP', 3: 'ED'}[episode['type']] ?? 'SP'}${episode['sort']}';
          return Semantics(
            button: true,
            label: 'EP${episode['sort']} ${watched ? '已看' : '未看'}',
            onTap: () => widget.onOpen(episode),
            child: AnimatedContainer(
              duration: motionDuration(context, 120),
              width: width,
              height: _height,
              decoration: BoxDecoration(
                color: background,
                borderRadius: badgeBorderRadius,
                border: Border.all(
                  color: hovered == index && dragStatus == null
                      ? scheme.primary
                      : watched || next
                      ? background
                      : scheme.outlineVariant,
                ),
              ),
              child: Center(
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: foreground,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          );
        }

        Widget swatch(Color fill, Color border) => Container(
          width: 12,
          height: 12,
          margin: const EdgeInsets.only(right: 5),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: border),
          ),
        );
        Widget legend(Widget mark, String text) =>
            Row(mainAxisSize: MainAxisSize.min, children: [mark, Text(text)]);
        final target = dragStatus == 'watched' ? '已看' : '未看';
        final String hint;
        if (dragStatus == null) {
          hint = '点击查看资源 · 长按标为已看 · 右键更多';
        } else if (outside) {
          hint = '已移出选集区域，松开将取消';
        } else {
          hint = '已选 ${selected.length} 话，松开标为$target · 按住拖动调整范围 · 右键或 Esc 取消';
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Listener(
              onPointerDown: (event) {
                if (event.buttons & kSecondaryMouseButton != 0) _cancel();
              },
              onPointerMove: (event) {
                if (event.buttons & kSecondaryMouseButton != 0) _cancel();
              },
              child: RawGestureDetector(
                gestures: {
                  TapGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                        TapGestureRecognizer
                      >(
                        TapGestureRecognizer.new,
                        (recognizer) => recognizer
                          ..onTapUp = (details) {
                            final index = indexAt(details.localPosition);
                            if (index != null) widget.onOpen(visible[index]);
                          }
                          ..onSecondaryTapUp = (details) {
                            final index = indexAt(details.localPosition);
                            if (index != null && dragStatus == null) {
                              unawaited(
                                _menu(details.globalPosition, visible[index]),
                              );
                            }
                          },
                      ),
                  LongPressGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                        LongPressGestureRecognizer
                      >(
                        () => LongPressGestureRecognizer(
                          duration: const Duration(milliseconds: 600),
                        ),
                        (recognizer) => recognizer
                          ..onLongPressStart = (details) {
                            final index = indexAt(details.localPosition);
                            if (index != null) _start(visible[index]);
                          }
                          ..onLongPressMoveUpdate = (details) {
                            drag(details.localPosition);
                          }
                          ..onLongPressEnd = (_) {
                            _end();
                          }
                          ..onLongPressCancel = _cancel,
                      ),
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  onHover: (event) {
                    final index = indexAt(event.localPosition);
                    if (index != hovered) {
                      setState(() => hovered = index);
                      widget.onHover(index == null ? null : visible[index]);
                    }
                  },
                  onExit: (_) {
                    setState(() => hovered = null);
                    widget.onHover(null);
                  },
                  child: Wrap(
                    spacing: _gap,
                    runSpacing: _gap,
                    children: [
                      for (var i = 0; i < visible.length; i++) cell(i),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: Gap.sm + 2),
            DefaultTextStyle.merge(
              style: small?.copyWith(fontSize: 11),
              child: Wrap(
                spacing: Gap.lg,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  legend(
                    swatch(scheme.primaryContainer, scheme.primaryContainer),
                    '已看',
                  ),
                  legend(swatch(scheme.primary, scheme.primary), '下一话'),
                  legend(
                    swatch(Colors.transparent, scheme.outlineVariant),
                    '未看',
                  ),
                  Text(
                    hint,
                    style: dragStatus == null
                        ? null
                        : TextStyle(
                            color: outside ? scheme.error : scheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                  ),
                  if (collapsible)
                    TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 28),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onPressed: () => setState(() => expanded = !expanded),
                      child: Text(
                        expanded ? '收起' : '展开全部 ${episodes.length} 话',
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/error_message.dart';
import '../../domain/catalog.dart';
import '../../domain/play_candidate.dart';
import '../../domain/playback_session.dart';
import '../../domain/transfer.dart';
import '../../features/acquisition/title_matching.dart';
import '../../features/playback/play_selection.dart';
import '../../features/playback/playback.dart';
import '../acquisition/download_labels.dart';
import '../acquisition/download_task_widgets.dart';
import '../core/account_avatar.dart';
import '../core/bbcode.dart';
import '../core/external_link.dart';
import '../core/motion.dart';
import '../core/selection_controls.dart';
import '../core/subject_posters.dart';
import '../core/theme.dart';
import '../tracking/episode_grid.dart';
import '../tracking/subject_community.dart';
import 'player_danmaku_panel.dart';

/// A download of one episode: a task cached for it, or the episode's video
/// in a batch; [file] is null until the task's files are known.
typedef EpisodeCache = ({DownloadTask task, DownloadFile? file});

extension on EpisodeCache {
  double get progress => file?.progress ?? task.progress;
  bool get complete => progress >= 1;

  /// Its video can be played, finished or streaming.
  bool get playable => file != null && task.playable;
}

enum PlayerPanelTab { episodes, discussion, danmaku }

/// The panel beside the video: the subject's episodes with the playing
/// source and cache, the episode's Bangumi comments, and danmaku sources.
/// It follows the app's light or dark theme.
class PlayerSidePanel extends StatefulWidget {
  const PlayerSidePanel({
    super.key,
    required this.playback,
    required this.community,
    required this.subject,
    required this.session,
    required this.source,
    required this.downloads,
    required this.tab,
    required this.onTab,
    required this.onEpisode,
    required this.onFindResources,
    required this.onPlayFile,
    required this.onToggleTask,
    required this.onMarkEpisode,
    required this.onOpenSubject,
    required this.onError,
    this.remembered,
    this.onForgetSource,
  });
  final Playback playback;
  final SubjectCommunitySource community;
  final Subject? subject;
  final PlaybackSession? session;

  /// The source chosen for the session, when one was.
  final PlayCandidate? source;

  /// The source the subject remembers for its next episodes.
  final RememberedSource? remembered;
  final VoidCallback? onForgetSource;
  final TransferSnapshot downloads;
  final PlayerPanelTab tab;
  final ValueChanged<PlayerPanelTab> onTab;
  final ValueChanged<Episode> onEpisode;
  final ValueChanged<Episode?> onFindResources;
  final void Function(String id, String? fileId) onPlayFile;
  final Future<void> Function(DownloadTask) onToggleTask;
  final Future<void> Function(Episode episode, bool watched) onMarkEpisode;
  final ValueChanged<Subject> onOpenSubject;
  final ValueChanged<Object> onError;

  @override
  State<PlayerSidePanel> createState() => _PlayerSidePanelState();
}

class _PlayerSidePanelState extends State<PlayerSidePanel> {
  Episode? get current => switch ((widget.subject, widget.session)) {
    (final subject?, PlaybackSession(:final episodeId?)) => subject.episode(
      episodeId,
    ),
    _ => null,
  };

  Future<void> mark(Episode episode, bool watched) async {
    try {
      await widget.onMarkEpisode(episode, watched);
    } catch (e) {
      widget.onError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    final subject = widget.subject;
    final episode = current;
    final linked = widget.session?.subjectId != null;
    final tab = linked ? widget.tab : PlayerPanelTab.danmaku;
    return Material(
      color: scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.md, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subject?.title ?? widget.session?.title ?? '播放器',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontSize: 15),
                      ),
                      if (episode != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          episodeLabel(episode),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: small,
                        ),
                      ],
                    ],
                  ),
                ),
                if (subject != null && linked) ...[
                  const SizedBox(width: Gap.sm),
                  _DetailButton(onPressed: () => widget.onOpenSubject(subject)),
                ],
              ],
            ),
          ),
          if (linked)
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, 0),
              child: MelonSegmentedControl<PlayerPanelTab>(
                options: const {
                  PlayerPanelTab.episodes: '剧集',
                  PlayerPanelTab.discussion: '讨论',
                  PlayerPanelTab.danmaku: '弹幕',
                },
                value: tab,
                onChanged: widget.onTab,
              ),
            ),
          Expanded(
            // Tabs cross-fade rather than cut.
            child: MotionSwap(
              value: tab,
              scale: 1,
              milliseconds: 200,
              alignment: Alignment.topCenter,
              child: SizedBox.expand(
                child: switch (tab) {
                  PlayerPanelTab.episodes => _EpisodesPane(
                    key: ValueKey('episodes:${widget.session?.subjectId}'),
                    subject: subject,
                    session: widget.session,
                    source: widget.source,
                    remembered: widget.remembered,
                    onForgetSource: widget.onForgetSource,
                    downloads: widget.downloads,
                    onEpisode: widget.onEpisode,
                    onFindResources: widget.onFindResources,
                    onPlayFile: widget.onPlayFile,
                    onToggleTask: widget.onToggleTask,
                    onMark: mark,
                  ),
                  PlayerPanelTab.discussion => _DiscussionPane(
                    key: ValueKey('discussion:${episode?.id}'),
                    community: widget.community,
                    episode: episode,
                  ),
                  PlayerPanelTab.danmaku => PlayerDanmakuPane(
                    playback: widget.playback,
                    onError: widget.onError,
                  ),
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `第 N 话  标题`, without a placeholder title.
String episodeLabel(Episode episode) => episode.title == '未命名'
    ? episode.placedLabel
    : '${episode.placedLabel}  ${episode.title}';

/// Leaves the player for the subject's detail page.
class _DetailButton extends StatelessWidget {
  const _DetailButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextButton.icon(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 30),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        backgroundColor: scheme.surfaceContainerHigh,
        foregroundColor: scheme.onSurface,
        shape: const RoundedRectangleBorder(borderRadius: badgeBorderRadius),
        textStyle: const TextStyle(fontSize: 12),
      ),
      onPressed: onPressed,
      icon: const Icon(Icons.info_outline_rounded, size: 15),
      label: const Text('番剧详情'),
    );
  }
}

/// The playing source, every episode as a cell, and the subject's cache.
class _EpisodesPane extends StatefulWidget {
  const _EpisodesPane({
    super.key,
    required this.subject,
    required this.session,
    required this.source,
    required this.downloads,
    required this.onEpisode,
    required this.onFindResources,
    required this.onPlayFile,
    required this.onToggleTask,
    required this.onMark,
    this.remembered,
    this.onForgetSource,
  });
  final Subject? subject;
  final PlaybackSession? session;
  final PlayCandidate? source;
  final RememberedSource? remembered;
  final VoidCallback? onForgetSource;
  final TransferSnapshot downloads;
  final ValueChanged<Episode> onEpisode;
  final ValueChanged<Episode?> onFindResources;
  final void Function(String id, String? fileId) onPlayFile;
  final Future<void> Function(DownloadTask) onToggleTask;
  final Future<void> Function(Episode episode, bool watched) onMark;

  @override
  State<_EpisodesPane> createState() => _EpisodesPaneState();
}

class _EpisodesPaneState extends State<_EpisodesPane> {
  static const columns = 6, cellHeight = 40.0, cellGap = 6.0;
  static const specialsHeader = 36.0;
  final scroll = ScrollController();
  Episode? hovered;
  bool tasksOpen = false;
  String? taskError;
  int? _revealed;

  List<Episode> get episodes => widget.subject?.episodes ?? const [];
  List<Episode> get main => [
    for (final episode in episodes)
      if (episode.main) episode,
  ];

  /// The specials by number as Bangumi lists them, under the main episodes.
  List<Episode> get specials =>
      episodes.where((e) => !e.main).toList()
        ..sort((a, b) => a.sort.compareTo(b.sort));
  int? get episodeId => widget.session?.episodeId;

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  /// Scrolls the playing episode into view once per episode.
  void reveal(double gridTop) {
    final id = episodeId;
    if (id == null || id == _revealed) return;
    final main = this.main;
    var index = main.indexWhere((episode) => episode.id == id);
    var top = gridTop;
    if (index < 0) {
      index = specials.indexWhere((episode) => episode.id == id);
      top +=
          (main.length / columns).ceil() * (cellHeight + cellGap) +
          specialsHeader;
    }
    if (index < 0) return;
    _revealed = id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scroll.hasClients) return;
      final position = scroll.position;
      final row = index ~/ columns;
      final target = top + row * (cellHeight + cellGap);
      if (target + cellHeight < position.viewportDimension) return;
      scroll.jumpTo(
        (target - position.viewportDimension * .3).clamp(
          0.0,
          position.maxScrollExtent,
        ),
      );
    });
  }

  Future<void> toggleTask(DownloadTask task) async {
    try {
      await widget.onToggleTask(task);
      if (mounted && taskError != null) setState(() => taskError = null);
    } catch (e) {
      if (mounted) setState(() => taskError = errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    final subject = widget.subject;
    final tasks = widget.downloads.forSubject(subject?.id);
    final byEpisode = <int, List<EpisodeCache>>{};
    for (final task in tasks) {
      final files = subject == null
          ? const <int, DownloadFile>{}
          : episodeFiles(subject, task);
      for (final MapEntry(key: id, value: file) in files.entries) {
        byEpisode.putIfAbsent(id, () => []).add((task: task, file: file));
      }
      if (task.episodeId case final id? when !files.containsKey(id)) {
        byEpisode.putIfAbsent(id, () => []).add((task: task, file: null));
      }
    }
    final shown =
        hovered ??
        episodes.where((episode) => episode.id == episodeId).firstOrNull;
    final source = sourceCard(context);
    // The card's height is not known here; scroll by an estimate of it.
    reveal(source == null ? 40 : 170);
    return CustomScrollView(
      controller: scroll,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, 0),
          sliver: SliverList.list(
            children: [
              ?source,
              if (source != null) const SizedBox(height: Gap.lg),
              SizedBox(
                height: 20,
                child: shown == null
                    ? Text(
                        episodes.isEmpty ? '暂无剧集信息' : '共 ${main.length} 话',
                        style: small,
                      )
                    : episodeLine(shown, byEpisode[shown.id] ?? const []),
              ),
              const SizedBox(height: Gap.sm),
            ],
          ),
        ),
        grid(main, byEpisode),
        if (specials case final specials when specials.isNotEmpty) ...[
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
            sliver: SliverToBoxAdapter(
              child: SizedBox(
                height: specialsHeader,
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: Gap.sm),
                    child: Tooltip(
                      message: specialsHelp,
                      child: Text('特别篇', style: small),
                    ),
                  ),
                ),
              ),
            ),
          ),
          grid(specials, byEpisode),
        ],
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.xl),
          sliver: SliverList.list(
            children: [
              if (episodes.isNotEmpty) legend(context),
              if (tasks.isNotEmpty) ...[
                const SizedBox(height: Gap.md),
                taskSection(context, tasks),
              ],
            ],
          ),
        ),
      ],
    );
  }

  bool aired(Episode episode) =>
      !(episode.aired?.isAfter(DateTime.now()) ?? false);

  /// The hovered or playing episode: title, then its state.
  Widget episodeLine(Episode episode, List<EpisodeCache> caches) {
    final small = Theme.of(context).textTheme.bodySmall;
    final cache =
        caches.where((cache) => cache.playable).firstOrNull ??
        caches.firstOrNull;
    final state = [
      if (episode.watched) '已看',
      if (!aired(episode)) '未更新',
      if (cache != null)
        cache.complete
            ? '已缓存'
            : '${downloadStatus(cache.task)} ${(cache.progress * 100).floor()}%',
    ].join('  ');
    return Row(
      children: [
        Expanded(
          child: Text(
            episodeLabel(episode),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
        ),
        if (state.isNotEmpty) ...[
          const SizedBox(width: Gap.sm),
          Text(state, style: small),
        ],
      ],
    );
  }

  Widget? sourceCard(BuildContext context) {
    final session = widget.session;
    if (session == null) return null;
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    final task = switch (session.downloadId) {
      final id? => widget.downloads.task(id),
      null => null,
    };
    final source = widget.source;
    final kind = switch (task?.method) {
      CacheMethod.bt => 'BT',
      CacheMethod.pikpak => 'PikPak',
      CacheMethod.online => '在线缓存',
      null => source?.kind.label ?? '在线',
    };
    final name = switch (source) {
      PlayCandidate(:final line) when line.isNotEmpty => line,
      PlayCandidate(:final providerLabel?) => providerLabel,
      _ => task?.releaseGroups.firstOrNull ?? task?.source,
    };
    final live = task == null
        ? null
        : task.complete
        ? '已缓存'
        : [
            '${session.streamId != null ? '边下边播' : downloadStatus(task)} '
                '${(task.progress * 100).floor()}%',
            if (task.status == DownloadStatus.downloading) ...[
              transferRate(task.downloadSpeed),
              if (task.method == CacheMethod.bt) '${task.swarm.peers} 个节点',
            ],
          ].join('  ');
    final episode = widget.subject?.episode(session.episodeId ?? -1);
    return Container(
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.xs, Gap.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: controlBorderRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  kind,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text(
                  [?name, ?source?.quality].join('  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              if (episode != null)
                TextButton(
                  onPressed: () => widget.onFindResources(episode),
                  child: const Text('换资源'),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: Gap.sm),
            child: Text(
              task?.title ?? source?.title ?? session.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: small,
            ),
          ),
          if (live != null) ...[
            const SizedBox(height: Gap.xs),
            Text(
              live,
              style: small?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
          if (task != null && !task.complete) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(right: Gap.sm),
              child: MotionValue(
                value: task.progress,
                builder: (context, value) => LinearProgressIndicator(
                  value: value,
                  minHeight: 2,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
          ],
          if (widget.remembered case final remembered?) ...[
            const SizedBox(height: Gap.xs),
            Row(
              children: [
                Icon(Icons.bookmark_outline, size: 14, color: small?.color),
                const SizedBox(width: Gap.xs),
                Expanded(
                  child: Tooltip(
                    message: '再看这部番时优先使用这个来源',
                    child: Text(
                      '已记住 ${remembered.label}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: small,
                    ),
                  ),
                ),
                if (widget.onForgetSource != null)
                  TextButton(
                    onPressed: widget.onForgetSource,
                    child: const Text('忘记'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget grid(List<Episode> episodes, Map<int, List<EpisodeCache>> caches) =>
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
        sliver: SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: cellGap,
            crossAxisSpacing: cellGap,
            mainAxisExtent: cellHeight,
          ),
          itemCount: episodes.length,
          itemBuilder: (_, index) =>
              cell(episodes[index], caches[episodes[index].id] ?? const []),
        ),
      );

  Widget cell(Episode episode, List<EpisodeCache> caches) {
    final scheme = Theme.of(context).colorScheme;
    final playing = episode.id == episodeId;
    final playable = caches.where((cache) => cache.playable).firstOrNull;
    final downloading = playable == null
        ? caches.where((cache) => !cache.complete).firstOrNull
        : null;
    final released = aired(episode);
    final cached = playable != null;
    final (background, foreground, border) = playing
        ? (scheme.primary, scheme.onPrimary, null)
        : episode.watched
        ? (scheme.primaryContainer, scheme.onPrimaryContainer, null)
        : !released
        ? (
            scheme.surfaceContainerHigh,
            scheme.onSurfaceVariant.withValues(alpha: .6),
            null,
          )
        : (
            Colors.transparent,
            scheme.onSurface,
            cached
                ? scheme.primary.withValues(alpha: .45)
                : scheme.outlineVariant,
          );
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = episode),
      onExit: (_) {
        if (hovered == episode) setState(() => hovered = null);
      },
      child: GestureDetector(
        onSecondaryTapUp: (details) =>
            menu(episode, details.globalPosition, playing),
        child: Material(
          color: background,
          shape: RoundedRectangleBorder(
            borderRadius: controlBorderRadius,
            side: border == null
                ? BorderSide.none
                : BorderSide(color: border, width: 1.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: playing ? null : () => widget.onEpisode(episode),
            child: Stack(
              children: [
                Center(
                  child: playing
                      ? Icon(
                          Icons.equalizer_rounded,
                          size: 18,
                          color: foreground,
                        )
                      : DefaultTextStyle.merge(
                          style: TextStyle(
                            fontSize: 13,
                            color: foreground,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                          child: EpisodeNumber(episode),
                        ),
                ),
                if (cached && !playing)
                  Positioned(
                    right: 5,
                    top: 5,
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: episode.watched
                            ? scheme.onPrimaryContainer
                            : scheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                if (downloading != null && !playing)
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 5,
                    child: MotionValue(
                      value: downloading.progress,
                      builder: (context, value) => LinearProgressIndicator(
                        value: value,
                        minHeight: 2,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> menu(Episode episode, Offset position, bool playing) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        if (!playing) const PopupMenuItem(value: 'play', child: Text('观看')),
        const PopupMenuItem(value: 'resources', child: Text('查找资源')),
        PopupMenuItem(
          value: 'mark',
          child: Text(episode.watched ? '标为未看' : '标为已看'),
        ),
      ],
    );
    switch (choice) {
      case 'play':
        widget.onEpisode(episode);
      case 'resources':
        widget.onFindResources(episode);
      case 'mark':
        await widget.onMark(episode, !episode.watched);
    }
  }

  Widget legend(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    Widget item(Widget mark, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: 4),
        Text(label, style: small),
      ],
    );
    Widget box(Color color) => Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
    );
    return Row(
      children: [
        Expanded(
          child: Wrap(
            spacing: Gap.md,
            runSpacing: Gap.xs,
            children: [
              item(box(scheme.primaryContainer), '已看'),
              item(
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                '已缓存',
              ),
              item(
                Container(width: 10, height: 2, color: scheme.primary),
                '下载中',
              ),
              item(box(scheme.surfaceContainerHigh), '未更新'),
            ],
          ),
        ),
        Tooltip(
          message: '点击观看：有缓存直接观看，否则按来源设置选择资源\n右键：查找资源、标为已看',
          child: Icon(
            Icons.help_outline_rounded,
            size: 16,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget taskSection(BuildContext context, List<DownloadTask> tasks) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    final active = tasks.where((task) => !task.complete).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, color: scheme.outlineVariant),
        InkWell(
          borderRadius: controlBorderRadius,
          onTap: () => setState(() => tasksOpen = !tasksOpen),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Gap.md),
            child: Row(
              children: [
                const Text('缓存任务', style: TextStyle(fontSize: 13)),
                const SizedBox(width: Gap.sm),
                Text(
                  [
                    '${tasks.length} 个',
                    if (active > 0) '$active 个进行中',
                  ].join('  '),
                  style: small,
                ),
                const Spacer(),
                ExpandChevron(
                  open: tasksOpen,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        MotionReveal(
          visible: tasksOpen,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (taskError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: Gap.sm),
                  child: Text(
                    taskError!,
                    style: TextStyle(color: scheme.error, fontSize: 12),
                  ),
                ),
              for (final task in tasks) taskTile(task),
            ],
          ),
        ),
      ],
    );
  }

  Widget taskTile(DownloadTask task) {
    final episode = widget.subject?.episode(task.episodeId ?? -1);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.sm),
      child: Ink(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: controlBorderRadius,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (task.coverUrl != null) ...[
                  SizedBox(
                    width: 28,
                    height: 38,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: SubjectCover(
                        url: task.coverUrl,
                        title: task.title,
                        id: task.subjectId ?? 0,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    episode == null ? task.title : episode.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                DownloadToggleButton(
                  task: task,
                  onToggle: toggleTask,
                  size: 18,
                ),
                DownloadPlayButton(task: task, onPlay: widget.onPlayFile),
              ],
            ),
            const SizedBox(height: 4),
            DownloadTaskStatus(task: task),
            if (task.errorMessage case final message?)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  message,
                  style: TextStyle(fontSize: 11, color: scheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The episode's Bangumi comments, oldest first like the site.
class _DiscussionPane extends StatefulWidget {
  const _DiscussionPane({
    super.key,
    required this.community,
    required this.episode,
  });
  final SubjectCommunitySource community;
  final Episode? episode;

  @override
  State<_DiscussionPane> createState() => _DiscussionPaneState();
}

class _DiscussionPaneState extends State<_DiscussionPane> {
  List<TopicPost>? posts;
  String? error;

  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load({bool refresh = false}) async {
    final episode = widget.episode;
    if (episode == null) return;
    if (refresh) {
      setState(() {
        error = null;
        posts = null;
      });
    }
    try {
      final result = await widget.community.episodeComments(
        episode.id,
        refresh: refresh,
      );
      if (mounted) setState(() => posts = result);
    } catch (e) {
      if (mounted) setState(() => error = errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    final episode = widget.episode;
    if (episode == null) {
      return Center(child: Text('这个视频没有对应的剧集', style: small));
    }
    final posts = this.posts;
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.sm, Gap.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              posts == null
                  ? 'Bangumi 本话吐槽'
                  : 'Bangumi 本话吐槽  ${posts.length} 条',
              style: small,
            ),
          ),
          TextButton.icon(
            onPressed: () =>
                openExternal(context, 'https://bgm.tv/ep/${episode.id}'),
            icon: const Icon(Icons.open_in_new, size: 15),
            label: const Text('在 Bangumi 打开'),
          ),
        ],
      ),
    );
    final Widget body;
    if (error != null) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('吐槽加载失败', style: small),
            TextButton(
              onPressed: () => load(refresh: true),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    } else if (posts == null) {
      body = const Center(
        child: SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    } else if (posts.isEmpty) {
      body = Center(child: Text('这一话还没有吐槽', style: small));
    } else {
      body = ListView.separated(
        padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.xl),
        itemCount: posts.length,
        separatorBuilder: (_, _) => Divider(
          height: 1,
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        itemBuilder: (_, index) =>
            _Comment(post: posts[index], floor: index + 1),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Expanded(child: body),
      ],
    );
  }
}

class _Comment extends StatefulWidget {
  const _Comment({required this.post, required this.floor});
  final TopicPost post;
  final int floor;

  @override
  State<_Comment> createState() => _CommentState();
}

class _CommentState extends State<_Comment> {
  static const _preview = 2;
  bool all = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final post = widget.post;
    final replies = post.replies;
    final shown = all ? replies : replies.take(_preview).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gap.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AccountAvatar(url: post.avatarUrl, name: post.author, size: 28),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _byline(context, post, '#${widget.floor}'),
                const SizedBox(height: 2),
                _text(context, post),
                if (replies.isNotEmpty) ...[
                  const SizedBox(height: Gap.sm),
                  Container(
                    padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: badgeBorderRadius,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (index, reply) in shown.indexed)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _byline(
                                  context,
                                  reply,
                                  '#${widget.floor}-${index + 1}',
                                ),
                                const SizedBox(height: 2),
                                _text(context, reply),
                              ],
                            ),
                          ),
                        if (replies.length > _preview)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              style: TextButton.styleFrom(
                                minimumSize: const Size(0, 28),
                                padding: EdgeInsets.zero,
                              ),
                              onPressed: () => setState(() => all = !all),
                              child: Text(
                                all
                                    ? '收起回复'
                                    : '还有 ${replies.length - _preview} 条回复',
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _byline(BuildContext context, TopicPost post, String floor) {
    final small = Theme.of(context).textTheme.bodySmall;
    return Row(
      children: [
        Flexible(
          child: Text(
            post.author,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: small?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        const SizedBox(width: Gap.sm),
        Text(floor, style: small),
        const Spacer(),
        Text(
          communityDate(post.time),
          style: small?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  Widget _text(BuildContext context, TopicPost post) =>
      post.content.trim().isEmpty
      ? Text('（内容已删除）', style: Theme.of(context).textTheme.bodySmall)
      : BBCode(
          post.content,
          style: const TextStyle(fontSize: 13, height: 1.55),
        );
}

/// Room the panel takes beside the video.
double sidePanelWidth(double contentWidth) =>
    math.min(contentWidth < 900 ? 296.0 : 336.0, contentWidth * .45);

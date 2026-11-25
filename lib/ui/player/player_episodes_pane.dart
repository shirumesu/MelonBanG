import 'package:flutter/material.dart';

import '../../core/error_message.dart';
import '../../domain/catalog.dart';
import '../../domain/play_candidate.dart';
import '../../domain/playback_session.dart';
import '../../domain/transfer.dart';
import '../../features/acquisition/title_matching.dart';
import '../../features/playback/play_ranking.dart';
import '../core/action_feedback.dart';
import '../core/byte_units.dart';
import '../core/help_hint.dart';
import '../core/motion.dart';
import '../core/subject_cover.dart';
import '../core/theme.dart';
import '../downloads/download_labels.dart';
import '../downloads/download_task_widgets.dart';
import '../tracking/episode_grid.dart';

/// A download of one episode: a task cached for it, or the episode's video
/// in a batch; `file` is null until the task's files are known.
typedef EpisodeCache = ({DownloadTask task, DownloadFile? file});

extension on EpisodeCache {
  double get progress => file?.progress ?? task.progress;
  bool get complete => progress >= 1;

  /// Its video can be played, finished or streaming.
  bool get playable => file != null && task.playable;
}

/// `第 N 话  标题`, without a placeholder title.
String episodeLabel(Episode episode) => episode.title == '未命名'
    ? episode.placedLabel
    : '${episode.placedLabel}  ${episode.title}';

/// The playing source, every episode as a cell, and the subject's cache.
class PlayerEpisodesPane extends StatefulWidget {
  const PlayerEpisodesPane({
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
    required this.onForgetSource,
  });
  final Subject? subject;
  final PlaybackSession? session;
  final PlayCandidate? source;
  final RememberedSource? remembered;
  final VoidCallback onForgetSource;
  final TransferSnapshot downloads;
  final ValueChanged<Episode> onEpisode;
  final ValueChanged<Episode?> onFindResources;
  final void Function(String id, String? fileId) onPlayFile;
  final Future<void> Function(DownloadTask) onToggleTask;
  final Future<void> Function(Episode episode, bool watched) onMark;

  @override
  State<PlayerEpisodesPane> createState() => _PlayerEpisodesPaneState();
}

class _PlayerEpisodesPaneState extends State<PlayerEpisodesPane> {
  static const columns = 6, cellHeight = 40.0, cellGap = 8.0;
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
    final shown = hovered;
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
            style: const TextStyle(fontSize: FontSize.body),
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
    // Only a torrent's file name says more than the episode.
    final torrent = switch (task?.method) {
      CacheMethod.bt || CacheMethod.pikpak => true,
      CacheMethod.online => false,
      null => source?.kind == PlayKind.bt || source?.kind == PlayKind.pikpak,
    };
    final name =
        source?.sourceLabel ?? task?.releaseGroups.firstOrNull ?? task?.source;
    final live = task == null || task.complete
        ? null
        : transferLine(
            task,
            ByteUnitsScope.of(context),
            status:
                '${session.streamId != null ? '边下边播' : downloadStatus(task)} '
                '${(task.progress * 100).floor()}%',
          );
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
                padding: const EdgeInsets.symmetric(
                  horizontal: Gap.xs,
                  vertical: 1,
                ),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: badgeBorderRadius,
                ),
                child: Text(
                  kind,
                  style: TextStyle(
                    fontSize: FontSize.caption,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text(
                  name ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: FontSize.body),
                ),
              ),
              if (episode != null)
                TextButton(
                  onPressed: () => widget.onFindResources(episode),
                  child: const Text('换资源'),
                ),
            ],
          ),
          if (torrent)
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
            const SizedBox(height: Gap.sm),
            Padding(
              padding: const EdgeInsets.only(right: Gap.sm),
              child: MotionValue(
                value: task.progress,
                builder: (context, value) => LinearProgressIndicator(
                  value: value,
                  minHeight: 2,
                  borderRadius: pillBorderRadius,
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
    final (background, foreground, outline) = playing
        ? (scheme.primary, scheme.onPrimary, null)
        : episode.watched
        ? (scheme.primaryContainer, scheme.onPrimaryContainer, null)
        : !released
        ? (
            scheme.surfaceContainerHigh,
            scheme.onSurfaceVariant.withValues(alpha: .6),
            null,
          )
        : (Colors.transparent, scheme.onSurface, scheme.outlineVariant);
    // A cache shows as a primary outline on any cell but the playing one.
    final border = cached && !playing
        ? scheme.primary.withValues(alpha: .45)
        : outline;
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
            // An episode not yet aired plays only from a cache, perhaps of
            // an early broadcast; otherwise its resources may have one.
            onTap: playing
                ? null
                : released || caches.isNotEmpty
                ? () => widget.onEpisode(episode)
                : () => widget.onFindResources(episode),
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
                            fontSize: FontSize.body,
                            color: foreground,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                          child: EpisodeNumber(episode),
                        ),
                ),
                if (downloading != null && !playing)
                  Positioned(
                    left: Gap.sm,
                    right: Gap.sm,
                    bottom: Gap.xs,
                    child: MotionValue(
                      value: downloading.progress,
                      builder: (context, value) => LinearProgressIndicator(
                        value: value,
                        minHeight: 2,
                        borderRadius: pillBorderRadius,
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
      popUpAnimationStyle: AnimationStyle(
        duration: motionDuration(context, 150),
        reverseDuration: motionDuration(context, 100),
        curve: Curves.easeOutCubic,
      ),
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
        const SizedBox(width: Gap.xs),
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
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: scheme.primary.withValues(alpha: .45),
                      width: 1.5,
                    ),
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
        const HelpHint(message: '点击观看：有缓存直接观看，否则按来源设置选择资源\n右键：查找资源、标为已看'),
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
                const Text('缓存任务', style: TextStyle(fontSize: FontSize.body)),
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
                  child: InlineIssue(taskError!),
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
        padding: const EdgeInsets.all(Gap.md),
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
                    child: CoverFrame(
                      radius: tightBorderRadius,
                      child: SubjectCover(
                        url: task.coverUrl,
                        title: task.title,
                        id: task.subjectId ?? 0,
                      ),
                    ),
                  ),
                  const SizedBox(width: Gap.sm),
                ],
                Expanded(
                  child: Text(
                    episode == null ? task.title : episode.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: FontSize.small),
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
            const SizedBox(height: Gap.xs),
            DownloadTaskStatus(task: task),
            if (task.errorMessage case final message?)
              Padding(
                padding: const EdgeInsets.only(top: Gap.xs),
                child: InlineIssue(message),
              ),
          ],
        ),
      ),
    );
  }
}

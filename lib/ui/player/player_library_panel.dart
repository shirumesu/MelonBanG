import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/catalog.dart';
import '../../domain/transfer.dart';
import '../acquisition/download_labels.dart';
import '../acquisition/download_task_widgets.dart';
import '../core/selection_controls.dart';
import '../core/subject_posters.dart';
import '../core/theme.dart';

/// A task whose single video file can be played (finished or streaming).
DownloadTask? playableTask(List<DownloadTask> tasks, int episodeId) => tasks
    .where(
      (task) =>
          task.episodeId == episodeId &&
          task.playable &&
          task.videos.length == 1,
    )
    .firstOrNull;

/// Episode list and this subject's cache tasks, beside the video.
class PlayerLibraryPanel extends StatefulWidget {
  const PlayerLibraryPanel({
    super.key,
    required this.onToggleTask,
    required this.subjectId,
    required this.subject,
    required this.episodeId,
    required this.title,
    required this.downloads,
    required this.onEpisode,
    required this.onFindResources,
    required this.onPlayFile,
  });
  final Future<void> Function(DownloadTask) onToggleTask;
  final int? subjectId, episodeId;
  final Subject? subject;
  final String title;
  final TransferSnapshot downloads;
  final ValueChanged<Episode> onEpisode;
  final ValueChanged<Episode?> onFindResources;
  final void Function(String id, String? fileId) onPlayFile;
  @override
  State<PlayerLibraryPanel> createState() => _PlayerLibraryPanelState();
}

class _PlayerLibraryPanelState extends State<PlayerLibraryPanel> {
  final episodeScroll = ScrollController();
  static const episodeHeight = 58.0;
  final tasksByEpisode = <int?, List<DownloadTask>>{};
  List<DownloadTask> _tasks = [];
  String tab = 'episodes';
  String? error;
  List<Episode> episodes = [];
  final episodesById = <int?, Episode>{};

  void indexEpisodes() {
    episodes = widget.subject?.episodes ?? const [];
    episodesById.clear();
    for (final episode in episodes) {
      episodesById[episode.id] = episode;
    }
  }

  List<DownloadTask> get tasks => _tasks;

  void indexDownloads() {
    _tasks = widget.downloads.forSubject(widget.subjectId);
    tasksByEpisode.clear();
    for (final task in _tasks) {
      tasksByEpisode.putIfAbsent(task.episodeId, () => []).add(task);
    }
  }

  @override
  void dispose() {
    episodeScroll.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    indexDownloads();
    indexEpisodes();
    revealCurrent();
  }

  @override
  void didUpdateWidget(PlayerLibraryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.downloads != widget.downloads ||
        oldWidget.subjectId != widget.subjectId) {
      indexDownloads();
    }
    if (oldWidget.subject != widget.subject) indexEpisodes();
    if (oldWidget.episodeId != widget.episodeId ||
        oldWidget.subject != widget.subject) {
      revealCurrent();
    }
  }

  void revealCurrent() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted || !episodeScroll.hasClients || tab == 'tasks') return;
    final index = episodes.indexWhere(
      (episode) => episode.id == widget.episodeId,
    );
    if (index < 0) return;
    final position = episodeScroll.position;
    episodeScroll.jumpTo(
      (index * episodeHeight - position.viewportDimension * .3).clamp(
        0.0,
        position.maxScrollExtent,
      ),
    );
  });

  Future<void> toggleTask(DownloadTask task) async {
    try {
      await widget.onToggleTask(task);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    final current = episodesById[widget.episodeId];
    final tasks = this.tasks;
    final showTasks = tab == 'tasks' && tasks.isNotEmpty;
    return Material(
      color: scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.sm, Gap.md),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.subject == null
                            ? widget.title
                            : widget.subject!.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontSize: 14),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        current == null
                            ? '正在播放'
                            : '第 ${current.number} 话 / 共 ${episodes.length} 话',
                        style: small,
                      ),
                    ],
                  ),
                ),
                if (widget.subjectId != null)
                  TextButton.icon(
                    onPressed: () => widget.onFindResources(current),
                    icon: const Icon(Icons.search_rounded, size: 17),
                    label: const Text('找资源'),
                  ),
              ],
            ),
          ),
          if (widget.subjectId == null)
            Padding(
              padding: const EdgeInsets.all(Gap.lg),
              child: Text('这个视频没有关联番剧', style: small),
            )
          else ...[
            if (tasks.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.sm),
                child: MelonSegmentedControl<String>(
                  options: {
                    'episodes': '选集 ${episodes.length}',
                    'tasks': '缓存 ${tasks.length}',
                  },
                  value: showTasks ? 'tasks' : 'episodes',
                  onChanged: (value) {
                    setState(() => tab = value);
                    if (value == 'episodes') revealCurrent();
                  },
                ),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Gap.lg,
                  vertical: Gap.sm,
                ),
                child: Text(
                  error!,
                  style: TextStyle(color: scheme.error, fontSize: 12),
                ),
              ),
            Expanded(
              child: showTasks
                  ? ListView.builder(
                      padding: const EdgeInsets.fromLTRB(
                        Gap.sm,
                        0,
                        Gap.sm,
                        Gap.lg,
                      ),
                      itemCount: tasks.length,
                      itemBuilder: (_, index) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
                        child: taskTile(tasks[index]),
                      ),
                    )
                  : episodes.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(Gap.sm),
                      child: Text('暂无剧集信息', style: small),
                    )
                  : ListView.builder(
                      controller: episodeScroll,
                      padding: const EdgeInsets.fromLTRB(
                        Gap.sm,
                        0,
                        Gap.sm,
                        Gap.lg,
                      ),
                      itemExtent: episodeHeight,
                      itemCount: episodes.length,
                      itemBuilder: (_, index) => episodeRow(episodes[index]),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  Widget episodeRow(Episode episode) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    final id = episode.id;
    final current = id == widget.episodeId;
    final related = tasksByEpisode[id] ?? const <DownloadTask>[];
    final complete = playableTask(related, id);
    final task = complete ?? related.firstOrNull;
    final available = current || complete != null;
    final status = current
        ? '正在播放'
        : available
        ? (task != null && !task.complete ? '可播放' : '已缓存')
        : task != null
        ? '${taskStatus(task)} ${(task.progress * 100).round()}%'
        : null;
    final title = episode.title;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: current
            ? scheme.primary.withValues(alpha: .12)
            : Colors.transparent,
        borderRadius: controlBorderRadius,
        child: InkWell(
          borderRadius: controlBorderRadius,
          onTap: current ? null : () => widget.onEpisode(episode),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Gap.sm, Gap.sm, Gap.xs, Gap.sm),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: current
                        ? scheme.primary
                        : available
                        ? scheme.surfaceContainerHighest
                        : Colors.transparent,
                    borderRadius: badgeBorderRadius,
                    border: available || current
                        ? null
                        : Border.all(color: scheme.outlineVariant),
                  ),
                  child: current
                      ? Icon(
                          Icons.equalizer_rounded,
                          size: 18,
                          color: scheme.onPrimary,
                        )
                      : Text(
                          episode.number,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: available
                                ? scheme.onSurface
                                : scheme.onSurfaceVariant,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title == '未命名' ? '第 ${episode.number} 话' : title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: current ? FontWeight.w700 : null,
                          color: current
                              ? scheme.primary
                              : available
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                      if (status != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          status,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: small?.copyWith(
                            fontSize: 11,
                            color: current || (available && task != null)
                                ? scheme.primary
                                : null,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => widget.onFindResources(episode),
                  child: const Text('资源'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget taskTile(DownloadTask task) {
    final episode = episodesById[task.episodeId];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Ink(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
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
                    episode == null ? task.title : '第 ${episode.number} 话',
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
                DownloadPlayButton(
                  task: task,
                  onPlay: widget.onPlayFile,
                  compact: true,
                ),
              ],
            ),
            const SizedBox(height: 4),
            DownloadTaskStatus(task: task),
            if (task.errorMessage case final message?)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  message,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String taskStatus(DownloadTask task) =>
    [?downloadOrigin(task), downloadStatus(task)].join(' ');

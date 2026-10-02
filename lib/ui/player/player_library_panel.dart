import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../data/bittorrent_settings.dart';
import '../core/selection_controls.dart';
import '../core/subject_posters.dart';
import '../core/theme.dart';

/// Episodes that have a playable file outside the download manager.
Future<Set<int>> loadLocalEpisodes(
  AppServices service,
  int subjectId,
  List<Json> episodes,
) async {
  final available = <int>{};
  for (final episode in episodes) {
    final episodeId = episode['episodeId'] as int;
    final saved = await service.store.get(
      'episode_files',
      '$subjectId:$episodeId',
    );
    if (saved != null &&
        saved['downloadId'] == null &&
        await File('${saved['path']}').exists()) {
      available.add(episodeId);
    }
  }
  return available;
}

List<Json> subjectTasks(Json downloads, int? subjectId) => subjectId == null
    ? []
    : objects(downloads['tasks'])
          .where((task) => task['subjectId'] == subjectId)
          .toList();

List<Json> taskVideoFiles(Json downloads, Json task) =>
    objects(downloads['files'])
        .where(
          (file) =>
              file['downloadId'] == task['id'] && file['mediaKind'] == 'video',
        )
        .toList();

/// A task whose single video file can be played (finished or streaming).
Json? playableTask(Json downloads, List<Json> tasks, int episodeId) => tasks
    .where(
      (task) =>
          task['episodeId'] == episodeId &&
          !['checking', 'failed'].contains(task['status']) &&
          taskVideoFiles(downloads, task).length == 1,
    )
    .firstOrNull;

/// Episode list and this subject's cache tasks, beside the video.
class PlayerLibraryPanel extends StatefulWidget {
  const PlayerLibraryPanel({
    super.key,
    required this.service,
    required this.subjectId,
    required this.subject,
    required this.episodeId,
    required this.title,
    required this.downloads,
    required this.localEpisodes,
    required this.onEpisode,
    required this.onFindResources,
    required this.onPlayFile,
  });
  final AppServices service;
  final int? subjectId, episodeId;
  final Json? subject;
  final String title;
  final Json downloads;
  final Set<int> localEpisodes;
  final ValueChanged<Json> onEpisode;
  final ValueChanged<Json?> onFindResources;
  final void Function(String id, String? fileId) onPlayFile;
  @override
  State<PlayerLibraryPanel> createState() => _PlayerLibraryPanelState();
}

class _PlayerLibraryPanelState extends State<PlayerLibraryPanel> {
  final currentKey = GlobalKey();
  String tab = 'episodes';
  String? error;
  List<Json> get episodes => objects(widget.subject?['episodes']);
  List<Json> get tasks => subjectTasks(widget.downloads, widget.subjectId);

  @override
  void initState() {
    super.initState();
    revealCurrent();
  }

  @override
  void didUpdateWidget(PlayerLibraryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.episodeId != widget.episodeId ||
        oldWidget.subject != widget.subject) {
      revealCurrent();
    }
  }

  void revealCurrent() => WidgetsBinding.instance.addPostFrameCallback((_) {
    final target = currentKey.currentContext;
    if (target != null && target.mounted) {
      unawaited(Scrollable.ensureVisible(target, alignment: .3));
    }
  });

  Future<void> toggleTask(Json task) async {
    try {
      if (['paused', 'failed', 'completed'].contains(task['status'])) {
        await widget.service.downloads.resume('${task['id']}');
      } else {
        await widget.service.downloads.pause('${task['id']}');
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  List<Json> filesFor(Json task) => taskVideoFiles(widget.downloads, task);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    final current = episodes
        .where((e) => e['episodeId'] == widget.episodeId)
        .firstOrNull;
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
                            : titleOf(widget.subject!),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontSize: 14),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        current == null
                            ? '正在播放'
                            : '正在播放第 ${current['sort']} 话 · 共 ${episodes.length} 话',
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
              child: Text('此视频没有关联番剧。关联番剧播放时，可在这里选集、查找资源和查看缓存。', style: small),
            )
          else ...[
            if (tasks.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.sm),
                child: MelonSegmentedControl<String>(
                  options: {
                    'episodes': '选集 · ${episodes.length}',
                    'tasks': '本作缓存 · ${tasks.length}',
                  },
                  value: showTasks ? 'tasks' : 'episodes',
                  onChanged: (value) => setState(() => tab = value),
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
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Gap.sm, 0, Gap.sm, Gap.lg),
                children: showTasks
                    ? [
                        for (final task in tasks)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: Gap.sm,
                            ),
                            child: taskTile(task),
                          ),
                      ]
                    : [
                        if (episodes.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(Gap.sm),
                            child: Text('暂未获取到章节信息，可点“找资源”搜索本作。', style: small),
                          ),
                        for (final episode in episodes) episodeRow(episode),
                      ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget episodeRow(Json episode) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    final id = episode['episodeId'] as int;
    final current = id == widget.episodeId;
    final related = tasks.where((t) => t['episodeId'] == id).toList();
    final complete = playableTask(widget.downloads, related, id);
    final task = complete ?? related.firstOrNull;
    final available =
        current || widget.localEpisodes.contains(id) || complete != null;
    final status = current
        ? '正在播放'
        : available
        ? (task != null && number(task['progress']) < 1 ? '可边下边看' : '已缓存')
        : task != null
        ? '${taskStatus(task)} · ${(number(task['progress']) * 100).round()}%'
        : '未缓存 · 点击查找资源';
    final title = titleOf(episode);
    return Padding(
      key: current ? currentKey : null,
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: current
            ? scheme.primary.withValues(alpha: .12)
            : Colors.transparent,
        borderRadius: controlBorderRadius,
        child: InkWell(
          borderRadius: controlBorderRadius,
          onTap: current
              ? null
              : available
              ? () => widget.onEpisode(episode)
              : () => widget.onFindResources(episode),
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
                          '${episode['sort']}',
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
                        title == '未命名' ? '第 ${episode['sort']} 话' : title,
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
                  ),
                ),
                if (!current)
                  IconButton(
                    tooltip: '查找第 ${episode['sort']} 话资源',
                    icon: const Icon(Icons.search_rounded, size: 17),
                    onPressed: () => widget.onFindResources(episode),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget taskTile(Json task) {
    final progress = number(task['progress']).clamp(0.0, 1.0);
    final episode = episodes
        .where((e) => e['episodeId'] == task['episodeId'])
        .firstOrNull;
    final files = filesFor(task);
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
                if (task['coverUrl'] != null) ...[
                  SizedBox(
                    width: 28,
                    height: 38,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: SubjectCover(
                        url: task['coverUrl'],
                        title: '${task['title'] ?? ''}',
                        id: number(task['subjectId']).toInt(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    episode == null
                        ? '${task['title'] ?? '本作资源'}'
                        : '第 ${episode['sort']} 话',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                Text(
                  '${(progress * 100).round()}%',
                  style: const TextStyle(fontSize: 11),
                ),
                if (task['status'] != 'completed' ||
                    task['seedingStopped'] == true)
                  IconButton(
                    tooltip:
                        [
                          'paused',
                          'failed',
                          'completed',
                        ].contains(task['status'])
                        ? (progress >= 1 && task['provider'] != 'pikpak'
                              ? '继续做种'
                              : '继续下载')
                        : (progress >= 1 && task['provider'] != 'pikpak'
                              ? '暂停做种'
                              : '暂停下载'),
                    onPressed: () => toggleTask(task),
                    icon: Icon(
                      ['paused', 'failed', 'completed'].contains(task['status'])
                          ? Icons.play_arrow
                          : Icons.pause,
                      size: 18,
                    ),
                  ),
                if (!['checking', 'failed'].contains(task['status']) &&
                    files.length == 1)
                  IconButton(
                    tooltip: progress >= 1 ? '播放已缓存视频' : '边下边看',
                    onPressed: () => widget.onPlayFile(
                      '${task['id']}',
                      '${files.first['id']}',
                    ),
                    icon: const Icon(Icons.play_arrow, size: 18),
                  ),
              ],
            ),
            LinearProgressIndicator(
              value: progress,
              minHeight: 3,
              borderRadius: BorderRadius.circular(3),
            ),
            const SizedBox(height: 7),
            Text(
              '${taskStatus(task)}${task['status'] == 'seeding'
                  ? ' · ↑ ${(number(task['uploadSpeedBytesPerSecond']) / 1048576).toStringAsFixed(1)} MiB/s'
                  : task['status'] == 'downloading'
                  ? ' · ${(number(task['downloadSpeedBytesPerSecond']) / 1048576).toStringAsFixed(1)} MB/s'
                  : ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (task['errorMessage'] != null)
              Text(
                '${task['errorMessage']}',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            if (!['checking', 'failed'].contains(task['status']) &&
                files.length > 1)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(
                  '选择文件播放 · ${files.length} 个',
                  style: const TextStyle(fontSize: 12),
                ),
                children: [
                  for (final file in files)
                    ListTile(
                      dense: true,
                      title: Text(
                        '${file['name']}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: const Icon(Icons.play_arrow, size: 16),
                      onTap: () =>
                          widget.onPlayFile('${task['id']}', '${file['id']}'),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

String taskStatus(Json task) => task['provider'] == 'pikpak'
    ? 'PikPak · ${switch (task['status']) {
        'metadata' => '云端准备中',
        'downloading' => '下载到本机',
        _ => downloadStatus(task),
      }}'
    : downloadStatus(task);

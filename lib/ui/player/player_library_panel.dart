import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../data/bittorrent_settings.dart';
import '../core/subject_posters.dart';

/// Episode and cache actions stay available alongside the resource sheet.
class PlayerLibraryPanel extends StatefulWidget {
  const PlayerLibraryPanel({
    super.key,
    required this.service,
    required this.subjectId,
    required this.subject,
    required this.episodeId,
    required this.title,
    required this.downloads,
    required this.onEpisode,
    required this.onFindResources,
    required this.onPlayFile,
  });
  final AppServices service;
  final int? subjectId, episodeId;
  final Json? subject;
  final String title;
  final Json downloads;
  final ValueChanged<Json> onEpisode;
  final ValueChanged<Json?> onFindResources;
  final void Function(String id, String? fileId) onPlayFile;
  @override
  State<PlayerLibraryPanel> createState() => _PlayerLibraryPanelState();
}

class _PlayerLibraryPanelState extends State<PlayerLibraryPanel> {
  final localEpisodes = <int>{};
  String? error;
  List<Json> get episodes => objects(widget.subject?['episodes']);
  List<Json> get tasks => widget.subjectId == null
      ? []
      : objects(widget.downloads['tasks'])
            .where((task) => task['subjectId'] == widget.subjectId)
            .toList();

  @override
  void initState() {
    super.initState();
    unawaited(loadLocalEpisodes());
  }

  @override
  void didUpdateWidget(PlayerLibraryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.subject != widget.subject) {
      unawaited(loadLocalEpisodes());
    }
  }

  Future<void> loadLocalEpisodes() async {
    final id = widget.subjectId;
    if (id == null) return;
    final available = <int>{};
    for (final episode in episodes) {
      final episodeId = episode['episodeId'] as int;
      final saved = await widget.service.store.get(
        'episode_files',
        '$id:$episodeId',
      );
      if (saved != null &&
          saved['downloadId'] == null &&
          await File('${saved['path']}').exists()) {
        available.add(episodeId);
      }
    }
    if (mounted) {
      setState(() {
        localEpisodes.clear();
        localEpisodes.addAll(available);
      });
    }
  }

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

  List<Json> filesFor(Json task) => objects(widget.downloads['files'])
      .where(
        (file) =>
            file['downloadId'] == task['id'] && file['mediaKind'] == 'video',
      )
      .toList();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = episodes
        .where((e) => e['episodeId'] == widget.episodeId)
        .firstOrNull;
    return Material(
      color: scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 56, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.subject == null
                      ? widget.title
                      : titleOf(widget.subject!),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  current == null ? '正在播放' : '正在播放 · 第 ${current['sort']} 话',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (widget.subjectId == null)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('此视频没有关联章节。关联番剧播放时，可在这里选集、查找资源和查看缓存。'),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OutlinedButton.icon(
                onPressed: () => widget.onFindResources(current),
                icon: const Icon(Icons.search, size: 18),
                label: const Text('找资源'),
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  error!,
                  style: TextStyle(color: scheme.error, fontSize: 12),
                ),
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: episodeRows(),
              ),
            ),
            if (tasks.isNotEmpty)
              Flexible(
                flex: 0,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text('本作缓存', style: TextStyle(fontSize: 12)),
                          ),
                          Text(
                            '${tasks.length} 个任务',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                      for (final task in tasks) taskTile(task),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  List<Widget> episodeRows() => [
    if (episodes.isEmpty) const Text('暂未获取到章节信息，可在“找资源”中搜索本作。'),
    for (final episode in episodes) episodeRow(episode),
  ];

  Widget episodeRow(Json episode) {
    final id = episode['episodeId'];
    final current = id == widget.episodeId;
    final related = tasks.where((t) => t['episodeId'] == id).toList();
    final complete = related
        .where(
          (t) =>
              !['checking', 'failed'].contains(t['status']) &&
              filesFor(t).length == 1,
        )
        .firstOrNull;
    final task = complete ?? related.firstOrNull;
    final available = current || localEpisodes.contains(id) || complete != null;
    final status = current
        ? '正在播放'
        : available
        ? (task != null && number(task['progress']) < 1 ? '可边下边看' : '已缓存')
        : task != null
        ? '${taskStatus(task)} · ${(number(task['progress']) * 100).round()}%'
        : '未缓存';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        selected: current,
        title: Text(
          '第 ${episode['sort']} 话',
          style: const TextStyle(fontSize: 13),
        ),
        subtitle: Text(
          '${titleOf(episode)}\n$status',
          maxLines: 3,
          style: const TextStyle(fontSize: 11),
        ),
        onTap: available && !current ? () => widget.onEpisode(episode) : null,
        trailing: current
            ? const Icon(Icons.volume_up_outlined, size: 17)
            : IconButton(
                tooltip: '查找第 ${episode['sort']} 话资源',
                icon: const Icon(Icons.search, size: 18),
                onPressed: () => widget.onFindResources(episode),
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
                        ? (progress >= 1 ? '继续做种' : '继续下载')
                        : (progress >= 1 ? '暂停做种' : '暂停下载'),
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

String taskStatus(Json task) => downloadStatus(task);

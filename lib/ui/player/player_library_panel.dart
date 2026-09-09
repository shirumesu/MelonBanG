import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../app_services.dart';

/// Searches keep their own episode context without navigating away from playback.
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
    required this.onPlayFile,
  });
  final AppServices service;
  final int? subjectId, episodeId;
  final Json? subject;
  final String title;
  final Json downloads;
  final ValueChanged<Json> onEpisode;
  final void Function(String id, String? fileId) onPlayFile;
  @override
  State<PlayerLibraryPanel> createState() => _PlayerLibraryPanelState();
}

class _PlayerLibraryPanelState extends State<PlayerLibraryPanel> {
  final query = TextEditingController();
  final added = <String>{}, adding = <String>{};
  final localEpisodes = <int>{};
  int tab = 0, request = 0;
  int? selectedEpisode;
  bool searching = false;
  String? error;
  List<Json> candidates = [], providers = [];
  List<Json> get episodes => objects(widget.subject?['episodes']);
  List<Json> get tasks => widget.subjectId == null
      ? []
      : objects(widget.downloads['tasks'])
            .where((task) => task['subjectId'] == widget.subjectId)
            .toList();

  @override
  void initState() {
    super.initState();
    selectedEpisode = widget.episodeId;
    fillQuery();
    unawaited(loadLocalEpisodes());
  }

  @override
  void didUpdateWidget(PlayerLibraryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.subject != widget.subject) {
      if (query.text.isEmpty) fillQuery();
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

  void fillQuery() {
    final item = widget.subject;
    if (item == null) return;
    final episode = episodes
        .where((e) => e['episodeId'] == selectedEpisode)
        .firstOrNull;
    final name = '${item['name'] ?? titleOf(item)}';
    query.text = episode == null
        ? name
        : '$name ${number(episode['sort']).toInt().toString().padLeft(2, '0')}';
  }

  Future<void> search() async {
    final id = widget.subjectId;
    final keyword = query.text.trim();
    if (id == null || keyword.isEmpty) return;
    final ticket = ++request;
    final episode = selectedEpisode;
    setState(() {
      searching = true;
      error = null;
      candidates = [];
      providers = [];
    });
    try {
      final result = await widget.service.sources.search(
        id,
        keyword,
        episodeId: episode,
      );
      if (mounted && ticket == request) {
        setState(() {
          candidates = objects(result['candidates']);
          providers = objects(result['providers']);
        });
      }
    } catch (e) {
      if (mounted && ticket == request) setState(() => error = '$e');
    } finally {
      if (mounted && ticket == request) setState(() => searching = false);
    }
  }

  void findEpisode(Json episode) {
    setState(() {
      tab = 1;
      selectedEpisode = episode['episodeId'] as int;
    });
    fillQuery();
    unawaited(search());
  }

  Future<void> enqueue(Json candidate) async {
    final id = '${candidate['candidateId']}';
    if (adding.contains(id) || added.contains(id)) return;
    setState(() {
      adding.add(id);
      error = null;
    });
    try {
      await widget.service.sources.enqueue(id);
      if (mounted) setState(() => added.add(id));
    } catch (e) {
      if (mounted) setState(() => error = '下载未能加入：$e');
    } finally {
      if (mounted) setState(() => adding.remove(id));
    }
  }

  Future<void> toggleTask(Json task) async {
    try {
      if (['paused', 'failed'].contains(task['status'])) {
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
  void dispose() {
    request++;
    query.dispose();
    super.dispose();
  }

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
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 0, label: Text('选集')),
                  ButtonSegment(value: 1, label: Text('找资源')),
                ],
                selected: {tab},
                onSelectionChanged: (value) =>
                    setState(() => tab = value.first),
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
                children: tab == 0 ? episodeRows() : resourceRows(),
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
        .where((t) => number(t['progress']) >= 1 && filesFor(t).length == 1)
        .firstOrNull;
    final task = complete ?? related.firstOrNull;
    final available = current || localEpisodes.contains(id) || complete != null;
    final status = current
        ? '正在播放'
        : available
        ? '已缓存'
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
                onPressed: () => findEpisode(episode),
              ),
      ),
    );
  }

  List<Widget> resourceRows() => [
    DropdownButtonFormField<int>(
      key: ValueKey(selectedEpisode),
      initialValue: episodes.any((e) => e['episodeId'] == selectedEpisode)
          ? selectedEpisode
          : null,
      isExpanded: true,
      decoration: const InputDecoration(labelText: '下载关联章节'),
      items: [
        const DropdownMenuItem<int>(value: null, child: Text('本作 · 不指定章节')),
        for (final episode in episodes)
          DropdownMenuItem(
            value: episode['episodeId'] as int,
            child: Text(
              '第 ${episode['sort']} 话',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (value) {
        request++;
        setState(() {
          selectedEpisode = value;
          searching = false;
          candidates = [];
          providers = [];
          error = null;
        });
        fillQuery();
      },
    ),
    const SizedBox(height: 12),
    TextField(
      controller: query,
      onSubmitted: (_) => search(),
      decoration: InputDecoration(
        labelText: '资源关键词',
        suffixIcon: IconButton(
          tooltip: '搜索资源',
          onPressed: search,
          icon: const Icon(Icons.search),
        ),
      ),
    ),
    const SizedBox(height: 12),
    if (searching) const LinearProgressIndicator(),
    for (final provider in providers)
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          '${provider['providerName']} · ${provider['status'] == 'error' ? '搜索失败，可重试' : '${provider['resultCount']} 条'}',
          style: TextStyle(
            fontSize: 11,
            color: provider['status'] == 'error'
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    if (!searching && candidates.isEmpty)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          providers.isEmpty ? '输入作品名或集数查找资源' : '没有找到资源，试试原名或其他关键词',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    for (final candidate in candidates)
      Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              '${candidate['title']}',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            Text(
              '${candidate['providerName']}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed:
                    adding.contains(candidate['candidateId']) ||
                        added.contains(candidate['candidateId'])
                    ? null
                    : () => enqueue(candidate),
                icon: adding.contains(candidate['candidateId'])
                    ? const SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        added.contains(candidate['candidateId'])
                            ? Icons.check
                            : Icons.download,
                        size: 16,
                      ),
                label: Text(
                  added.contains(candidate['candidateId']) ? '已加入缓存' : '下载',
                ),
              ),
            ),
          ],
        ),
      ),
  ];

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
                if (progress < 1 || task['status'] == 'failed')
                  IconButton(
                    tooltip: ['paused', 'failed'].contains(task['status'])
                        ? '继续下载'
                        : '暂停下载',
                    onPressed: () => toggleTask(task),
                    icon: Icon(
                      ['paused', 'failed'].contains(task['status'])
                          ? Icons.play_arrow
                          : Icons.pause,
                      size: 18,
                    ),
                  ),
                if (progress >= 1 && files.length == 1)
                  IconButton(
                    tooltip: '播放已缓存视频',
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
              '${taskStatus(task)}${task['status'] == 'downloading' ? ' · ${(number(task['downloadSpeedBytesPerSecond']) / 1048576).toStringAsFixed(1)} MB/s' : ''}',
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
            if (progress >= 1 && files.length > 1)
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

String taskStatus(Json task) => switch (task['status']) {
  'metadata' => '解析资源',
  'downloading' || 'ready' => '下载中',
  'paused' => '已暂停',
  'completed' => '已缓存',
  'failed' => '下载失败',
  _ => '等待下载',
};

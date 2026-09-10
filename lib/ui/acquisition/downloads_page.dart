import 'package:flutter/material.dart';

import '../../data/json.dart';
import '../../data/bittorrent_settings.dart';
import '../core/page_widgets.dart';
import '../core/subject_posters.dart';
import '../core/theme.dart';

class DownloadsPage extends StatefulWidget {
  const DownloadsPage({
    super.key,
    required this.downloads,
    required this.onAddMagnet,
    required this.onAddTorrent,
    required this.onOpenVideo,
    required this.onExplore,
    required this.onTogglePause,
    required this.onRemove,
    required this.onStopSeeding,
    required this.onPlay,
  });
  final Json downloads;
  final VoidCallback onAddMagnet, onAddTorrent, onOpenVideo, onExplore;
  final ValueChanged<Json> onTogglePause, onRemove, onStopSeeding;
  final void Function(String, String?) onPlay;
  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  String filter = '全部';
  @override
  Widget build(BuildContext context) {
    final tasks = objects(widget.downloads['tasks'])
        .where((t) => t['status'] != 'removed')
        .toList();
    final visible = tasks
        .where(
          (t) => switch (filter) {
            '下载中' =>
              [
                    'metadata',
                    'downloading',
                    'ready',
                    'checking',
                    'queued',
                  ].contains(t['status']) &&
                  number(t['progress']) < 1,
            '已暂停' => ['paused', 'failed'].contains(t['status']),
            '已完成' => number(t['progress']) >= 1,
            '做种中' => t['status'] == 'seeding',
            _ => true,
          },
        )
        .toList();
    final speed = tasks.fold<double>(
      0,
      (sum, t) => sum + number(t['downloadSpeedBytesPerSecond']),
    );
    return PageScroll(
      children: [
        const SizedBox(height: 10),
        MelonPanel(
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: mint.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.folder_copy_outlined, color: mint),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '本地缓存',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${tasks.length} 个任务 · ${tasks.where((t) => number(t['progress']) >= 1).length} 个已完成',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Text(
                '↓ ${(speed / 1048576).toStringAsFixed(1)} MB/s',
                style: const TextStyle(
                  color: mint,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        SectionTitle(
          title: '下载与本地缓存',
          trailing: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: widget.onAddMagnet,
                icon: const Icon(Icons.add_link, size: 17),
                label: const Text('磁力链接'),
              ),
              TextButton.icon(
                onPressed: widget.onAddTorrent,
                icon: const Icon(Icons.file_open_outlined, size: 17),
                label: const Text('种子文件'),
              ),
              PopupMenuButton<String>(
                tooltip: '更多缓存操作',
                icon: const Icon(Icons.more_horiz, size: 20),
                onSelected: (_) => widget.onOpenVideo(),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    enabled: false,
                    height: 28,
                    child: Text('测试工具'),
                  ),
                  PopupMenuItem(value: 'local', child: Text('打开本地视频…')),
                ],
              ),
            ],
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final label in ['全部', '下载中', '做种中', '已暂停', '已完成'])
              ChoiceChip(
                label: Text(label),
                selected: filter == label,
                onSelected: (_) => setState(() => filter = label),
              ),
          ],
        ),
        const SizedBox(height: 16),
        for (final task in visible)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _task(context, task),
          ),
        if (visible.isEmpty)
          EmptyState(
            text: tasks.isEmpty ? '缓存好喜欢的故事，随时开始观看' : '当前分类没有任务',
            action: tasks.isEmpty ? widget.onExplore : null,
            actionLabel: '去探索',
          ),
      ],
    );
  }

  Widget _task(BuildContext context, Json task) {
    final progress = number(task['progress']).clamp(0.0, 1.0).toDouble();
    final canStop =
        progress >= 1 && ['seeding', 'queued'].contains(task['status']);
    final canResume =
        ['paused', 'failed'].contains(task['status']) ||
        (task['status'] == 'completed' && task['seedingStopped'] == true);
    final stoppedByPolicy = task['status'] == 'completed' && !canResume;
    final files = objects(widget.downloads['files'])
        .where((f) => f['downloadId'] == task['id'])
        .toList();
    return MelonPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 64,
                height: 84,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SubjectCover(
                    url: task['coverUrl'],
                    title: '${task['title'] ?? ''}',
                    id: number(task['subjectId']).toInt(),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${task['title']}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (files.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text(
                          files.length == 1
                              ? '${files.single['name']}'
                              : '${files.length} 个文件 · ${files.first['name']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(fontSize: 11),
                        ),
                      ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 6,
                            borderRadius: BorderRadius.circular(99),
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .surfaceContainerLow,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${(progress * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      children: [
                        Text(
                          downloadStatus(task),
                          style: const TextStyle(
                            color: mint,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '↓ ${(number(task['downloadSpeedBytesPerSecond']) / 1048576).toStringAsFixed(1)} · ↑ ${(number(task['uploadSpeedBytesPerSecond']) / 1048576).toStringAsFixed(1)} MiB/s · ${number(task['peerCount']).toInt()} 个连接 · 分享率 ${number(task['totalBytes']) > 0 ? (number(task['uploadedBytes']) / number(task['totalBytes'])).toStringAsFixed(2) : '0.00'}',
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                        if (number(task['progress']) >= 1)
                          Text(
                            '已上传 ${(number(task['uploadedBytes']) / 1048576).toStringAsFixed(1)} MiB · 累计做种 ${(number(task['seedSeconds']) / 60).floor()} 分钟',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(fontSize: 11),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (files.isNotEmpty)
                IconButton(
                  tooltip: '查看文件',
                  onPressed: () => _showFiles(context, task, files),
                  icon: const Icon(Icons.folder_open_outlined, size: 20),
                ),
              IconButton(
                tooltip: canStop
                    ? '停止做种'
                    : stoppedByPolicy
                    ? '已按做种设置停止'
                    : canResume && progress >= 1
                    ? '继续做种'
                    : '暂停 / 继续下载',
                onPressed: stoppedByPolicy
                    ? null
                    : canStop
                    ? () => widget.onStopSeeding(task)
                    : () => widget.onTogglePause(task),
                icon: Icon(
                  canStop
                      ? Icons.stop_circle_outlined
                      : canResume
                      ? Icons.play_arrow
                      : Icons.pause,
                  size: 20,
                ),
              ),
              IconButton(
                tooltip: '播放',
                onPressed: progress >= 1
                    ? () => widget.onPlay('${task['id']}', null)
                    : null,
                icon: const Icon(Icons.play_circle_outline, size: 22),
              ),
              IconButton(
                tooltip: '移除任务与缓存',
                onPressed: () => widget.onRemove(task),
                icon: const Icon(Icons.delete_outline, size: 20),
              ),
            ],
          ),
          if (task['errorMessage'] != null || task['persistenceError'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '${task['errorMessage'] ?? task['persistenceError']}',
                style: const TextStyle(color: coral, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showFiles(
    BuildContext context,
    Json task,
    List<Json> files,
  ) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('任务文件'),
      content: SizedBox(
        width: 560,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: files.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final file = files[index];
            final playable =
                file['mediaKind'] == 'video' && number(file['progress']) >= 1;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                file['mediaKind'] == 'video'
                    ? Icons.video_file_outlined
                    : Icons.insert_drive_file_outlined,
                size: 20,
              ),
              title: Text(
                '${file['name']}',
                style: const TextStyle(fontSize: 12),
              ),
              subtitle: Text(
                '${(number(file['size']) / 1048576).toStringAsFixed(1)} MiB · ${(number(file['progress']) * 100).toStringAsFixed(0)}%',
              ),
              trailing: file['mediaKind'] != 'video'
                  ? null
                  : IconButton(
                      tooltip: '播放此文件',
                      onPressed: playable
                          ? () {
                              Navigator.pop(context);
                              widget.onPlay('${task['id']}', '${file['id']}');
                            }
                          : null,
                      icon: const Icon(Icons.play_arrow, size: 20),
                    ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

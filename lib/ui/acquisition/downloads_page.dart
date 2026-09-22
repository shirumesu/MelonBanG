import 'package:flutter/material.dart';

import '../../data/json.dart';
import '../../data/bittorrent_settings.dart';
import '../core/page_widgets.dart';
import '../core/selection_controls.dart';
import '../core/subject_posters.dart';
import '../core/theme.dart';

String _transferRate(dynamic value) {
  final bytes = number(value);
  if (bytes <= 0) return '0 B/s';
  if (bytes < 1024) return '${bytes.toStringAsFixed(0)} B/s';
  if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KiB/s';
  return '${(bytes / 1048576).toStringAsFixed(1)} MiB/s';
}

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
  String statusFilter = '所有状态';
  final expanded = <String>{};
  StateSetter? _refreshFileDialog;

  @override
  void didUpdateWidget(covariant DownloadsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_refreshFileDialog != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refreshFileDialog?.call(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasks = objects(widget.downloads['tasks'])
        .where((t) => t['status'] != 'removed')
        .toList();
    final visible = tasks.where((t) {
      final complete = number(t['progress']) >= 1;
      final category =
          filter == '全部' || (filter == '已缓存' ? complete : !complete);
      final status = switch (statusFilter) {
        '已暂停' => t['status'] == 'paused',
        '失败' => t['status'] == 'failed',
        '做种中' => t['status'] == 'seeding',
        _ => true,
      };
      return category && status;
    }).toList();
    final speed = tasks.fold<double>(
      0,
      (sum, t) => sum + number(t['downloadSpeedBytesPerSecond']),
    );
    final active = visible.where((t) => number(t['progress']) < 1).toList();
    final cached = visible.where((t) => number(t['progress']) >= 1).toList();
    return PageScroll(
      children: [
        SectionTitle(
          title: '缓存',
          subtitle:
              '${tasks.length} 个任务 · ${tasks.where((t) => number(t['progress']) >= 1).length} 个已缓存',
          trailing: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
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
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 290,
              child: MelonSegmentedControl<String>(
                options: const {'全部': '全部', '进行中': '进行中', '已缓存': '已缓存'},
                value: filter,
                onChanged: (value) => setState(() => filter = value),
              ),
            ),
            MelonChoiceMenu<String>(
              options: const {
                '所有状态': '所有状态',
                '已暂停': '已暂停',
                '失败': '失败',
                '做种中': '做种中',
              },
              value: statusFilter,
              onSelected: (value) => setState(() => statusFilter = value),
            ),
            if (speed > 0)
              Text(
                '↓ ${(speed / 1048576).toStringAsFixed(1)} MiB/s',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 12,
                ),
              ),
          ],
        ),
        for (final group in [('进行中', active), ('已缓存', cached)]) ...[
          if (group.$2.isNotEmpty) ...[
            SectionTitle(title: group.$1, subtitle: '${group.$2.length} 个任务'),
            for (final task in group.$2)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _task(context, task),
              ),
          ],
        ],
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
    final id = '${task['id']}';
    final progress = number(task['progress']).clamp(0.0, 1.0).toDouble();
    final complete = progress >= 1;
    final canStop = complete && ['seeding', 'queued'].contains(task['status']);
    final canResume =
        ['paused', 'failed'].contains(task['status']) ||
        (task['status'] == 'completed' && task['seedingStopped'] == true);
    final stoppedByPolicy = task['status'] == 'completed' && !canResume;
    final files = objects(widget.downloads['files'])
        .where((f) => f['downloadId'] == task['id'])
        .toList();
    final videos = files.where((f) => f['mediaKind'] == 'video').toList();
    final playable =
        complete &&
        task['status'] != 'checking' &&
        videos.any((file) => number(file['progress']) >= 1);
    final scheme = Theme.of(context).colorScheme;
    final details = expanded.contains(id);
    return MelonPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 58,
                height: 78,
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
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 10,
                      runSpacing: 5,
                      children: [
                        MelonBadge(
                          downloadStatus(task),
                          color: task['status'] == 'failed'
                              ? coral
                              : complete
                              ? sky
                              : mint,
                        ),
                        if (files.isNotEmpty)
                          Text(
                            '${files.length} 个文件',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        if (!complete)
                          Text(
                            '${(progress * 100).toStringAsFixed(0)}% · ↓ ${_transferRate(task['downloadSpeedBytesPerSecond'])}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                    if (!complete)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 4,
                          borderRadius: BorderRadius.circular(99),
                          backgroundColor: scheme.surfaceContainerLow,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (complete)
                FilledButton.icon(
                  onPressed: playable
                      ? () => videos.length > 1
                            ? _showFiles(context, id)
                            : widget.onPlay(id, null)
                      : null,
                  icon: const Icon(Icons.play_arrow_rounded, size: 19),
                  label: Text(videos.length > 1 ? '选择文件' : '播放'),
                )
              else
                IconButton(
                  tooltip: '暂停 / 继续下载',
                  onPressed: () => widget.onTogglePause(task),
                  icon: Icon(
                    canResume ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  ),
                ),
              IconButton(
                tooltip: details ? '收起任务详情' : '任务详情',
                onPressed: () => setState(
                  () => details ? expanded.remove(id) : expanded.add(id),
                ),
                icon: Icon(
                  details
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                ),
              ),
            ],
          ),
          if (task['errorMessage'] != null || task['persistenceError'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '${task['errorMessage'] ?? task['persistenceError']}',
                style: TextStyle(color: scheme.error, fontSize: 12),
              ),
            ),
          if (details) ...[
            const Divider(height: 28),
            if (files.isNotEmpty)
              Text(
                files.length == 1
                    ? '${files.single['name']}'
                    : '${files.length} 个文件 · ${files.first['name']}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: 8),
            Text(
              '↓ ${_transferRate(task['downloadSpeedBytesPerSecond'])} · ↑ ${_transferRate(task['uploadSpeedBytesPerSecond'])} · ${number(task['peerCount']).toInt()} 个连接 · 分享率 ${number(task['totalBytes']) > 0 ? (number(task['uploadedBytes']) / number(task['totalBytes'])).toStringAsFixed(2) : '0.00'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (!complete && task.containsKey('trackerCount')) ...[
              const SizedBox(height: 6),
              Text(
                '发现 ${number(task['knownPeerCount']).toInt()} 个节点 · Tracker ${number(task['workingTrackers']).toInt()}/${number(task['trackerCount']).toInt()} 可用'
                '${number(task['failedTrackers']) > 0 ? '（${number(task['failedTrackers']).toInt()} 个连接异常）' : ''}'
                ' · ${number(task['dhtNodes']) < 0 ? 'DHT 已关闭' : 'DHT ${number(task['dhtNodes']).toInt()} 个节点'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if ([
                    'metadata',
                    'downloading',
                    'ready',
                  ].contains(task['status']) &&
                  number(task['peerCount']) == 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    number(task['knownPeerCount']) > 0
                        ? '已发现节点，正在尝试连接。'
                        : number(task['failedTrackers']) > 0 &&
                              number(task['workingTrackers']) == 0 &&
                              number(task['dhtNodes']) <= 0
                        ? '暂未发现下载节点。可检查网络是否允许 BT / UDP，或尝试其他资源。'
                        : '正在寻找下载节点；等待时间也取决于资源的做种情况。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
            if (complete)
              Text(
                '已上传 ${(number(task['uploadedBytes']) / 1048576).toStringAsFixed(1)} MiB · 累计做种 ${(number(task['seedSeconds']) / 60).floor()} 分钟',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (files.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => _showFiles(context, id),
                    icon: const Icon(Icons.folder_open_outlined, size: 17),
                    label: const Text('查看文件'),
                  ),
                if (complete && task['status'] != 'checking')
                  TextButton.icon(
                    onPressed: stoppedByPolicy
                        ? null
                        : canStop
                        ? () => widget.onStopSeeding(task)
                        : () => widget.onTogglePause(task),
                    icon: Icon(
                      canStop
                          ? Icons.stop_circle_outlined
                          : Icons.play_arrow_rounded,
                      size: 17,
                    ),
                    label: Text(
                      canStop
                          ? '停止做种'
                          : stoppedByPolicy
                          ? '已按做种设置停止'
                          : '继续做种',
                    ),
                  ),
                TextButton.icon(
                  onPressed: () => widget.onRemove(task),
                  icon: const Icon(Icons.delete_outline, size: 17),
                  label: const Text('移除任务与缓存'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showFiles(BuildContext context, String id) async {
    try {
      await showDialog<void>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, refresh) {
            _refreshFileDialog = refresh;
            final task = objects(widget.downloads['tasks'])
                .where(
                  (task) =>
                      '${task['id']}' == id && task['status'] != 'removed',
                )
                .firstOrNull;
            final files = objects(widget.downloads['files'])
                .where((file) => '${file['downloadId']}' == id)
                .toList();
            return AlertDialog(
              title: Text(task == null ? '任务已移除' : '任务文件'),
              content: SizedBox(
                width: 560,
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: files.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final file = files[index];
                    final playable =
                        task != null &&
                        file['mediaKind'] == 'video' &&
                        number(file['progress']) >= 1 &&
                        number(task['progress']) >= 1 &&
                        task['status'] != 'checking';
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
                                      widget.onPlay(id, '${file['id']}');
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
            );
          },
        ),
      );
    } finally {
      _refreshFileDialog = null;
    }
  }
}

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../domain/transfer.dart';
import '../../features/downloads/downloads_controller.dart';
import '../core/page_widgets.dart';
import '../core/selection_controls.dart';
import '../core/subject_posters.dart';
import '../core/theme.dart';
import 'download_dialogs.dart';
import 'download_labels.dart';

class DownloadsPage extends StatefulWidget {
  const DownloadsPage({
    super.key,
    required this.downloads,
    required this.onExplore,
    required this.onPlay,
    required this.onError,
  });
  final DownloadsController downloads;
  final VoidCallback onExplore;
  final void Function(String, String?) onPlay;
  final ValueChanged<Object> onError;
  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  String filter = '全部';
  String statusFilter = '所有状态';
  final expanded = <String>{};
  StateSetter? _refreshFileDialog;

  @override
  void initState() {
    super.initState();
    widget.downloads.snapshot.addListener(_refreshFiles);
  }

  @override
  void dispose() {
    widget.downloads.snapshot.removeListener(_refreshFiles);
    super.dispose();
  }

  void _refreshFiles() {
    if (_refreshFileDialog != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refreshFileDialog?.call(() {});
      });
    }
  }

  Future<void> _perform(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      widget.onError(e);
    }
  }

  Future<void> _addMagnet() async {
    final uri = await showDialog<String>(
      context: context,
      builder: (_) => const AddMagnetDialog(),
    );
    if (uri != null && uri.trim().isNotEmpty) {
      await _perform(() => widget.downloads.addMagnet(uri.trim()));
    }
  }

  Future<void> _addTorrent() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Torrent', extensions: ['torrent']),
      ],
    );
    if (file != null) {
      await _perform(
        () async =>
            widget.downloads.addTorrent(await file.readAsBytes(), file.name),
      );
    }
  }

  Future<void> _remove(DownloadTask task) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (_) =>
          RemoveDownloadDialog(title: task.title, cloud: task.cloud),
    );
    if (remove == true) await _perform(() => widget.downloads.remove(task.id));
  }

  void _toggle(DownloadTask task) =>
      _perform(() => widget.downloads.toggle(task));

  void _stopSeeding(DownloadTask task) =>
      _perform(() => widget.downloads.stopSeeding(task.id));

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: widget.downloads.snapshot,
    builder: (context, snapshot, _) => _page(context, snapshot),
  );

  Widget _page(BuildContext context, TransferSnapshot snapshot) {
    final tasks = snapshot.tasks;
    final visible = tasks.where((t) {
      final category =
          filter == '全部' || (filter == '已缓存' ? t.complete : !t.complete);
      final status = switch (statusFilter) {
        '已暂停' => t.status == DownloadStatus.paused,
        '失败' => t.status == DownloadStatus.failed,
        '做种中' => t.status == DownloadStatus.seeding,
        _ => true,
      };
      return category && status;
    }).toList();
    final speed = tasks.fold<int>(0, (sum, t) => sum + t.downloadSpeed);
    final active = visible.where((t) => !t.complete).toList();
    final cached = visible.where((t) => t.complete).toList();
    return PageScroll(
      children: [
        SectionTitle(
          title: '缓存',
          subtitle:
              '${tasks.length} 个任务 · ${tasks.where((t) => t.complete).length} 个已缓存',
          trailing: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton.icon(
                onPressed: _addMagnet,
                icon: const Icon(Icons.add_link, size: 17),
                label: const Text('磁力链接'),
              ),
              TextButton.icon(
                onPressed: _addTorrent,
                icon: const Icon(Icons.file_open_outlined, size: 17),
                label: const Text('种子文件'),
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
            PageSliver(
              child: SliverList.builder(
                itemCount: group.$2.length,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _task(context, group.$2[index]),
                ),
              ),
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

  Widget _task(BuildContext context, DownloadTask task) {
    final id = task.id;
    final progress = task.progress.clamp(0.0, 1.0);
    final complete = task.complete;
    final cloud = task.cloud;
    final status = task.status;
    final swarm = task.swarm;
    final canStop =
        complete &&
        (status == DownloadStatus.seeding || status == DownloadStatus.queued);
    final canResume =
        status == DownloadStatus.paused ||
        status == DownloadStatus.failed ||
        (status == DownloadStatus.completed && task.seedingStopped);
    final stoppedByPolicy = status == DownloadStatus.completed && !canResume;
    final files = task.files;
    final videos = task.videos;
    final playable = task.playable && videos.isNotEmpty;
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
                    url: task.coverUrl,
                    title: task.title,
                    id: task.subjectId ?? 0,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
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
                          color: status == DownloadStatus.failed
                              ? coral
                              : complete
                              ? sky
                              : mint,
                        ),
                        if (cloud) const MelonBadge('PikPak', color: sky),
                        if (files.isNotEmpty)
                          Text(
                            '${files.length} 个文件',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        if (!complete)
                          Text(
                            cloud && status == DownloadStatus.metadata
                                ? '等待 PikPak 完成离线下载'
                                : '${(progress * 100).toStringAsFixed(0)}% · ↓ ${transferRate(task.downloadSpeed)}',
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
              if (complete || playable)
                FilledButton.icon(
                  onPressed: playable
                      ? () => videos.length > 1
                            ? _showFiles(context, id)
                            : widget.onPlay(id, null)
                      : null,
                  icon: const Icon(Icons.play_arrow_rounded, size: 19),
                  label: Text(
                    videos.length > 1
                        ? '选择文件'
                        : complete
                        ? '播放'
                        : '边下边看',
                  ),
                ),
              if (!complete)
                IconButton(
                  tooltip: cloud ? '暂停 / 继续本机缓存' : '暂停 / 继续下载',
                  onPressed: () => _toggle(task),
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
          if ((task.errorMessage ?? task.persistenceError) case final issue?)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                issue,
                style: TextStyle(color: scheme.error, fontSize: 12),
              ),
            ),
          if (details) ...[
            const Divider(height: 28),
            if (files.isNotEmpty)
              Text(
                files.length == 1
                    ? files.single.name
                    : '${files.length} 个文件 · ${files.first.name}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: 8),
            Text(
              cloud
                  ? 'PikPak 云端文件 → 本机缓存 · ↓ ${transferRate(task.downloadSpeed)}'
                  : '↓ ${transferRate(task.downloadSpeed)} · ↑ ${transferRate(task.uploadSpeed)} · ${swarm.peers} 个连接 · 分享率 ${task.totalBytes > 0 ? (task.uploadedBytes / task.totalBytes).toStringAsFixed(2) : '0.00'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (!cloud && !complete && swarm.trackers != null) ...[
              const SizedBox(height: 6),
              Text(
                '发现 ${swarm.knownPeers ?? 0} 个节点 · Tracker ${swarm.workingTrackers ?? 0}/${swarm.trackers} 可用'
                '${(swarm.failedTrackers ?? 0) > 0 ? '（${swarm.failedTrackers} 个连接异常）' : ''}'
                ' · ${(swarm.dhtNodes ?? 0) < 0 ? 'DHT 已关闭' : 'DHT ${swarm.dhtNodes ?? 0} 个节点'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if ((status == DownloadStatus.metadata ||
                      status == DownloadStatus.downloading) &&
                  swarm.peers == 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    (swarm.knownPeers ?? 0) > 0
                        ? '已发现节点，正在尝试连接。'
                        : (swarm.failedTrackers ?? 0) > 0 &&
                              (swarm.workingTrackers ?? 0) == 0 &&
                              (swarm.dhtNodes ?? 0) <= 0
                        ? '暂未发现下载节点。可检查网络是否允许 BT / UDP，或尝试其他资源。'
                        : '正在寻找下载节点；等待时间也取决于资源的做种情况。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
            if (!cloud && complete)
              Text(
                '已上传 ${(task.uploadedBytes / 1048576).toStringAsFixed(1)} MiB · 累计做种 ${(task.seedSeconds / 60).floor()} 分钟',
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
                if (!cloud && complete && status != DownloadStatus.checking)
                  TextButton.icon(
                    onPressed: stoppedByPolicy
                        ? null
                        : canStop
                        ? () => _stopSeeding(task)
                        : () => _toggle(task),
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
                  onPressed: () => _remove(task),
                  icon: const Icon(Icons.delete_outline, size: 17),
                  label: Text(cloud ? '移除本机任务与缓存' : '移除任务与缓存'),
                ),
              ],
            ),
            if (cloud)
              Text(
                '暂停和移除仅影响本机缓存，PikPak 云端文件会保留。',
                style: Theme.of(context).textTheme.bodySmall,
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
            final task = widget.downloads.snapshot.value.task(id);
            final files = task?.files ?? const <DownloadFile>[];
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
                        task != null && file.video && task.playable;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        file.video
                            ? Icons.video_file_outlined
                            : Icons.insert_drive_file_outlined,
                        size: 20,
                      ),
                      title: Text(
                        file.name,
                        style: const TextStyle(fontSize: 12),
                      ),
                      subtitle: Text(
                        '${(file.size / 1048576).toStringAsFixed(1)} MiB · ${(file.progress * 100).toStringAsFixed(0)}%',
                      ),
                      trailing: !file.video
                          ? null
                          : IconButton(
                              tooltip: '播放此文件',
                              onPressed: playable
                                  ? () {
                                      Navigator.pop(context);
                                      widget.onPlay(id, file.id);
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

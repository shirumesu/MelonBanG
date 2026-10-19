import 'dart:io';

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
import 'download_task_widgets.dart';

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
  String statusFilter = '全部状态';
  final expanded = <String>{};

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
      builder: (_) => RemoveDownloadDialog(title: task.title),
    );
    if (remove == true) await _perform(() => widget.downloads.remove(task.id));
  }

  void _toggle(DownloadTask task) =>
      _perform(() => widget.downloads.toggle(task));

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
                '全部状态': '全部状态',
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
            if (filter == '全部')
              SectionTitle(title: '${group.$1} ${group.$2.length}')
            else
              const SizedBox(height: Gap.lg),
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
            text: tasks.isEmpty ? '还没有缓存' : '没有符合条件的任务',
            action: tasks.isEmpty ? widget.onExplore : null,
            actionLabel: '去探索',
          ),
      ],
    );
  }

  Widget _task(BuildContext context, DownloadTask task) {
    final id = task.id;
    final swarm = task.swarm;
    final files = task.files;
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
                    DownloadTaskStatus(task: task),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              DownloadPlayButton(task: task, onPlay: widget.onPlay),
              DownloadToggleButton(task: task, onToggle: _toggle),
              IconButton(
                tooltip: details ? '收起详情' : '详情',
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
                    : '${files.first.name} 等 ${files.length} 个文件',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: 8),
            _stats(context, [
              '↓ ${transferRate(task.downloadSpeed)}',
              if (task.seeds) ...[
                '↑ ${transferRate(task.uploadSpeed)}',
                '${swarm.peers} 个连接',
                '分享率 ${task.totalBytes > 0 ? (task.uploadedBytes / task.totalBytes).toStringAsFixed(2) : '0.00'}',
              ],
            ]),
            if (task.seeds && !task.complete && swarm.trackers != null) ...[
              const SizedBox(height: 6),
              _stats(context, [
                '发现 ${swarm.knownPeers ?? 0} 个节点',
                'Tracker ${swarm.workingTrackers ?? 0}/${swarm.trackers} 可用',
                (swarm.dhtNodes ?? 0) < 0
                    ? 'DHT 已关闭'
                    : 'DHT ${swarm.dhtNodes ?? 0} 个节点',
              ]),
              if ((task.status == DownloadStatus.metadata ||
                      task.status == DownloadStatus.downloading) &&
                  swarm.peers == 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    (swarm.knownPeers ?? 0) > 0
                        ? '已发现节点，正在连接'
                        : (swarm.failedTrackers ?? 0) > 0 &&
                              (swarm.workingTrackers ?? 0) == 0 &&
                              (swarm.dhtNodes ?? 0) <= 0
                        ? '没有找到下载节点，请检查网络是否允许 BT，或换一个资源'
                        : '正在寻找下载节点，做种的人少时会比较慢',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
            if (task.seeds && task.complete) ...[
              const SizedBox(height: 6),
              _stats(context, [
                '已上传 ${(task.uploadedBytes / 1048576).toStringAsFixed(1)} MiB',
                '做种 ${(task.seedSeconds / 60).floor()} 分钟',
              ]),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (files.isNotEmpty)
                  TextButton.icon(
                    onPressed: () =>
                        _perform(() => widget.downloads.reveal(task)),
                    icon: const Icon(Icons.folder_open_outlined, size: 17),
                    label: Text(Platform.isMacOS ? '在访达中显示' : '在资源管理器中显示'),
                  ),
                TextButton.icon(
                  onPressed: () => _remove(task),
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

  Widget _stats(BuildContext context, List<String> values) => Wrap(
    spacing: Gap.lg,
    runSpacing: 4,
    children: [
      for (final value in values)
        Text(value, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

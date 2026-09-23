import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../data/storage_locations.dart';
import '../../data/storage_usage.dart';
import '../core/page_widgets.dart';

class StorageSettings extends StatefulWidget {
  const StorageSettings({
    super.key,
    required this.storage,
    required this.dataDirectory,
    required this.mediaDirectory,
    this.onExit,
    this.readUsage = StorageUsage.measure,
  });
  final StorageLocations? storage;
  final VoidCallback? onExit;
  final String dataDirectory, mediaDirectory;
  final Future<StorageUsage> Function(String, String) readUsage;
  @override
  State<StorageSettings> createState() => _StorageSettingsState();
}

class _StorageSettingsState extends State<StorageSettings> {
  bool busy = false;
  String? error;
  StorageUsage? usage;
  bool measuring = false;
  int measurement = 0;

  @override
  void initState() {
    super.initState();
    refreshUsage();
  }

  @override
  void didUpdateWidget(covariant StorageSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dataDirectory != widget.dataDirectory ||
        oldWidget.mediaDirectory != widget.mediaDirectory) {
      refreshUsage();
    }
  }

  Future<void> refreshUsage() async {
    final request = ++measurement;
    setState(() => measuring = true);
    StorageUsage result;
    try {
      result = await widget.readUsage(
        widget.dataDirectory,
        widget.mediaDirectory,
      );
    } catch (_) {
      result = const StorageUsage();
    }
    if (!mounted || request != measurement) return;
    setState(() {
      usage = result;
      measuring = false;
    });
  }

  String usageLabel(bool media) {
    if (measuring) return '正在统计…';
    final bytes = media ? usage?.mediaBytes : usage?.dataBytes;
    if (bytes == null) return '暂时无法统计';
    if (bytes < 1024) return '已用 $bytes B';
    var value = bytes.toDouble();
    for (final unit in ['KiB', 'MiB', 'GiB', 'TiB']) {
      value /= 1024;
      if (value < 1024 || unit == 'TiB') {
        return '已用 ${value.toStringAsFixed(1)} $unit';
      }
    }
    throw StateError('Unreachable storage size');
  }

  Future<void> choose(bool media) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final selected = await getDirectoryPath(confirmButtonText: '选择文件夹');
      if (selected == null || !mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(media ? '迁移媒体缓存？' : '迁移应用数据？'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('新位置'),
                const SizedBox(height: 8),
                SelectableText(selected),
                const SizedBox(height: 20),
                const Text('下次启动时会复制并校验现有数据，完成后切换位置。原目录保留，迁移完成前请保持磁盘连接。'),
                const SizedBox(height: 12),
                const Text('重启会中断当前播放和传输，请在方便时退出并重新打开应用。'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认迁移'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await widget.storage!.schedule(
        dataPath: media ? null : selected,
        mediaPath: media ? selected : null,
      );
    } catch (e) {
      error = '$e'.replaceFirst('Bad state: ', '');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final media in [false, true]) ...[
        SectionTitle(
          title: media ? '媒体缓存' : '应用数据',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                usageLabel(media),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: '刷新空间用量',
                onPressed: measuring ? null : refreshUsage,
                icon: const Icon(Icons.refresh, size: 18),
              ),
            ],
          ),
        ),
        MelonPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                media ? widget.mediaDirectory : widget.dataDirectory,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: busy || widget.storage == null
                    ? null
                    : () => choose(media),
                icon: const Icon(Icons.drive_file_move_outline),
                label: const Text('更改位置'),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 18),
      if (widget.storage == null) const Text('当前使用启动参数指定的数据目录，请先移除该参数以启用位置管理。'),
      if (widget.storage?.pending case final plan?) ...[
        const SizedBox(height: 14),
        MelonPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('迁移已安排 · 重启后生效'),
              const SizedBox(height: 8),
              if (plan['data'] != widget.dataDirectory)
                SelectableText('应用数据 → ${plan['data']}'),
              if (plan['media'] != widget.mediaDirectory)
                SelectableText('媒体缓存 → ${plan['media']}'),
              const SizedBox(height: 12),
              const Text('请退出并重新打开应用，启动时会显示迁移进度。'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                children: [
                  if (widget.onExit != null)
                    FilledButton(
                      onPressed: busy ? null : widget.onExit,
                      child: const Text('退出应用'),
                    ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () async {
                            setState(() {
                              busy = true;
                              error = null;
                            });
                            try {
                              await widget.storage!.cancel();
                            } catch (_) {
                              error = '暂时无法取消迁移，请重试。';
                            } finally {
                              if (mounted) setState(() => busy = false);
                            }
                          },
                    child: const Text('取消迁移'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
      if (error != null)
        Text(
          error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
    ],
  );
}

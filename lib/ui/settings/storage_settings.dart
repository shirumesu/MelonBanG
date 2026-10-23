import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/storage_locations.dart';
import '../../core/storage_usage.dart';
import '../core/action_feedback.dart';
import '../core/page_widgets.dart';
import 'settings_page.dart';

class StorageSettings extends StatefulWidget {
  const StorageSettings({
    super.key,
    required this.storage,
    required this.dataDirectory,
    required this.mediaDirectory,
    required this.onClearCache,
    required this.readCacheSize,
    this.onExit,
    this.readUsage = StorageUsage.measure,
  });
  final StorageLocations? storage;
  final VoidCallback? onExit;
  final String dataDirectory, mediaDirectory;
  final Future<void> Function() onClearCache;
  final Future<int> Function() readCacheSize;
  final Future<StorageUsage> Function(String, String) readUsage;
  @override
  State<StorageSettings> createState() => _StorageSettingsState();
}

class _StorageSettingsState extends State<StorageSettings> {
  bool busy = false;
  String? error;
  StorageUsage? usage;
  int? cacheBytes;
  bool measuring = false;
  int measurement = 0;
  final cleanup = ActionFeedback();

  @override
  void dispose() {
    cleanup.dispose();
    super.dispose();
  }

  Future<void> clearCache() => cleanup.run(() async {
    await widget.onClearCache();
    if (mounted) await refreshUsage();
    return null;
  });

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
    (StorageUsage, int?) result;
    try {
      result = await (
        widget.readUsage(widget.dataDirectory, widget.mediaDirectory),
        widget.readCacheSize(),
      ).wait;
    } catch (_) {
      result = (const StorageUsage(), null);
    }
    if (!mounted || request != measurement) return;
    setState(() {
      usage = result.$1;
      cacheBytes = result.$2;
      measuring = false;
    });
  }

  String usageLabel(int? bytes) {
    if (measuring) return '正在统计…';
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
  Widget build(BuildContext context) {
    const divider = Divider(height: 1, indent: 20, endIndent: 20);
    final small = Theme.of(context).textTheme.bodySmall;
    Widget location(bool media) => SettingRow(
      title: media ? '媒体缓存' : '应用数据',
      subtitle: usageLabel(media ? usage?.mediaBytes : usage?.dataBytes),
      trailing: OutlinedButton.icon(
        onPressed: busy || widget.storage == null ? null : () => choose(media),
        icon: const Icon(Icons.drive_file_move_outline, size: 18),
        label: const Text('更改位置'),
      ),
    );
    Widget path(String value) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: SelectableText(value, style: small),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingRow(
          title: '图片与资料缓存',
          subtitle:
              '${usageLabel(cacheBytes)}，超过 120 天自动清理，图片最多 100 MiB；'
              '清理不影响已下载的视频、追番和观看进度',
          trailing: FeedbackButton(
            feedback: cleanup,
            label: '清理缓存',
            runningLabel: '正在清理…',
            successLabel: '已清理',
            icon: Icons.cleaning_services_outlined,
            onPressed: clearCache,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: FeedbackIssue(feedback: cleanup, onRetry: clearCache),
        ),
        divider,
        location(false),
        path(widget.dataDirectory),
        divider,
        location(true),
        path(widget.mediaDirectory),
        divider,
        SettingRow(
          title: '刷新空间用量',
          subtitle: widget.storage == null
              ? '当前使用启动参数指定的数据目录，请先移除该参数以启用位置管理'
              : null,
          trailing: IconButton(
            tooltip: '刷新空间用量',
            onPressed: measuring ? null : refreshUsage,
            icon: const Icon(Icons.refresh, size: 18),
          ),
        ),
        if (widget.storage?.pending case final plan?) ...[
          divider,
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '迁移将在重启后进行',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                if (plan['data'] != widget.dataDirectory)
                  SelectableText('应用数据 → ${plan['data']}', style: small),
                if (plan['media'] != widget.mediaDirectory)
                  SelectableText('媒体缓存 → ${plan['media']}', style: small),
                const SizedBox(height: 8),
                Text('请退出并重新打开应用，启动时会显示迁移进度。', style: small),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}

/// The first launch: where downloaded episodes go, before anything is stored.
class StorageSetup extends StatefulWidget {
  const StorageSetup({super.key, required this.storage, required this.onDone});
  final StorageLocations storage;
  final VoidCallback onDone;
  @override
  State<StorageSetup> createState() => _StorageSetupState();
}

class _StorageSetupState extends State<StorageSetup> {
  late String media = widget.storage.media;
  bool busy = false;
  String? error;

  /// A folder that already holds other files gets a MelonBanG subfolder.
  Future<void> pick() async {
    final selected = await getDirectoryPath(confirmButtonText: '选择文件夹');
    if (selected == null) return;
    final folder = Directory(selected);
    final empty = !await folder.exists() || await folder.list().isEmpty;
    if (!mounted) return;
    setState(() {
      media = empty ? selected : p.join(selected, 'MelonBanG');
      error = null;
    });
  }

  Future<void> confirm() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (media != widget.storage.media) await widget.storage.choose(media);
      widget.onDone();
    } catch (e) {
      setState(() {
        busy = false;
        error = '$e'.replaceFirst('Bad state: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('欢迎使用 MelonBanG', style: text.headlineSmall),
              const SizedBox(height: 8),
              const Text('先选好番剧下载到哪里。视频很占空间，建议放在剩余空间较大的磁盘上。'),
              const SizedBox(height: 20),
              MelonPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('下载位置', style: text.titleSmall),
                    const SizedBox(height: 8),
                    SelectableText(media, style: text.bodySmall),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: busy ? null : pick,
                      icon: const Icon(Icons.folder_open_outlined),
                      label: const Text('更改位置'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text('之后可以在 设置 › 存储 › 媒体缓存 里更改', style: text.bodySmall),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: busy ? null : confirm,
                  child: const Text('开始使用'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

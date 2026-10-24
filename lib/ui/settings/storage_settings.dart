import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/error_message.dart';
import '../../core/storage_locations.dart';
import '../../core/storage_usage.dart';
import '../../features/update/uninstall.dart';
import '../core/action_feedback.dart';
import '../core/motion.dart';
import '../core/page_widgets.dart';
import 'settings_page.dart';

/// The data and media folders with their usage, moving them, and the image
/// cache.
SettingsSection storageSection({
  required StorageLocations? storage,
  required String dataDirectory,
  required String mediaDirectory,
  required Future<void> Function() onClearCache,
  required Future<int> Function() readCacheSize,
  required VoidCallback onExit,
}) => SettingsSection(
  id: 'storage',
  title: '存储',
  icon: Icons.folder_outlined,
  groups: [
    SettingsGroup([
      SettingsItem(
        '存储 缓存 清理 应用数据 媒体缓存 下载位置 迁移 空间 文件夹',
        StorageSettings(
          readCacheSize: readCacheSize,
          onClearCache: onClearCache,
          onExit: onExit,
          storage: storage,
          dataDirectory: dataDirectory,
          mediaDirectory: mediaDirectory,
        ),
      ),
    ]),
  ],
);

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
    return '已用 ${size(bytes)}';
  }

  String size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    var value = bytes.toDouble();
    for (final unit in ['KiB', 'MiB', 'GiB', 'TiB']) {
      value /= 1024;
      if (value < 1024 || unit == 'TiB') {
        return '${value.toStringAsFixed(1)} $unit';
      }
    }
    throw StateError('Unreachable storage size');
  }

  /// The folder to move to for the [chosen] one. A folder that already holds
  /// other files gets a MelonBanG subfolder. The install directory is
  /// replaced by updates and removed on uninstall, so media there goes to its
  /// downloads folder, which both leave in place, and data cannot go there.
  Future<String> target(String chosen, bool media) async {
    var target = p.normalize(chosen);
    final folder = Directory(target);
    if (await folder.exists() && !await folder.list().isEmpty) {
      target = p.join(target, 'MelonBanG');
    }
    final installation = AppUninstall.installation;
    if (!p.equals(installation, target) && !p.isWithin(installation, target)) {
      return target;
    }
    if (!media || !Platform.isWindows) {
      throw StateError('不能放在安装目录里，更新或卸载时会被删除，请选择其他位置');
    }
    final downloads = p.join(installation, 'downloads');
    return p.equals(downloads, target) || p.isWithin(downloads, target)
        ? target
        : downloads;
  }

  Future<void> choose(bool media) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final picked = await getDirectoryPath(confirmButtonText: '选择文件夹');
      if (picked == null || !mounted) return;
      final selected = await target(picked, media);
      await widget.storage!.check(
        dataPath: media ? null : selected,
        mediaPath: media ? selected : null,
      );
      final inside = p.isWithin(AppUninstall.installation, selected);
      if (!mounted) return;
      final confirmed = await showMelonDialog<bool>(
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
                if (!p.equals(selected, picked)) ...[
                  const SizedBox(height: 8),
                  Text(
                    inside
                        ? '所选位置在安装目录里，将使用其中的 downloads 文件夹，更新时不会被替换。'
                        : '所选文件夹里已有其他文件，将使用其中的 MelonBanG 文件夹，避免混在一起。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (inside) ...[
                  const SizedBox(height: 12),
                  Text(
                    '卸载时选择删除数据，或手动删除安装目录，已下载的番剧会被一起删除。',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                const Text('现有数据会在后台复制，期间可以照常使用。复制完成后重新打开应用即可切换位置，原目录保留。'),
                const SizedBox(height: 12),
                const Text('迁移完成前请保持原位置和新位置的磁盘连接。'),
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
      error = errorMessage(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// The pending move: its background copy, then the restart that switches.
  Widget move(StorageLocations storage, MoveCopy? copy) {
    final plan = storage.pending;
    if (plan == null) return const SizedBox.shrink();
    final small = Theme.of(context).textTheme.bodySmall;
    final copied = plan['copied'] == true;
    final total = copy?.total ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            copied ? '迁移已准备好' : '正在后台迁移',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          if (plan['data'] != widget.dataDirectory)
            SelectableText('应用数据 → ${plan['data']}', style: small),
          if (plan['media'] != widget.mediaDirectory)
            SelectableText('媒体缓存 → ${plan['media']}', style: small),
          const SizedBox(height: 8),
          if (copy?.error case final message?)
            Text(
              '复制已停止：$message',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            )
          else if (copied)
            Text(
              '文件已复制，重新打开应用后切换到新位置'
              '${(copy?.left ?? 0) > 0 ? '，${copy!.left} 个正在使用的文件届时补上' : ''}。',
              style: small,
            )
          else ...[
            LinearProgressIndicator(
              value: total == 0 ? null : copy!.done / total,
            ),
            const SizedBox(height: 6),
            Text(
              total == 0
                  ? '正在准备…'
                  : '${copy!.done * 100 ~/ total}% · 共 ${size(total)}'
                        '${copy.file.isEmpty ? '' : ' · ${copy.file}'}',
              style: small,
            ),
            const SizedBox(height: 4),
            Text('期间可以照常使用，复制完成后重新打开应用即可切换。', style: small),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            children: [
              if (copied && widget.onExit != null)
                FilledButton(
                  onPressed: busy ? null : widget.onExit,
                  child: const Text('退出应用'),
                ),
              if (copy?.error != null)
                OutlinedButton(
                  onPressed: busy ? null : storage.prepare,
                  child: const Text('重试'),
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
                          await storage.cancel();
                        } catch (e) {
                          error = errorMessage(e);
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
    );
  }

  @override
  Widget build(BuildContext context) {
    const divider = Divider(height: 1, indent: 20, endIndent: 20);
    final small = Theme.of(context).textTheme.bodySmall;
    Widget location(bool media) => SettingRow(
      title: media ? '媒体缓存' : '应用数据',
      subtitle: usageLabel(media ? usage?.mediaBytes : usage?.dataBytes),
      trailing: OutlinedButton.icon(
        onPressed: busy || widget.storage?.pending != null
            ? null
            : () => choose(media),
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
        if (widget.storage case final storage?
            when storage.pending != null) ...[
          divider,
          ValueListenableBuilder<MoveCopy?>(
            valueListenable: storage.copy,
            builder: (context, copy, _) => move(storage, copy),
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
        error = errorMessage(e);
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

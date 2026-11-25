import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/error_message.dart';
import '../../core/notices.dart';
import '../../core/storage_locations.dart';
import '../../core/storage_usage.dart';
import '../../features/update/uninstall.dart';
import '../core/action_feedback.dart';
import '../core/byte_units.dart';
import '../core/motion.dart';
import '../core/page_widgets.dart';
import '../core/theme.dart';
import 'setting_rows.dart';

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
        '存储 缓存 应用缓存 图片 资料 清理 应用数据 媒体缓存 下载位置 迁移 空间 文件夹',
        _StorageSettings(
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

/// The folder to use for the [chosen] one. A drive's root or a folder that
/// already holds files gets a subfolder of its own, as Steam and Windows do
/// for their libraries. Updates replace the install directory and uninstalling
/// removes it, so media there goes to its downloads folder, which neither
/// touches, and data cannot go there.
Future<String> storageTarget(String chosen, {required bool media}) async {
  var target = p.normalize(chosen);
  final root =
      p.dirname(target) == target ||
      (Platform.isMacOS && p.dirname(target) == '/Volumes');
  if (root ||
      await Directory(target).exists() && !await isEmptyFolder(target)) {
    target = p.join(target, media ? 'MelonBanG Media' : 'MelonBanG');
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

const _syncedNote = '此位置在网盘同步文件夹中，下载时会占用网络并可能损坏文件，建议更换';

class _StorageSettings extends StatefulWidget {
  const _StorageSettings({
    required this.storage,
    required this.dataDirectory,
    required this.mediaDirectory,
    required this.onClearCache,
    required this.readCacheSize,
    required this.onExit,
  });
  final StorageLocations? storage;
  final VoidCallback onExit;
  final String dataDirectory, mediaDirectory;
  final Future<void> Function() onClearCache;
  final Future<int> Function() readCacheSize;
  @override
  State<_StorageSettings> createState() => _StorageSettingsState();
}

class _StorageSettingsState extends State<_StorageSettings> {
  bool busy = false;
  String? error;
  StorageUsage? usage;
  int? cacheBytes;
  String? usageIssue, cacheIssue;
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
  void didUpdateWidget(covariant _StorageSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dataDirectory != widget.dataDirectory ||
        oldWidget.mediaDirectory != widget.mediaDirectory) {
      refreshUsage();
    }
  }

  Future<void> refreshUsage() async {
    final request = ++measurement;
    setState(() => measuring = true);
    (StorageUsage?, int?) values;
    (AsyncError?, AsyncError?) errors = (null, null);
    try {
      values = await (
        StorageUsage.measure(widget.dataDirectory, widget.mediaDirectory),
        widget.readCacheSize(),
      ).wait;
    } on ParallelWaitError<
      (StorageUsage?, int?),
      (AsyncError?, AsyncError?)
    > catch (failure) {
      values = failure.values;
      errors = failure.errors;
    }
    if (!mounted || request != measurement) return;
    String? issue(AsyncError? error) =>
        error == null ? null : errorMessage(error.error);
    setState(() {
      usage = values.$1;
      cacheBytes = values.$2;
      usageIssue = issue(errors.$1);
      cacheIssue = issue(errors.$2);
      measuring = false;
    });
  }

  String usageLabel(int? bytes, String? issue) {
    if (measuring) return '正在统计…';
    if (issue != null) return '无法统计：$issue';
    return '已用 ${ByteUnitsScope.of(context).format(bytes!)}';
  }

  Future<void> choose(bool media) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final picked = await getDirectoryPath(confirmButtonText: '选择文件夹');
      if (picked == null || !mounted) return;
      final current = media ? widget.mediaDirectory : widget.dataDirectory;
      final selected = await storageTarget(picked, media: media);
      if (p.equals(picked, current) || p.equals(selected, current)) {
        throw StateError(media ? '媒体缓存已经在这个位置' : '应用数据已经在这个位置');
      }
      await widget.storage!.check(
        dataPath: media ? null : selected,
        mediaPath: media ? selected : null,
      );
      final (space, source) = await (
        DiskSpace.of(selected),
        DiskSpace.of(current),
      ).wait;
      // Within a volume the folder is renamed and takes no extra space.
      final needed = space.volume == source.volume
          ? null
          : media
          ? usage?.mediaBytes
          : usage?.dataBytes;
      final short = needed != null && needed > space.free;
      final inside = p.isWithin(AppUninstall.installation, selected);
      if (!mounted) return;
      final small = Theme.of(context).textTheme.bodySmall;
      final units = ByteUnitsScope.of(context);
      final confirmed = await showConfirmDialog(
        context,
        title: media ? '迁移媒体缓存？' : '迁移应用数据？',
        confirmLabel: '确认迁移',
        enabled: !short,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('新位置'),
            const SizedBox(height: Gap.sm),
            SelectableText(selected),
            if (!p.equals(selected, picked)) ...[
              const SizedBox(height: Gap.sm),
              Text(
                inside
                    ? '所选位置在安装目录里，将使用其中的 downloads 文件夹，更新时不会被替换。'
                    : '将在所选位置下新建 ${p.basename(selected)} 文件夹，不会和那里的其他文件混在一起。',
                style: small,
              ),
            ],
            const SizedBox(height: Gap.sm),
            if (short)
              InlineIssue(
                '所在磁盘可用 ${units.format(space.free)}'
                '，迁移约需 ${units.format(needed)}，空间不足',
              )
            else
              Text(
                '所在磁盘可用 ${units.format(space.free)}'
                '${needed == null ? '' : '，迁移约需 ${units.format(needed)}'}',
                style: small,
              ),
            if (media && space.system) ...[
              const SizedBox(height: Gap.sm),
              const InlineIssue(
                '这是系统盘。番剧很占空间，系统盘空间紧张会拖慢整个系统，建议选择其他磁盘。',
                tone: NoticeTone.warning,
              ),
            ],
            if (cloudSynced(selected)) ...[
              const SizedBox(height: Gap.sm),
              const InlineIssue(_syncedNote, tone: NoticeTone.warning),
            ],
            if (inside) ...[
              const SizedBox(height: Gap.md),
              const InlineIssue(
                '卸载时选择删除数据，或手动删除安装目录，已下载的番剧会被一起删除。',
                tone: NoticeTone.warning,
              ),
            ],
            const SizedBox(height: 20),
            const Text('重新打开应用后生效，原位置的文件会被删除；跨磁盘时会先在后台复制'),
            const SizedBox(height: Gap.md),
            const Text('迁移完成前请保持原位置和新位置的磁盘连接。'),
          ],
        ),
      );
      if (!confirmed || !mounted) return;
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            copied ? '迁移已准备好' : '正在后台迁移',
            style: const TextStyle(
              fontSize: FontSize.body,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: Gap.sm),
          if (plan['data'] != widget.dataDirectory)
            SelectableText('应用数据 → ${plan['data']}', style: small),
          if (plan['media'] != widget.mediaDirectory)
            SelectableText('媒体缓存 → ${plan['media']}', style: small),
          const SizedBox(height: Gap.sm),
          if (copy?.error case final message?)
            InlineIssue('复制已停止：$message')
          else if (copied)
            Text(
              '重新打开应用即可完成迁移，并删除原位置的文件'
              '${(copy?.left ?? 0) > 0 ? '；${copy!.left} 个正在使用的文件届时补上' : ''}',
              style: small,
            )
          else ...[
            LinearProgressIndicator(
              value: total == 0 ? null : copy!.done / total,
            ),
            const SizedBox(height: Gap.sm),
            Text(
              total == 0
                  ? '正在准备…'
                  : '${copy!.done * 100 ~/ total}%，共 ${ByteUnitsScope.of(context).format(total)}',
              style: small,
            ),
            if (total > 0 && copy!.file.isNotEmpty)
              Text(
                copy.file,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: small,
              ),
            const SizedBox(height: Gap.xs),
            Text('期间可以照常使用，复制完成后重新打开应用即可完成迁移', style: small),
          ],
          const SizedBox(height: Gap.md),
          Wrap(
            spacing: Gap.md,
            children: [
              if (copied)
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
      subtitle: [
        usageLabel(media ? usage?.mediaBytes : usage?.dataBytes, usageIssue),
        if (widget.storage == null) '位置由启动参数指定，移除该参数后才能更改',
      ].join('；'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Usage is measured on opening, after cleaning and after moving;
          // this catches files changed outside the app.
          IconButton(
            tooltip: '刷新空间用量',
            visualDensity: VisualDensity.compact,
            onPressed: measuring ? null : refreshUsage,
            icon: const Icon(Icons.refresh, size: 18),
          ),
          const SizedBox(width: Gap.xs),
          OutlinedButton.icon(
            // Without location management (a data folder given at launch)
            // there is nothing to move.
            onPressed:
                busy ||
                    widget.storage == null ||
                    widget.storage!.pending != null
                ? null
                : () => choose(media),
            icon: const Icon(Icons.drive_file_move_outline, size: 18),
            label: const Text('更改位置'),
          ),
        ],
      ),
    );
    Widget path(String value) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, Gap.md),
      child: SelectableText(value, style: small),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingRow(
          title: '应用缓存',
          subtitle: usageLabel(cacheBytes, cacheIssue),
          help:
              '图片与番剧资料，超过 120 天自动清理，图片最多 100 MiB\n'
              '清理不影响已下载的视频、追番、订阅和观看进度',
          trailing: FeedbackButton(
            feedback: cleanup,
            label: '清理缓存',
            runningLabel: '清理中',
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
            padding: const EdgeInsets.fromLTRB(20, 0, 20, Gap.md),
            child: InlineIssue(error!),
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
  DiskSpace? space;
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    measure();
  }

  Future<void> measure() async {
    final measured = media;
    final DiskSpace result;
    try {
      result = await DiskSpace.of(measured);
    } on FileSystemException {
      // Free space is a hint; the folder can be chosen without it.
      return;
    }
    if (mounted && measured == media) setState(() => space = result);
  }

  Future<void> pick() async {
    try {
      final picked = await getDirectoryPath(confirmButtonText: '选择文件夹');
      if (picked == null) return;
      final selected = await storageTarget(picked, media: true);
      if (!mounted) return;
      setState(() {
        media = selected;
        space = null;
        error = null;
      });
      await measure();
    } catch (e) {
      if (mounted) setState(() => error = errorMessage(e));
    }
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
      if (!mounted) return;
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
          padding: const EdgeInsets.all(Gap.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('欢迎使用 MelonBanG', style: text.headlineSmall),
              const SizedBox(height: Gap.sm),
              const Text('先选好番剧下载到哪里。视频很占空间，建议放在剩余空间较大的磁盘上。'),
              const SizedBox(height: 20),
              MelonPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('下载位置', style: text.titleSmall),
                    const SizedBox(height: Gap.sm),
                    SelectableText(media, style: text.bodySmall),
                    if (space case final space?)
                      Text(
                        '所在磁盘可用 ${ByteUnitsScope.of(context).format(space.free)}'
                        '${space.system ? '（系统盘）' : ''}',
                        style: text.bodySmall,
                      ),
                    if (cloudSynced(media)) ...[
                      const SizedBox(height: Gap.xs),
                      const InlineIssue(_syncedNote, tone: NoticeTone.warning),
                    ],
                    const SizedBox(height: Gap.md),
                    OutlinedButton.icon(
                      onPressed: busy ? null : pick,
                      icon: const Icon(Icons.folder_open_outlined),
                      label: const Text('更改位置'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Gap.sm),
              Text('之后可以在 设置 › 存储 › 媒体缓存 里更改', style: text.bodySmall),
              if (error != null) ...[
                const SizedBox(height: Gap.md),
                InlineIssue(error!),
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

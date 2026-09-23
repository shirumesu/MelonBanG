import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../data/storage_locations.dart';
import '../core/page_widgets.dart';

class StorageSettings extends StatefulWidget {
  const StorageSettings({
    super.key,
    required this.storage,
    required this.dataDirectory,
    required this.mediaDirectory,
  });
  final StorageLocations? storage;
  final String dataDirectory, mediaDirectory;
  @override
  State<StorageSettings> createState() => _StorageSettingsState();
}

class _StorageSettingsState extends State<StorageSettings> {
  bool busy = false;
  String? error;
  Future<void> choose(bool media) async {
    final selected = await getDirectoryPath(confirmButtonText: '选择空文件夹');
    if (selected == null || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
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
        SectionTitle(title: media ? '媒体缓存' : '应用数据'),
        MelonPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(media ? '视频、下载中的文件和种子元数据' : '追番记录、播放进度与下载任务记录'),
              const SizedBox(height: 12),
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
                label: const Text('更改位置并迁移'),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 18),
      const Text(
        '迁移在下次启动时执行，复制并校验完成后才切换位置。原目录保留为备份，确认新位置正常后可手动删除。界面偏好与系统钥匙串仍由操作系统保存。',
      ),
      if (widget.storage == null) const Text('当前使用启动参数指定的数据目录，请先移除该参数以启用位置管理。'),
      if (widget.storage?.pending case final plan?) ...[
        const SizedBox(height: 14),
        Text('迁移已安排，请退出并重新打开应用。\n应用数据：${plan['data']}\n媒体缓存：${plan['media']}'),
        TextButton(
          onPressed: busy
              ? null
              : () async {
                  await widget.storage!.cancel();
                  if (mounted) setState(() {});
                },
          child: const Text('取消迁移'),
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

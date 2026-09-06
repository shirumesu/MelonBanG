import 'package:flutter/material.dart';

import '../../data/json.dart';
import '../core/page_widgets.dart';

class DownloadsPage extends StatelessWidget {
  const DownloadsPage({
    super.key,
    required this.downloads,
    required this.onAddMagnet,
    required this.onAddTorrent,
    required this.onExplore,
    required this.onTogglePause,
    required this.onRemove,
    required this.onPlay,
  });
  final Json downloads;
  final VoidCallback onAddMagnet;
  final VoidCallback onAddTorrent;
  final VoidCallback onExplore;
  final ValueChanged<Json> onTogglePause;
  final ValueChanged<Json> onRemove;
  final void Function(String, String?) onPlay;
  @override
  Widget build(BuildContext context) => PageScroll(
    children: [
      SectionTitle(
        title: '下载与本地缓存',
        trailing: Row(
          children: [
            TextButton.icon(
              onPressed: onAddMagnet,
              icon: const Icon(Icons.add_link),
              label: const Text('磁力链接'),
            ),
            TextButton.icon(
              onPressed: onAddTorrent,
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('种子文件'),
            ),
          ],
        ),
      ),
      for (final task in objects(
        downloads['tasks'],
      ).where((task) => task['status'] != 'removed'))
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${task['title']}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: number(task['progress']).clamp(0, 1),
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${task['status']} · ${(number(task['progress']) * 100).toStringAsFixed(1)}% · ${(number(task['downloadSpeedBytesPerSecond']) / 1048576).toStringAsFixed(1)} MB/s · ${task['peerCount']} peers',
                      ),
                    ),
                    IconButton(
                      tooltip: '暂停 / 继续',
                      onPressed: () => onTogglePause(task),
                      icon: Icon(
                        ['paused', 'failed'].contains(task['status'])
                            ? Icons.play_arrow
                            : Icons.pause,
                      ),
                    ),
                    IconButton(
                      tooltip: '播放',
                      onPressed: number(task['progress']) >= 1
                          ? () => onPlay('${task['id']}', null)
                          : null,
                      icon: const Icon(Icons.play_circle_outline),
                    ),
                    IconButton(
                      tooltip: '移除任务与缓存',
                      onPressed: () => onRemove(task),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
                if (task['errorMessage'] != null)
                  Text(
                    '${task['errorMessage']}',
                    style: const TextStyle(color: Colors.orange),
                  ),
                for (final file in objects(downloads['files']).where(
                  (file) =>
                      file['downloadId'] == task['id'] &&
                      file['mediaKind'] == 'video',
                ))
                  ListTile(
                    dense: true,
                    title: Text('${file['name']}'),
                    trailing: IconButton(
                      tooltip: '播放此文件',
                      icon: const Icon(Icons.play_arrow),
                      onPressed: number(file['progress']) >= 1
                          ? () => onPlay('${task['id']}', '${file['id']}')
                          : null,
                    ),
                  ),
              ],
            ),
          ),
        ),
      if (objects(downloads['tasks'])
          .where((task) => task['status'] != 'removed')
          .isEmpty)
        EmptyState(
          text: '缓存好喜欢的故事，随时开始观看',
          action: onExplore,
          actionLabel: '去探索',
        ),
    ],
  );
}

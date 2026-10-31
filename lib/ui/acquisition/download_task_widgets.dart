import 'package:flutter/material.dart';

import '../../domain/transfer.dart';
import '../core/motion.dart';
import '../core/byte_units.dart';
import '../core/page_widgets.dart';
import '../core/theme.dart';
import 'download_labels.dart';

// Shared by the cache page and the player's cache list, so a task reads and
// acts the same in both.

/// Status and origin badges, progress and speed of a task, with a progress
/// bar while it downloads.
class DownloadTaskStatus extends StatelessWidget {
  const DownloadTaskStatus({super.key, required this.task});
  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    final progress = task.progress.clamp(0.0, 1.0);
    final measured = !task.complete && task.cloudProgress == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (DownloadStatusBadge.shows(task)) DownloadStatusBadge(task),
            if (downloadOrigin(task) case final origin?)
              MelonBadge(
                origin,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            if (measured) ...[
              Text('${(progress * 100).floor()}%', style: small),
              Text(
                '↓ ${ByteUnitsScope.of(context).rate(task.downloadSpeed)}',
                style: small,
              ),
            ],
            if (task.status == DownloadStatus.seeding)
              Text(
                '↑ ${ByteUnitsScope.of(context).rate(task.uploadSpeed)}',
                style: small,
              ),
          ],
        ),
        if (!task.complete)
          Padding(
            padding: const EdgeInsets.only(top: Gap.sm),
            child: MotionValue(
              value: task.cloudProgress ?? progress,
              builder: (context, value) => LinearProgressIndicator(
                value: value,
                minHeight: 4,
                borderRadius: BorderRadius.circular(99),
                backgroundColor: Theme.of(context)
                    .colorScheme
                    .surfaceContainerLow,
              ),
            ),
          ),
      ],
    );
  }
}

/// Watches the task's video, or lets the user choose one of several; while
/// none can play it stays visible, disabled, and says why. An icon button,
/// for rows of a list.
class DownloadPlayButton extends StatelessWidget {
  const DownloadPlayButton({
    super.key,
    required this.task,
    required this.onPlay,
  });
  final DownloadTask task;
  final void Function(String id, String? fileId) onPlay;

  @override
  Widget build(BuildContext context) {
    final videos = task.videos;
    final blocked = playBlocked(task);
    final choose = videos.length > 1;
    final label = choose ? '选择视频' : '观看';
    return IconButton(
      tooltip: blocked ?? (task.complete ? label : '$label，同时继续下载'),
      onPressed: blocked != null
          ? null
          : choose
          ? () => chooseDownloadVideo(context, task, onPlay)
          : () => onPlay(task.id, videos.single.id),
      icon: Icon(
        choose ? Icons.playlist_play_rounded : Icons.play_arrow_rounded,
        size: 20,
      ),
    );
  }
}

/// Pauses or resumes the download, or stops or resumes seeding; hidden when
/// the task has nothing to toggle. An icon button in rows of a list, or
/// beside a task's watch button a labelled one in the same shape.
class DownloadToggleButton extends StatelessWidget {
  const DownloadToggleButton({
    super.key,
    required this.task,
    required this.onToggle,
    this.size,
    this.labelled = false,
  });
  final DownloadTask task;
  final ValueChanged<DownloadTask> onToggle;
  final double? size;
  final bool labelled;

  @override
  Widget build(BuildContext context) {
    final toggle = task.toggle;
    if (toggle == null) return const SizedBox.shrink();
    final icon = switch (toggle) {
      TaskToggle.pause => Icons.pause_rounded,
      TaskToggle.resume =>
        task.status == DownloadStatus.failed
            ? Icons.refresh_rounded
            : Icons.download_rounded,
      TaskToggle.stopSeeding => Icons.stop_circle_outlined,
      TaskToggle.resumeSeeding => Icons.upload_rounded,
    };
    if (labelled) {
      return OutlinedButton.icon(
        onPressed: () => onToggle(task),
        icon: MotionSwap(value: icon, child: Icon(icon, size: 18)),
        label: Text(toggleLabel(toggle)),
      );
    }
    return IconButton(
      tooltip: toggleLabel(toggle),
      onPressed: () => onToggle(task),
      icon: MotionSwap(
        value: icon,
        child: Icon(icon, size: size),
      ),
    );
  }
}

/// The task's videos with their size and progress, each playable.
Future<void> chooseDownloadVideo(
  BuildContext context,
  DownloadTask task,
  void Function(String id, String? fileId) onPlay,
) => showMelonDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('选择视频'),
    content: SizedBox(
      width: 560,
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: task.videos.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final file = task.videos[index];
          final size = ByteUnitsScope.of(context).format(file.size);
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.video_file_outlined, size: 20),
            title: Text(file.name, style: const TextStyle(fontSize: 12)),
            subtitle: Text(
              file.progress >= 1
                  ? size
                  : '$size  ${(file.progress * 100).floor()}%',
            ),
            trailing: const Icon(Icons.play_arrow_rounded, size: 20),
            onTap: () {
              Navigator.pop(context);
              onPlay(task.id, file.id);
            },
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

/// A task's status, red when it failed and blue once complete; nothing for
/// a finished task that does not seed, which needs no badge.
class DownloadStatusBadge extends StatelessWidget {
  const DownloadStatusBadge(this.task, {super.key});
  final DownloadTask task;

  /// Whether [task] has a status worth a badge.
  static bool shows(DownloadTask task) =>
      task.status != DownloadStatus.completed || task.seeds;

  @override
  Widget build(BuildContext context) {
    if (!shows(task)) return const SizedBox.shrink();
    return MelonBadge(
      downloadStatus(task),
      color: task.status == DownloadStatus.failed
          ? coral
          : task.complete
          ? sky
          : mint,
    );
  }
}

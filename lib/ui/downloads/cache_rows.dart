import 'package:flutter/material.dart';

import '../../core/notices.dart';
import '../../domain/transfer.dart';
import '../core/action_feedback.dart';
import '../core/byte_units.dart';
import '../core/motion.dart';
import '../core/page_widgets.dart';
import '../core/theme.dart';
import 'download_labels.dart';
import 'download_task_widgets.dart';

/// Where the rows of a show sit inside its panel.
final _rowRadius = insetRadius(panelBorderRadius, Gap.sm);

/// The ground of a cache row: tinted while picked, a click picks it and a
/// secondary click opens its menu; without [onTap] it cannot be picked.
class _RowGround extends StatelessWidget {
  const _RowGround({
    required this.selected,
    required this.onTap,
    required this.onMenu,
    required this.child,
  });
  final bool selected;
  final VoidCallback? onTap;
  final ValueChanged<Offset> onMenu;
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: selected
        ? Theme.of(context).colorScheme.primary.withValues(alpha: .12)
        : Colors.transparent,
    borderRadius: _rowRadius,
    child: InkWell(
      borderRadius: _rowRadius,
      onTap: onTap,
      onSecondaryTapUp: (details) => onMenu(details.globalPosition),
      child: child,
    ),
  );
}

/// Room for one icon button, kept while it has none.
class _ButtonSlot extends StatelessWidget {
  const _ButtonSlot(this.child);
  final Widget? child;

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: 40, child: Center(child: child));
}

/// One task of a show: its episode, release, where it comes from, its state
/// and size, with its controls. Until it finishes a progress line runs
/// beneath it; what stops it shows under that. A batch has no play button,
/// its videos follow it as rows of their own.
class CacheTaskRow extends StatelessWidget {
  const CacheTaskRow({
    super.key,
    required this.task,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.onMenu,
    required this.onToggle,
    required this.onPlay,
    required this.onRemove,
  });
  final DownloadTask task;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<Offset> onMenu;
  final ValueChanged<DownloadTask> onToggle;
  final void Function(String id, String? fileId) onPlay;
  final VoidCallback onRemove;

  /// The file's name where it differs from the release title shown.
  String get _fileName {
    final name = (task.videos.singleOrNull ?? task.files.firstOrNull)?.name;
    return name == null || name == task.title ? '' : name;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    final units = ByteUnitsScope.of(context);
    final progress = task.progress.clamp(0.0, 1.0);
    final measure = [
      if (!task.complete && task.cloudProgress == null) ...[
        '${(progress * 100).floor()}%',
        if (task.downloadSpeed > 0) '↓ ${units.rate(task.downloadSpeed)}',
      ] else if (task.complete && task.totalBytes > 0)
        units.format(task.totalBytes),
    ].join('  ');
    final issues = [
      if ((task.errorMessage ?? task.persistenceError) case final issue?)
        InlineIssue(issue),
      if (stalledHint(task) case final hint?)
        InlineIssue(hint, tone: NoticeTone.warning),
    ];
    return _RowGround(
      selected: selected,
      onTap: onTap,
      onMenu: onMenu,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.sm, 2, 0, 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 64,
                  child: Text(
                    label,
                    style: const TextStyle(fontSize: FontSize.body),
                  ),
                ),
                Expanded(
                  child: Tooltip(
                    message: _fileName,
                    child: Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: small,
                    ),
                  ),
                ),
                const SizedBox(width: Gap.md),
                if (downloadOrigin(task) case final origin?) ...[
                  MelonBadge(origin, color: scheme.onSurfaceVariant),
                  const SizedBox(width: Gap.sm),
                ],
                if (DownloadStatusBadge.shows(task)) ...[
                  DownloadStatusBadge(task, details: true),
                  const SizedBox(width: Gap.sm),
                ],
                if (measure.isNotEmpty)
                  Text(measure, textAlign: TextAlign.end, style: small),
                const SizedBox(width: Gap.xs),
                // Slots of their own, so the buttons line up down the list.
                _ButtonSlot(
                  DownloadToggleButton(
                    task: task,
                    onToggle: onToggle,
                    size: 20,
                  ),
                ),
                _ButtonSlot(
                  task.videos.length > 1
                      ? null
                      : DownloadPlayButton(task: task, onPlay: onPlay),
                ),
                IconButton(
                  tooltip: task.videos.length > 1 ? '删除整个合集' : '删除',
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline, size: 20),
                ),
              ],
            ),
            if (!task.complete)
              Padding(
                padding: const EdgeInsets.fromLTRB(64, 0, Gap.sm, Gap.xs),
                child: MotionValue(
                  value: task.cloudProgress ?? progress,
                  builder: (context, value) => LinearProgressIndicator(
                    value: value,
                    minHeight: 2,
                    borderRadius: pillBorderRadius,
                    backgroundColor: scheme.surfaceContainerLow,
                  ),
                ),
              ),
            for (final issue in issues)
              Padding(
                padding: const EdgeInsets.fromLTRB(64, 0, Gap.sm, Gap.xs),
                child: issue,
              ),
          ],
        ),
      ),
    );
  }
}

/// One video of a batch, under the batch's row: its episode, file name,
/// size and progress, to watch and, once the batch is finished, to pick or
/// delete on its own.
class CacheVideoRow extends StatelessWidget {
  const CacheVideoRow({
    super.key,
    required this.task,
    required this.file,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.onMenu,
    required this.onPlay,
    required this.onRemove,
  });
  final DownloadTask task;
  final DownloadFile file;
  final String label;
  final bool selected;

  /// Null while the batch downloads: its videos go with it.
  final VoidCallback? onTap;
  final ValueChanged<Offset> onMenu;
  final void Function(String id, String? fileId) onPlay;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    final blocked = playBlocked(task);
    return _RowGround(
      selected: selected,
      onTap: onTap,
      onMenu: onMenu,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.sm + Gap.lg, 0, 0, 0),
        child: Row(
          children: [
            SizedBox(
              width: 64 - Gap.lg,
              child: Text(label, style: small),
            ),
            Expanded(
              child: Text(
                file.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: small,
              ),
            ),
            const SizedBox(width: Gap.md),
            Text(
              [
                ByteUnitsScope.of(context).format(file.size),
                if (file.progress < 1) '${(file.progress * 100).floor()}%',
              ].join('  '),
              style: small,
            ),
            const SizedBox(width: Gap.xs),
            IconButton(
              tooltip: blocked ?? '观看',
              onPressed: blocked != null
                  ? null
                  : () => onPlay(task.id, file.id),
              icon: const Icon(Icons.play_arrow_rounded, size: 20),
            ),
            // Kept in place while hidden, so the play buttons line up.
            Visibility.maintain(
              visible: onRemove != null,
              child: IconButton(
                tooltip: '删除这个视频',
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

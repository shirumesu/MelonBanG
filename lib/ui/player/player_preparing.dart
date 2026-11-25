import 'package:flutter/material.dart';

import '../../core/notices.dart';
import '../../domain/transfer.dart';
import '../../features/appearance/appearance.dart';
import '../../features/playback/playback_coordinator.dart';
import '../core/byte_units.dart';
import '../core/motion.dart';
import '../core/overlay_glass.dart';
import '../core/subject_cover.dart';
import '../core/theme.dart';
import '../core/tone.dart';
import '../downloads/download_labels.dart';
import 'player_theme.dart';

/// The state, speed and peers of a download the player waits on; null once
/// it is complete.
String? _transferLine(DownloadTask? task, ByteUnits units) =>
    task == null || task.complete ? null : transferLine(task, units);

/// Why a BT task waiting for data has no peers yet. Every tracker failing
/// with an empty DHT table means its traffic does not get out, which a proxy
/// routing BT to a node that drops it does.
String? _swarmHint(DownloadTask? task) {
  if (task == null ||
      task.complete ||
      task.method != CacheMethod.bt ||
      task.swarm.peers > 0 ||
      task.downloadSpeed > 0) {
    return null;
  }
  final SwarmStats(:workingTrackers, :failedTrackers, :dhtNodes) = task.swarm;
  if ((failedTrackers ?? 0) > 0 &&
      (workingTrackers ?? 0) == 0 &&
      (dhtNodes ?? 0) == 0) {
    return '连不上 BT 网络，开着代理时请让 MelonBanG 直连';
  }
  return '冷门资源可能要等很久，可以在侧栏换个资源';
}

/// Shown over the video while it opens or buffers; a streamed download adds
/// its live state, and a BT task finding no peers says why it waits.
class BufferingStatus extends StatelessWidget {
  const BufferingStatus({super.key, required this.opening, this.task});
  final bool opening;
  final DownloadTask? task;

  @override
  Widget build(BuildContext context) {
    final task = this.task;
    final line = _transferLine(task, ByteUnitsScope.of(context));
    final hint = _swarmHint(task);
    const shadow = [Shadow(blurRadius: 6)];
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const BusyIndicator(size: 28, color: Colors.white),
          const SizedBox(height: Gap.md),
          Text(
            opening ? '正在打开视频…' : '正在缓冲…',
            style: const TextStyle(
              color: Colors.white,
              fontSize: FontSize.body,
              shadows: shadow,
            ),
          ),
          if (line != null) ...[
            const SizedBox(height: Gap.xs),
            Text(
              line,
              style: const TextStyle(
                color: overlayMuted,
                fontSize: FontSize.small,
                fontFeatures: [FontFeature.tabularFigures()],
                shadows: shadow,
              ),
            ),
          ],
          if (hint != null) ...[
            const SizedBox(height: Gap.xs),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: overlayMuted,
                fontSize: FontSize.small,
                shadows: shadow,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Stands in for the video until a source plays, or says why none could.
class PreparingView extends StatelessWidget {
  const PreparingView({
    super.key,
    required this.preparing,
    required this.onRetry,
    required this.onChoose,
    required this.exitLabel,
    this.task,
    this.onExitFullScreen,
  });
  final PreparingPlayback preparing;

  /// The download being started or streamed.
  final DownloadTask? task;
  final VoidCallback onRetry, onChoose;

  /// Set in the immersive modes, where no title bar leads back.
  final VoidCallback? onExitFullScreen;

  /// What leaving the immersive mode is called.
  final String exitLabel;

  @override
  Widget build(BuildContext context) {
    final failed = preparing.failed;
    final live = _transferLine(task, ByteUnitsScope.of(context));
    final hint = _swarmHint(task);
    final canChoose = preparing.subject != null && preparing.episode != null;
    const white = Colors.white;
    const muted = overlayMuted;
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: MotionAppear(
          offset: 10,
          milliseconds: 320,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 96,
                  height: 128,
                  child: CoverFrame(
                    child: SubjectCover(
                      url: preparing.coverUrl,
                      title: preparing.title,
                      id: preparing.subject?.id ?? 0,
                    ),
                  ),
                ),
                const SizedBox(height: Gap.lg),
                Text(
                  preparing.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: white,
                    fontSize: FontSize.title,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (preparing.detail case final detail?) ...[
                  const SizedBox(height: Gap.xs),
                  Text(
                    detail,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: muted,
                      fontSize: FontSize.small,
                    ),
                  ),
                ],
                const SizedBox(height: Gap.xl),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MotionSwap(
                      value: failed == null,
                      child: failed == null
                          ? const BusyIndicator(color: white)
                          : Icon(
                              toneIcon(NoticeTone.failed),
                              size: 18,
                              color: toneColor(
                                context,
                                NoticeTone.failed,
                                glass: true,
                              ),
                            ),
                    ),
                    const SizedBox(width: Gap.sm),
                    Flexible(
                      child: AnimatedSize(
                        duration: motionDuration(context, 220),
                        curve: Curves.easeOutCubic,
                        child: MotionSwap(
                          value: failed ?? preparing.status,
                          scale: 1,
                          milliseconds: 220,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            failed ?? preparing.status ?? '正在查找资源…',
                            style: const TextStyle(
                              color: muted,
                              fontSize: FontSize.body,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (preparing.source case final source?
                    when failed == null) ...[
                  const SizedBox(height: Gap.xs),
                  // The source's name stands out from the site listing it.
                  Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: '已选择 '),
                        if (source.sourceName.isNotEmpty)
                          TextSpan(
                            text: '${source.sourceName}  ',
                            style: const TextStyle(color: white),
                          ),
                        TextSpan(text: source.site),
                      ],
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: muted,
                      fontSize: FontSize.small,
                    ),
                  ),
                ],
                if (failed == null && live != null) ...[
                  const SizedBox(height: Gap.xs),
                  Text(
                    live,
                    style: const TextStyle(
                      color: muted,
                      fontSize: FontSize.small,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
                if (failed == null && hint != null) ...[
                  const SizedBox(height: Gap.xs),
                  Text(
                    hint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: muted,
                      fontSize: FontSize.small,
                    ),
                  ),
                ],
                const SizedBox(height: Gap.lg),
                _RecoveryActions(
                  onRetry: failed == null ? null : onRetry,
                  onChoose: canChoose ? onChoose : null,
                  chooseLabel: '选择资源',
                  onExit: onExitFullScreen,
                  exitLabel: exitLabel,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Why playback stopped, with retrying the source or choosing another; with
/// neither, as for a chosen file, it leads back. In immersive modes, which
/// have no title bar to lead back, it offers leaving them instead.
class FailureCard extends StatelessWidget {
  const FailureCard({
    super.key,
    required this.reason,
    required this.onBack,
    required this.exitLabel,
    this.onRetry,
    this.onChoose,
    this.onExitFullScreen,
  });
  final String reason;
  final VoidCallback onBack;
  final VoidCallback? onRetry, onChoose, onExitFullScreen;

  /// What leaving the immersive mode is called.
  final String exitLabel;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxWidth: 420),
    margin: const EdgeInsets.all(Gap.xl),
    padding: const EdgeInsets.all(Gap.xl),
    decoration: const BoxDecoration(
      color: overlaySurface,
      borderRadius: panelBorderRadius,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          toneIcon(NoticeTone.failed),
          color: toneColor(context, NoticeTone.failed, glass: true),
          size: 28,
        ),
        const SizedBox(height: Gap.md),
        Text(
          reason,
          textAlign: TextAlign.center,
          maxLines: 6,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: FontSize.body),
        ),
        const SizedBox(height: Gap.lg),
        _RecoveryActions(
          onRetry: onRetry,
          onChoose: onChoose,
          chooseLabel: '选择其他资源',
          onExit: onExitFullScreen,
          exitLabel: exitLabel,
          onBack: onBack,
        ),
      ],
    ),
  );
}

/// Retrying, choosing a source and leaving the immersive mode, each where it
/// is given; [onBack] stands in when none of them is.
class _RecoveryActions extends StatelessWidget {
  const _RecoveryActions({
    required this.chooseLabel,
    required this.exitLabel,
    this.onRetry,
    this.onChoose,
    this.onExit,
    this.onBack,
  });
  final VoidCallback? onRetry, onChoose, onExit, onBack;
  final String chooseLabel, exitLabel;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: Gap.sm,
    runSpacing: Gap.sm,
    alignment: WrapAlignment.center,
    children: [
      if (onRetry != null)
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: overlayInk,
          ),
          onPressed: onRetry,
          child: const Text('重试'),
        ),
      if (onChoose != null)
        OutlinedButton(
          style: overlayOutlinedButtonStyle,
          onPressed: onChoose,
          child: Text(chooseLabel),
        ),
      if (onExit != null)
        TextButton(
          style: TextButton.styleFrom(foregroundColor: overlayMuted),
          onPressed: onExit,
          child: Text(exitLabel),
        )
      else if (onRetry == null && onChoose == null && onBack != null)
        OutlinedButton(
          style: overlayOutlinedButtonStyle,
          onPressed: onBack,
          child: const Text('返回'),
        ),
    ],
  );
}

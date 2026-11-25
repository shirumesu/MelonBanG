import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../core/error_message.dart';
import '../../domain/play_candidate.dart';
import '../../domain/transfer.dart';
import '../../features/appearance/appearance.dart';
import '../../features/playback/playback.dart';
import '../../features/update/app_update.dart';
import '../core/byte_units.dart';
import '../core/motion.dart';
import '../core/overlay_glass.dart';
import '../core/theme.dart';

/// 详细参数 over the video's top left: what plays and how, read from mpv
/// once a second, to see why a video stutters or looks wrong and to paste
/// into a report.
class PlayerStatsPanel extends StatefulWidget {
  const PlayerStatsPanel({
    super.key,
    required this.playback,
    required this.source,
    required this.downloads,
    required this.onClose,
  });
  final Playback playback;

  /// The source the session plays, when one was chosen.
  final PlayCandidate? source;
  final ValueListenable<TransferSnapshot> downloads;
  final VoidCallback onClose;

  @override
  State<PlayerStatsPanel> createState() => _PlayerStatsPanelState();
}

class _PlayerStatsPanelState extends State<PlayerStatsPanel> {
  Timer? timer, copiedTimer;
  PlaybackDetails? details;
  bool copied = false;

  /// Errors reading the properties are shown in place of them.
  String? error;

  @override
  void initState() {
    super.initState();
    unawaited(read());
    timer = Timer.periodic(const Duration(seconds: 1), (_) => read());
  }

  @override
  void dispose() {
    timer?.cancel();
    copiedTimer?.cancel();
    super.dispose();
  }

  Future<void> read() async {
    try {
      final value = await widget.playback.details();
      if (mounted) {
        setState(() {
          details = value;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = errorMessage(e));
    }
  }

  List<(String, String)> rows(ByteUnits units) {
    final playback = widget.playback;
    final session = playback.session;
    final details = this.details;
    final source = widget.source;
    String? join(List<String?> parts) {
      final shown = parts.whereType<String>().where((e) => e.isNotEmpty);
      return shown.isEmpty ? null : shown.join('  ');
    }

    final task = switch (session?.downloadId) {
      final id? => widget.downloads.value.task(id),
      null => null,
    };
    final upscale = playback.upscale;
    final chain = playback.settings.superResolution;
    final danmaku = playback.danmaku;
    final row = <(String, String?)>[
      (
        '来源',
        source != null
            ? '${source.kind.label}  ${source.sourceLabel}'
            : task != null
            ? '缓存  ${task.title}'
            : session?.title,
      ),
      (
        '文件',
        switch (session?.path) {
          final path? => p.basename(path),
          null => null,
        },
      ),
      ('封装', details?.container),
      (
        '视频',
        join([
          details?.videoCodec?.toUpperCase(),
          if (details?.width case final width?) '$width×${details!.height}',
          if (details?.fps case final fps?) '${_trim(fps, 3)} fps',
          _depth(details?.pixelFormat),
        ]),
      ),
      ('色彩', join([details?.primaries, details?.gamma])),
      ('视频码率', _bits(details?.videoBitrate)),
      (
        '解码',
        details == null
            ? null
            : details.hwdec == null || details.hwdec == 'no'
            ? '软件解码'
            : '硬件解码  ${details.hwdec}',
      ),
      (
        '超分',
        chain == 'off'
            ? '关闭'
            : join([
                chain == 'quality' ? '质量' : '效率',
                if (upscale case (:final source, :final output?))
                  '${_size(source)} → ${_size(output)}'
                else if (upscale != null)
                  '只修复线条',
              ]),
      ),
      (
        '音频',
        join([
          details?.audioCodec?.toUpperCase(),
          if (details?.sampleRate case final rate?)
            '${_trim(rate / 1000, 1)} kHz',
          if (details?.channels case final channels?) '$channels 声道',
          _bits(details?.audioBitrate),
        ]),
      ),
      (
        '音画差',
        switch (details?.avsync) {
          final avsync? => '${(avsync * 1000).round()} ms',
          null => null,
        },
      ),
      (
        '丢帧',
        details?.droppedFrames == null
            ? null
            : '画面 ${details!.droppedFrames}  解码 ${details.decoderDroppedFrames ?? 0}',
      ),
      (
        '缓冲',
        join([
          if (details?.cacheSeconds case final seconds?)
            '已缓冲 ${seconds.toStringAsFixed(1)} 秒',
          if (details?.cacheSpeed case final speed? when speed > 0)
            '读取 ${units.rate(speed)}',
        ]),
      ),
      if (task != null && !task.complete)
        (
          '下载',
          join([
            '${(task.progress * 100).toStringAsFixed(1)}%',
            units.rate(task.downloadSpeed),
            if (task.method == CacheMethod.bt) '${task.swarm.peers} 个节点',
          ]),
        ),
      (
        '弹幕',
        danmaku.comments.isEmpty
            ? '没有弹幕'
            : join([
                '显示 ${danmaku.visible.length} / ${danmaku.comments.length} 条',
                for (final source in danmaku.sources)
                  if (source.enabled && source.count > 0)
                    '${source.label} ${source.count}',
              ]),
      ),
      ('内核', join([details?.mpv, ?_ffmpeg(details?.ffmpeg)])),
    ];
    return [
      for (final (label, value) in row)
        if (value != null) (label, value),
    ];
  }

  /// The rows as text for a report, with the app and system first.
  String report(List<(String, String)> rows) => [
    'MelonBanG ${AppUpdate.version.isEmpty ? '开发版本' : AppUpdate.version}  '
        '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    for (final (label, value) in rows) '$label：$value',
  ].join('\n');

  Future<void> copy(List<(String, String)> rows) async {
    await Clipboard.setData(ClipboardData(text: report(rows)));
    if (!mounted) return;
    setState(() => copied = true);
    copiedTimer?.cancel();
    copiedTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final rows = this.rows(ByteUnitsScope.of(context));
    const label = TextStyle(fontSize: FontSize.small, color: overlayMuted);
    const value = TextStyle(
      fontSize: FontSize.small,
      color: Colors.white,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    return OverlayGlass(
      borderRadius: panelBorderRadius,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.xs, Gap.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '详细参数',
                      style: TextStyle(
                        fontSize: FontSize.body,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      overlayColor: Colors.white,
                      textStyle: appFont.copyWith(fontSize: FontSize.small),
                    ).merge(compactTextButtonStyle),
                    onPressed: () => unawaited(copy(rows)),
                    child: MotionSwap(
                      value: copied,
                      child: Text(copied ? '已复制' : '复制'),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: widget.onClose,
                    iconSize: 16,
                    visualDensity: VisualDensity.compact,
                    color: overlayMuted,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: Gap.xs),
              if (error case final error?)
                Text('读取失败：$error', style: label)
              else
                Padding(
                  padding: const EdgeInsets.only(right: Gap.md),
                  child: Table(
                    columnWidths: const {
                      0: IntrinsicColumnWidth(),
                      1: FlexColumnWidth(),
                    },
                    children: [
                      for (final (name, text) in rows)
                        TableRow(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(
                                right: Gap.md,
                                bottom: 3,
                              ),
                              child: Text(name, style: label),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Text(text, style: value),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// [value] with at most [digits] decimals and no trailing zeros.
String _trim(double value, int digits) {
  final text = value.toStringAsFixed(digits);
  return text.contains('.')
      ? text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
      : text;
}

String _size(Size size) => '${size.width.round()}×${size.height.round()}';

/// Bits per second as kbps or Mbps.
String? _bits(int? bits) => switch (bits) {
  null || <= 0 => null,
  >= 1000000 => '${_trim(bits / 1000000, 1)} Mbps',
  _ => '${(bits / 1000).round()} kbps',
};

/// The colour depth a pixel format names: `yuv420p10` and `p010` are 10
/// bit; one that names none is 8 bit.
String? _depth(String? format) {
  if (format == null) return null;
  final bits =
      RegExp(r'^p0(\d{2})').firstMatch(format)?.group(1) ??
      RegExp(r'p(\d{2})(le|be)?$').firstMatch(format)?.group(1);
  return '${bits ?? 8} bit';
}

/// FFmpeg's version without its build suffix.
String? _ffmpeg(String? version) =>
    version == null ? null : 'FFmpeg ${version.split('-').first}';

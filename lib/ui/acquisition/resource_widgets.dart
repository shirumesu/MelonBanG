import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/play_candidate.dart';
import '../../domain/transfer.dart';
import '../../domain/resource_title.dart';
import '../../domain/sources.dart';
import '../core/motion.dart';
import '../core/page_widgets.dart';
import '../core/selection_controls.dart';
import '../core/theme.dart';

enum ResourceDownloadPhase { idle, adding, added, failed }

/// Width of the download column; rows and the table header share it.
double resourceDownloadWidth({required bool labelled, required bool split}) =>
    (labelled ? 80.0 : 36.0) + (split ? 29.0 : 0);

/// Split button: the main part uses the default cache method, the chevron
/// lists every method so the choice is explicit.
class ResourceDownloadButton extends StatelessWidget {
  const ResourceDownloadButton({
    super.key,
    required this.phase,
    required this.onPressed,
    this.error,
    this.showLabel = false,
    this.defaultMethod = CacheMethod.bt,
    this.onAlternative,
    this.alternativePhase = ResourceDownloadPhase.idle,
  });
  final ResourceDownloadPhase phase;
  final VoidCallback onPressed;
  final String? error;
  final bool showLabel;
  final CacheMethod defaultMethod;
  final VoidCallback? onAlternative;
  final ResourceDownloadPhase alternativePhase;

  static const _height = 34.0, _chevronWidth = 28.0, _menuWidth = 280.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final busy =
        phase == ResourceDownloadPhase.adding ||
        alternativePhase == ResourceDownloadPhase.adding;
    final split = onAlternative != null;
    final label = switch (phase) {
      ResourceDownloadPhase.idle =>
        split ? '用 ${defaultMethod.label} 下载（默认）' : '下载',
      ResourceDownloadPhase.adding => '正在加入下载…',
      ResourceDownloadPhase.added => '已加入下载',
      ResourceDownloadPhase.failed =>
        '添加失败，点击重试${error == null ? '' : '\n$error'}',
    };
    final action =
        busy ||
            [
              ResourceDownloadPhase.adding,
              ResourceDownloadPhase.added,
            ].contains(phase)
        ? null
        : onPressed;
    final settled = phase == ResourceDownloadPhase.added;
    final failed = phase == ResourceDownloadPhase.failed;
    final background = settled || failed
        ? scheme.surfaceContainerHigh
        : scheme.primaryContainer;
    final foreground = failed
        ? scheme.tertiary
        : settled
        ? scheme.primary
        : scheme.onPrimaryContainer;
    final icon = SizedBox.square(
      dimension: 18,
      child: AnimatedSwitcher(
        duration: motionDuration(context, 150),
        child: busy
            ? Padding(
                key: const ValueKey(ResourceDownloadPhase.adding),
                padding: const EdgeInsets.all(2),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: foreground,
                ),
              )
            : Icon(
                switch (phase) {
                  ResourceDownloadPhase.added => Icons.check_rounded,
                  ResourceDownloadPhase.failed => Icons.refresh_rounded,
                  _ => Icons.download_rounded,
                },
                key: ValueKey(phase),
                size: 18,
                color: foreground,
              ),
      ),
    );
    final left = split
        ? const BorderRadius.horizontal(left: Radius.circular(12))
        : controlBorderRadius;
    final main = Tooltip(
      message: label,
      child: InkWell(
        borderRadius: left,
        onTap: action,
        child: SizedBox(
          width: showLabel ? 80 : 36,
          height: _height,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon,
              if (showLabel) ...[
                const SizedBox(width: 5),
                Text(
                  switch (phase) {
                    ResourceDownloadPhase.adding => '加入中',
                    ResourceDownloadPhase.added => '已加入',
                    ResourceDownloadPhase.failed => '重试',
                    _ => '下载',
                  },
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: foreground,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return Semantics(
      liveRegion: phase != ResourceDownloadPhase.idle,
      child: AnimatedContainer(
        duration: motionDuration(context, 150),
        decoration: BoxDecoration(
          color: background,
          borderRadius: controlBorderRadius,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              main,
              if (split) ...[
                Container(
                  width: 1,
                  height: 18,
                  color: foreground.withValues(alpha: .2),
                ),
                _methodMenu(context, busy, foreground),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _methodMenu(BuildContext context, bool busy, Color foreground) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    MenuItemButton item(
      CacheMethod method,
      ResourceDownloadPhase state,
      VoidCallback run,
    ) {
      final added = state == ResourceDownloadPhase.added;
      return MenuItemButton(
        style: const ButtonStyle(
          minimumSize: WidgetStatePropertyAll(Size(_menuWidth - 10, 48)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: controlBorderRadius),
          ),
        ),
        onPressed: added || busy ? null : run,
        leadingIcon: Icon(
          method == CacheMethod.bt
              ? Icons.hub_outlined
              : Icons.cloud_download_outlined,
          size: 18,
          color: added ? scheme.onSurfaceVariant : scheme.primary,
        ),
        trailingIcon: added
            ? Text('已加入', style: small?.copyWith(color: scheme.primary))
            : method == defaultMethod
            ? Text('默认', style: small)
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${method.label} 下载'),
            Text(
              method == CacheMethod.bt
                  ? '本机直接下载，完成后可做种'
                  : '先在 PikPak 云端离线，再下载到本机',
              style: small?.copyWith(fontSize: 11),
            ),
          ],
        ),
      );
    }

    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(menuSurface(context)),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(5)),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: controlBorderRadius),
        ),
        elevation: const WidgetStatePropertyAll(3),
        minimumSize: const WidgetStatePropertyAll(Size(_menuWidth, 0)),
        maximumSize: const WidgetStatePropertyAll(
          Size(_menuWidth, double.infinity),
        ),
      ),
      // Right-align the menu with the button so it stays inside the table.
      alignmentOffset: const Offset(_chevronWidth - _menuWidth + 8, 4),
      menuChildren: [
        item(defaultMethod, phase, onPressed),
        item(defaultMethod.other, alternativePhase, onAlternative!),
      ],
      builder: (context, controller, _) => Tooltip(
        message: '选择下载方式',
        child: InkWell(
          borderRadius: const BorderRadius.horizontal(
            right: Radius.circular(12),
          ),
          onTap: busy
              ? null
              : () =>
                    controller.isOpen ? controller.close() : controller.open(),
          child: SizedBox(
            width: _chevronWidth,
            height: _height,
            child: Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: foreground,
            ),
          ),
        ),
      ),
    );
  }
}

/// Per-site status line: "动漫花园 12 条 · 蜜柑计划 搜索中 2/5".
String resourceProviderStatus(SourceProgress source) => switch (source.status) {
  SearchStatus.loading => '搜索中 ${source.completed}/${source.total}',
  SearchStatus.error => '搜索失败',
  SearchStatus.partial => '${source.resultCount} 条 · 部分名称失败',
  SearchStatus.ready => '${source.resultCount} 条',
};

class ResourceSearchStatus extends StatelessWidget {
  const ResourceSearchStatus({super.key, required this.providers});
  final List<SourceProgress> providers;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const LinearProgressIndicator(minHeight: 2),
      const SizedBox(height: Gap.sm),
      Text(
        [
          providers.every((e) => e.resultCount == 0)
              ? '正在查找资源，结果会陆续显示'
              : providers.any((e) => e.status == SearchStatus.loading)
              ? '已找到的资源可以使用，其余结果陆续加入'
              : '正在补充字幕组信息，资源已可使用',
          for (final provider in providers)
            '${provider.sourceName} ${resourceProviderStatus(provider)}',
        ].join(' · '),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
}

class ResourceArrival extends StatelessWidget {
  const ResourceArrival({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 240),
    child: child,
    builder: (_, value, child) => Opacity(
      opacity: value,
      child: Transform.translate(
        offset: Offset(0, 6 * (1 - value)),
        child: child,
      ),
    ),
  );
}

String resourceSizeLabel(TorrentRelease release) {
  final provided = (release.sizeLabel ?? '').trim();
  if (provided.isNotEmpty) return provided;
  return resourceBytesLabel(release.sizeBytes ?? 0);
}

String resourceBytesLabel(int bytes) {
  if (bytes <= 1) return '大小未知';
  if (bytes >= 1073741824) {
    return '${(bytes / 1073741824).toStringAsFixed(1)} GiB';
  }
  if (bytes >= 1048576) return '${(bytes / 1048576).toStringAsFixed(1)} MiB';
  return '${(bytes / 1024).toStringAsFixed(1)} KiB';
}

String resourceDateLabel(TorrentRelease release) {
  final raw = release.publishedAt ?? '';
  var date = DateTime.tryParse(raw);
  if (date == null && raw.isNotEmpty) {
    try {
      date = HttpDate.parse(raw).toLocal();
    } on HttpException {
      return '未提供';
    }
  }
  if (date == null) return '未提供';
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

// Shared by the resource table header and its rows.
const resourceTableWidth = 760.0;
const resourceGroupColumnWidth = 120.0;
const resourceSizeColumnWidth = 76.0;
const resourceDateColumnWidth = 84.0;
const resourcePlayWidth = 40.0;

/// Width of the action columns: download (torrents) and play.
double resourceActionsWidth({required bool wide}) =>
    resourceDownloadWidth(labelled: wide, split: true) + resourcePlayWidth;

class ResourceResultRow extends StatelessWidget {
  const ResourceResultRow({
    super.key,
    required this.candidate,
    required this.info,
    required this.expanded,
    required this.onExpand,
    this.notes = const [],
    this.recommended = false,
    this.download,
    this.onPlay,
    this.playing = false,
    this.error,
    this.details,
  });
  final PlayCandidate candidate;
  final ResourceTitleInfo info;
  final bool expanded, recommended, playing;
  final VoidCallback onExpand;

  /// Annotations beside the title's, such as match certainty or health.
  final List<String> notes;

  /// The download button of a torrent, given whether the row is wide.
  final Widget Function(bool wide)? download;

  /// Null when the row cannot be played from here.
  final VoidCallback? onPlay;
  final String? error;

  /// Shown below the original title when expanded, e.g. entries to choose.
  final Widget? details;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= resourceTableWidth;
      final scheme = Theme.of(context).colorScheme;
      final groups = info.sourceGroups.join(' & ');
      final (group, size, date) = switch (candidate.target) {
        ReleaseTarget(candidate: ReleaseCandidate(:final release)) => (
          groups.isEmpty ? '待确认' : groups,
          resourceSizeLabel(release),
          resourceDateLabel(release),
        ),
        DownloadTarget(:final task) => (
          groups.isEmpty ? '—' : groups,
          resourceBytesLabel(task.totalBytes),
          '—',
        ),
        OnlineTarget() => (
          candidate.line.isEmpty ? '—' : candidate.line,
          '在线播放',
          '—',
        ),
      };
      final source = candidate.providerLabel ?? candidate.provider;
      final detailUrl = switch (candidate.target) {
        ReleaseTarget(candidate: ReleaseCandidate(:final release)) =>
          release.detailUrl,
        _ => null,
      };
      final small = Theme.of(context).textTheme.bodySmall;
      final episodeLabel = info.episodeLabel;
      final episodeNote = '$episodeLabel（标题）';
      final labels = info.labels.where((label) => label != episodeNote);
      final notes = [
        ...info.notes.where((note) => note != episodeNote),
        ...this.notes,
      ];
      Widget tag(String text, {Color? background, Color? foreground}) =>
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: background ?? scheme.surfaceContainerLow,
              borderRadius: const BorderRadius.all(Radius.circular(5)),
            ),
            child: Text(
              text,
              style: small?.copyWith(
                fontSize: 11,
                color: foreground,
                fontWeight: foreground == null ? null : FontWeight.w700,
              ),
            ),
          );
      return InkWell(
        key: ValueKey('resource-original:${candidate.id}'),
        onTap: onExpand,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1, right: 2),
                          child: Tooltip(
                            message: expanded ? '收起' : '展开完整原名',
                            child: AnimatedRotation(
                              turns: expanded ? .25 : 0,
                              duration: motionDuration(context, 150),
                              child: Icon(
                                Icons.chevron_right,
                                size: 16,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            info.displayTitle,
                            maxLines: expanded ? null : 1,
                            overflow: expanded ? null : TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (recommended)
                          const Padding(
                            padding: EdgeInsets.only(left: Gap.sm),
                            child: MelonBadge('推荐'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Padding(
                      padding: const EdgeInsets.only(left: 18),
                      child: Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          tag(
                            candidate.kind.label,
                            background: scheme.secondaryContainer,
                          ),
                          if (episodeLabel != null)
                            tag(
                              episodeLabel,
                              background: info.episodeConflict
                                  ? scheme.errorContainer
                                  : scheme.primaryContainer,
                              foreground: info.episodeConflict
                                  ? scheme.onErrorContainer
                                  : scheme.onPrimaryContainer,
                            ),
                          for (final label in labels) tag(label),
                          if (notes.isNotEmpty)
                            Text(
                              notes.join(' · '),
                              style: small?.copyWith(
                                fontSize: 11,
                                color: info.episodeConflict
                                    ? scheme.error
                                    : null,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (!wide)
                      Padding(
                        padding: const EdgeInsets.only(left: 18, top: 5),
                        child: Text(
                          [
                            group,
                            size,
                            date,
                            if (source.isNotEmpty) source,
                          ].join(' · '),
                          style: small,
                        ),
                      ),
                    AnimatedSize(
                      duration: motionDuration(context),
                      alignment: Alignment.topLeft,
                      curve: Curves.easeOutCubic,
                      child: expanded
                          ? Padding(
                              padding: const EdgeInsets.only(left: 18, top: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SelectableText(
                                    info.title,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  if (detailUrl != null)
                                    TextButton.icon(
                                      style: TextButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                      ),
                                      onPressed: () =>
                                          _openSource(context, detailUrl),
                                      icon: const Icon(
                                        Icons.open_in_new,
                                        size: 13,
                                      ),
                                      label: const Text('查看原始发布'),
                                    ),
                                  ?details,
                                ],
                              ),
                            )
                          : const SizedBox(width: double.infinity),
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 18, top: 4),
                        child: Text(
                          error!,
                          style: small?.copyWith(color: scheme.error),
                        ),
                      ),
                  ],
                ),
              ),
              if (wide) ...[
                const SizedBox(width: Gap.md),
                SizedBox(
                  width: resourceGroupColumnWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: small?.copyWith(color: scheme.onSurface),
                      ),
                      Text(source, style: small?.copyWith(fontSize: 10)),
                    ],
                  ),
                ),
                const SizedBox(width: Gap.md),
                SizedBox(
                  width: resourceSizeColumnWidth,
                  child: Text(
                    size,
                    style: small?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: Gap.md),
                SizedBox(
                  width: resourceDateColumnWidth,
                  child: Text(
                    date,
                    style: small?.copyWith(
                      fontSize: 11,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
              const SizedBox(width: Gap.sm),
              SizedBox(
                width: resourceDownloadWidth(labelled: wide, split: true),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: download?.call(wide),
                ),
              ),
              SizedBox(
                width: resourcePlayWidth,
                child: playing
                    ? const Center(
                        child: SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : onPlay == null
                    ? null
                    : IconButton(
                        tooltip: '播放',
                        onPressed: onPlay,
                        icon: const Icon(Icons.play_arrow_rounded),
                      ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Future<void> _openSource(BuildContext context, String url) async {
    try {
      final uri = Uri.parse(url);
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('无法打开原始发布链接。')));
    }
  }
}

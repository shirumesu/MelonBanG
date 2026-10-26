import 'dart:io';

import 'package:flutter/material.dart';

import '../../domain/play_candidate.dart';
import '../../domain/transfer.dart';
import '../../domain/resource_title.dart';
import '../../domain/sources.dart';
import '../../features/appearance/appearance.dart';
import '../core/external_link.dart';
import '../core/byte_units.dart';
import '../core/motion.dart';
import '../core/theme.dart';
import 'download_labels.dart';

/// Width of the download and play columns; rows and the table header share
/// them.
double resourceDownloadWidth({required bool labelled}) => labelled ? 84 : 36;
double resourcePlayWidth({required bool labelled}) => labelled ? 76 : 36;
const _actionGap = 6.0;

/// A compact action of a result row: an icon, and a label when wide.
class _ResourceAction extends StatelessWidget {
  const _ResourceAction({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.width,
    required this.background,
    required this.foreground,
    this.onTap,
  });
  final Widget icon;
  final String? label;
  final String tooltip;
  final double width;
  final Color background, foreground;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: AnimatedContainer(
      duration: motionDuration(context, 150),
      decoration: BoxDecoration(
        color: background,
        borderRadius: controlBorderRadius,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: controlBorderRadius,
          onTap: onTap,
          child: SizedBox(
            width: width,
            height: 34,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox.square(
                  dimension: 18,
                  // A spinner following progress updates in place; a new
                  // state's symbol replaces the old one.
                  child: MotionSwap(
                    value: switch (icon) {
                      Icon(icon: final symbol) => symbol,
                      _ => icon.runtimeType,
                    },
                    child: icon,
                  ),
                ),
                if (label != null) ...[
                  const SizedBox(width: 5),
                  Text(
                    label!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: foreground,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Downloads a torrent or online entry into the cache; once added it
/// follows that task.
class ResourceDownloadButton extends StatelessWidget {
  const ResourceDownloadButton({
    super.key,
    required this.onPressed,
    this.adding = false,
    this.failed = false,
    this.task,
    this.showLabel = false,
  });
  final VoidCallback onPressed;
  final bool adding, failed, showLabel;

  /// The task this button added, while it exists.
  final DownloadTask? task;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final task = this.task;
    final foreground = failed
        ? scheme.tertiary
        : task != null
        ? scheme.primary
        : scheme.onSurface;
    final percent = task == null ? 0 : (task.progress * 100).floor();
    final (Widget icon, String label, String tooltip) = switch (task) {
      _ when adding => (
        Padding(
          padding: const EdgeInsets.all(2),
          child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
        ),
        '加入中',
        '正在加入缓存',
      ),
      DownloadTask(complete: true) => (
        Icon(Icons.download_done_rounded, size: 18, color: foreground),
        '已下载',
        '已下载到本机，可在缓存页查看',
      ),
      final DownloadTask task => (
        Padding(
          padding: const EdgeInsets.all(2),
          child: MotionValue(
            value: task.progress,
            builder: (context, value) => CircularProgressIndicator(
              strokeWidth: 2,
              value: value,
              color: foreground,
              backgroundColor: foreground.withValues(alpha: .2),
            ),
          ),
        ),
        '$percent%',
        '${downloadStatus(task)} $percent%，可在缓存页查看',
      ),
      null when failed => (
        Icon(Icons.refresh_rounded, size: 18, color: foreground),
        '重试',
        '添加失败，点击重试',
      ),
      null => (
        Icon(Icons.download_rounded, size: 18, color: foreground),
        '下载',
        '下载到本机',
      ),
    };
    return Semantics(
      liveRegion: adding || task != null,
      child: _ResourceAction(
        icon: icon,
        label: showLabel ? label : null,
        tooltip: tooltip,
        width: resourceDownloadWidth(labelled: showLabel),
        background: scheme.surfaceContainerHigh,
        foreground: foreground,
        onTap: adding || task != null ? null : onPressed,
      ),
    );
  }
}

/// Plays a result as its chapter; a torrent is added to the cache first.
class ResourcePlayButton extends StatelessWidget {
  const ResourcePlayButton({
    super.key,
    required this.onPressed,
    required this.instant,
    this.playing = false,
    this.showLabel = false,
  });
  final VoidCallback? onPressed;
  final bool instant, playing, showLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _ResourceAction(
      icon: playing
          ? Padding(
              padding: const EdgeInsets.all(2),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.onPrimary,
              ),
            )
          : Icon(Icons.play_arrow_rounded, size: 18, color: scheme.onPrimary),
      label: showLabel ? (playing ? '打开中' : '观看') : null,
      tooltip: instant || playing ? '观看' : '观看，同时下载到本机',
      width: resourcePlayWidth(labelled: showLabel),
      background: scheme.primary,
      foreground: scheme.onPrimary,
      onTap: onPressed,
    );
  }
}

/// Downloads a chosen range of a series' episodes.
class ResourceBatchButton extends StatelessWidget {
  const ResourceBatchButton({
    super.key,
    required this.onPressed,
    this.added = false,
    this.loading = false,
    this.showLabel = false,
  });

  /// Null when none of the episodes belongs to the subject.
  final VoidCallback? onPressed;

  /// Every episode was added from here; [loading] reads the entries first.
  final bool added, loading, showLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = onPressed == null
        ? scheme.onSurface.withValues(alpha: .38)
        : added
        ? scheme.primary
        : scheme.onSurface;
    return _ResourceAction(
      icon: loading
          ? Padding(
              padding: const EdgeInsets.all(2),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: foreground,
              ),
            )
          : Icon(
              added ? Icons.download_done_rounded : Icons.download_rounded,
              size: 18,
              color: foreground,
            ),
      label: showLabel ? (added ? '已添加' : '批量下载') : null,
      tooltip: loading
          ? '正在读取集数'
          : onPressed == null
          ? '没有对应本作的剧集'
          : added
          ? '已全部加入缓存'
          : '选择集数批量下载',
      width: resourceActionsWidth(wide: showLabel),
      background: scheme.surfaceContainerHigh,
      foreground: foreground,
      onTap: loading ? null : onPressed,
    );
  }
}

/// Per-site status line: "动漫花园 12 条 · 蜜柑计划 搜索中 2/5".
String resourceProviderStatus(SourceProgress source) => switch (source.status) {
  SearchStatus.loading => '搜索中 ${source.completed}/${source.total}',
  SearchStatus.error => '搜索失败',
  SearchStatus.partial => '${source.resultCount} 条，部分失败',
  SearchStatus.ready => '${source.resultCount} 条',
};

class ResourceSearchStatus extends StatelessWidget {
  const ResourceSearchStatus({super.key, required this.providers, this.cloud});
  final List<SourceProgress> providers;
  final SourceProgress? cloud;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const LinearProgressIndicator(minHeight: 2),
      const SizedBox(height: Gap.sm),
      Text(
        providers.any((e) => e.status == SearchStatus.loading)
            ? '正在搜索 ${providers.where((e) => e.status != SearchStatus.loading).length}/${providers.length} 个资源站'
            // PikPak stays loading until the sites' group pages finish too.
            : cloud?.status == SearchStatus.loading &&
                  cloud!.completed < cloud!.total
            ? '正在查询 PikPak ${cloud!.completed}/${cloud!.total}'
            : '正在补充字幕组信息',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
}

String resourceSizeLabel(TorrentRelease release, ByteUnits units) {
  final provided = (release.sizeLabel ?? '').trim();
  if (provided.isNotEmpty) return provided;
  return resourceBytesLabel(release.sizeBytes ?? 0, units);
}

String resourceBytesLabel(int bytes, ByteUnits units) =>
    bytes <= 1 ? '—' : units.format(bytes);

String resourceDateLabel(TorrentRelease release) {
  final raw = release.publishedAt ?? '';
  var date = DateTime.tryParse(raw);
  if (date == null && raw.isNotEmpty) {
    try {
      date = HttpDate.parse(raw).toLocal();
    } on HttpException {
      return '—';
    }
  }
  if (date == null) return '—';
  return date.toIso8601String().substring(0, 10);
}

/// Site release groups, else the group the title credits.
String resourceGroupLabel(ResourceTitleInfo info) => info.sourceGroups.isEmpty
    ? info.credit ?? ''
    : info.sourceGroups.join(' & ');

// Shared by the resource table header and its rows.
const resourceTableWidth = 760.0;
const resourceGroupColumnWidth = 120.0;
const resourceSizeColumnWidth = 76.0;
const resourceDateColumnWidth = 84.0;

/// Width of the action columns: download and play.
double resourceActionsWidth({required bool wide}) =>
    resourceDownloadWidth(labelled: wide) +
    _actionGap +
    resourcePlayWidth(labelled: wide);

class ResourceResultRow extends StatelessWidget {
  const ResourceResultRow({
    super.key,
    required this.candidate,
    required this.info,
    required this.expanded,
    required this.onExpand,
    this.notes = const [],
    this.warnings = const [],
    this.recommended = false,
    this.download,
    this.onPlay,
    this.playing = false,
    this.error,
  });
  final PlayCandidate candidate;
  final ResourceTitleInfo info;
  final bool expanded, recommended, playing;
  final VoidCallback onExpand;

  /// Annotations beside the title's, such as duration or progress.
  final List<String> notes;

  /// Annotations that need attention, such as match certainty or health.
  final List<String> warnings;

  /// The download button, given whether the row is wide.
  final Widget Function(bool wide)? download;

  /// Null when the row cannot be played from here.
  final VoidCallback? onPlay;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    final units = ByteUnitsScope.of(context);
    final groups = resourceGroupLabel(info);
    final (group, size, date) = switch (candidate.target) {
      ReleaseTarget(candidate: ReleaseCandidate(:final release)) => (
        groups,
        resourceSizeLabel(release, units),
        resourceDateLabel(release),
      ),
      DownloadTarget(:final task) => (
        groups,
        resourceBytesLabel(task.totalBytes, units),
        '—',
      ),
      OnlineTarget() => (candidate.line, '—', '—'),
    };
    final detailUrl = switch (candidate.target) {
      ReleaseTarget(candidate: ReleaseCandidate(:final release)) =>
        release.detailUrl,
      _ => null,
    };
    final episodeLabel = info.episodeLabel;
    return _ResourceRowFrame(
      title: info.displayTitle,
      wrapTitle: expanded,
      expanded: expanded,
      expandTooltip: '显示原标题',
      onExpand: onExpand,
      recommended: recommended,
      kind: switch (candidate.target) {
        DownloadTarget() =>
          candidate.kind == PlayKind.local
              ? '本地'
              : '${candidate.providerLabel} 缓存中',
        OnlineTarget() => '在线',
        ReleaseTarget() => candidate.kind.label,
      },
      span: episodeLabel == null
          ? null
          : info.batch
          ? '合集 $episodeLabel'
          : episodeLabel,
      spanConflict: info.episodeConflict,
      labels: info.labels,
      notes: [
        if (info.titleCredits.length > 1) info.titleCredits.join(' & '),
        ...notes,
      ],
      warnings: [...info.warnings, ...warnings],
      group: group,
      size: size,
      date: date,
      source: candidate.providerLabel ?? candidate.provider,
      details: [
        _OriginalTitle(
          title: expanded ? info.title : null,
          detailUrl: detailUrl,
          padding: const EdgeInsets.only(left: 18, top: 8),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(left: 18, top: 4),
            child: Text(error!, style: small?.copyWith(color: scheme.error)),
          ),
      ],
      actions: (wide) => Row(
        children: [
          SizedBox(
            width: resourceDownloadWidth(labelled: wide),
            child: download?.call(wide),
          ),
          const SizedBox(width: _actionGap),
          SizedBox(
            width: resourcePlayWidth(labelled: wide),
            child: playing || onPlay != null
                ? ResourcePlayButton(
                    onPressed: onPlay,
                    instant: candidate.instant,
                    playing: playing,
                    showLabel: wide,
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

/// The layout the resource rows share: a chevron and [title] over the tags,
/// the group, size and date in columns on a wide row or in a line under the
/// tags otherwise, then the [actions].
class _ResourceRowFrame extends StatelessWidget {
  const _ResourceRowFrame({
    required this.title,
    required this.wrapTitle,
    required this.expanded,
    required this.expandTooltip,
    required this.onExpand,
    required this.recommended,
    required this.kind,
    required this.span,
    this.spanConflict = false,
    required this.labels,
    required this.notes,
    required this.warnings,
    required this.group,
    required this.size,
    required this.date,
    required this.source,
    this.details = const [],
    required this.actions,
  });
  final String title, expandTooltip, kind, group, size, date, source;
  final bool wrapTitle, expanded, recommended, spanConflict;
  final VoidCallback onExpand;

  /// The episodes the row covers, highlighted; in error colours when they
  /// contradict the title.
  final String? span;
  final List<String> labels, notes, warnings;

  /// Shown under the tags.
  final List<Widget> details;

  /// The row's buttons, given whether the row is wide.
  final Widget? Function(bool wide) actions;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= resourceTableWidth;
      final scheme = Theme.of(context).colorScheme;
      final small = Theme.of(context).textTheme.bodySmall;
      final figures = small?.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      );
      return InkWell(
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
                          child: _RowChevron(
                            expanded: expanded,
                            tooltip: expandTooltip,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: wrapTitle ? null : 1,
                            overflow: wrapTitle ? null : TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
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
                          if (recommended)
                            Tooltip(
                              message: '综合画质、字幕和大小推荐',
                              child: _tag(
                                context,
                                '推荐',
                                background: scheme.primary,
                                foreground: scheme.onPrimary,
                              ),
                            ),
                          _tag(
                            context,
                            kind,
                            background: scheme.secondaryContainer,
                          ),
                          if (span case final span?)
                            _tag(
                              context,
                              span,
                              background: spanConflict
                                  ? scheme.errorContainer
                                  : scheme.primaryContainer,
                              foreground: spanConflict
                                  ? scheme.onErrorContainer
                                  : scheme.onPrimaryContainer,
                            ),
                          for (final label in labels) _tag(context, label),
                          for (final note in notes)
                            _tag(context, note, background: Colors.transparent),
                          for (final warning in warnings)
                            _tag(
                              context,
                              warning,
                              background: scheme.tertiaryContainer,
                              foreground: scheme.onTertiaryContainer,
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
                            source,
                          ].where((e) => e.isNotEmpty && e != '—').join('  '),
                          style: small,
                        ),
                      ),
                    ...details,
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
                        group.isEmpty ? '—' : group,
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
                  child: Text(size, style: figures),
                ),
                const SizedBox(width: Gap.md),
                SizedBox(
                  width: resourceDateColumnWidth,
                  child: Text(date, style: figures?.copyWith(fontSize: 11)),
                ),
              ],
              const SizedBox(width: Gap.sm),
              SizedBox(
                width: resourceActionsWidth(wide: wide),
                child: actions(wide),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// A release's original [title] and a link to its page, unfolding when the
/// title is given.
class _OriginalTitle extends StatelessWidget {
  const _OriginalTitle({
    required this.title,
    required this.detailUrl,
    required this.padding,
  });
  final String? title, detailUrl;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => AnimatedSize(
    duration: motionDuration(context),
    alignment: Alignment.topLeft,
    curve: Curves.easeOutCubic,
    child: title == null
        ? const SizedBox(width: double.infinity)
        : Padding(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(title!, style: const TextStyle(fontSize: 12)),
                if (detailUrl case final url?)
                  TextButton.icon(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    onPressed: () => openExternal(context, url),
                    icon: const Icon(Icons.open_in_new, size: 13),
                    label: const Text('打开发布页'),
                  ),
              ],
            ),
          ),
  );
}

/// Turns down while its row is [expanded]; [tooltip] says what expanding
/// shows.
class _RowChevron extends StatelessWidget {
  const _RowChevron({required this.expanded, required this.tooltip});
  final bool expanded;
  final String tooltip;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: expanded ? '收起' : tooltip,
    child: AnimatedRotation(
      turns: expanded ? .25 : 0,
      duration: motionDuration(context, 150),
      child: Icon(
        Icons.chevron_right,
        size: 16,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

Widget _tag(
  BuildContext context,
  String text, {
  Color? background,
  Color? foreground,
}) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
  decoration: BoxDecoration(
    color: background ?? Theme.of(context).colorScheme.surfaceContainerLow,
    borderRadius: const BorderRadius.all(Radius.circular(5)),
  ),
  child: Text(
    text,
    style: Theme.of(context).textTheme.bodySmall?.copyWith(
      fontSize: 11,
      color: foreground,
      fontWeight: foreground == null ? null : FontWeight.w700,
    ),
  ),
);

/// The heading of a series: one group's single-episode releases of it on
/// one site, or an online site subject. It shows the episodes it covers and
/// the tags they share, so its episodes list only what sets them apart.
/// Tapping it shows the episodes; its action downloads a range of them.
class ResourceSeriesRow extends StatelessWidget {
  const ResourceSeriesRow({
    super.key,
    required this.candidate,
    required this.info,
    required this.title,
    required this.group,
    required this.expanded,
    required this.onExpand,
    this.coverage,
    this.size = '—',
    this.date = '—',
    this.notes = const [],
    this.warnings = const [],
    this.recommended = false,
    this.action,
  });

  /// The best release or the site subject, which supplies the kind, site
  /// and tags.
  final PlayCandidate candidate;
  final ResourceTitleInfo info;
  final String title, group, size, date;

  /// The episodes it covers, once known.
  final String? coverage;
  final bool expanded, recommended;
  final VoidCallback onExpand;
  final List<String> notes, warnings;

  /// The batch download button, given whether the row is wide.
  final Widget Function(bool wide)? action;

  @override
  Widget build(BuildContext context) => _ResourceRowFrame(
    title: title,
    wrapTitle: false,
    expanded: expanded,
    expandTooltip: '展开各集',
    onExpand: onExpand,
    recommended: recommended,
    kind: candidate.kind.label,
    span: coverage,
    labels: info.labels,
    notes: notes,
    warnings: warnings,
    group: group,
    size: size,
    date: date,
    source: candidate.providerLabel ?? candidate.provider,
    actions: (wide) => action?.call(wide),
  );
}

/// The episodes of an expanded series, inset under its title on a tinted
/// panel whose rows keep the table's columns.
class ResourceEpisodePanel extends StatelessWidget {
  const ResourceEpisodePanel({super.key, required this.rows});

  /// The rows, given whether the table is wide.
  final List<Widget> Function(bool wide) rows;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Padding(
      padding: const EdgeInsets.fromLTRB(26, 0, 8, 10),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: controlBorderRadius,
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rows(constraints.maxWidth >= resourceTableWidth),
          ),
        ),
      ),
    ),
  );
}

/// One episode of an expanded series: its number and what sets it apart,
/// with the table's size and date columns and actions. Tapping it shows the
/// original title when it has one.
class ResourceEpisodeRow extends StatelessWidget {
  const ResourceEpisodeRow({
    super.key,
    required this.label,
    required this.wide,
    this.title,
    this.detailUrl,
    this.expanded = false,
    this.onExpand,
    this.notes = const [],
    this.warnings = const [],
    this.size = '',
    this.date = '',
    this.download,
    this.play,
    this.error,
  });
  final String label;
  final bool wide, expanded;

  /// The original title and release page, shown when expanded.
  final String? title, detailUrl;
  final VoidCallback? onExpand;
  final List<String> notes, warnings;
  final String size, date;
  final Widget? download, play;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    final meta = [size, date].where((e) => e.isNotEmpty && e != '—');
    Widget cell(double width, String text, {double? fontSize}) => SizedBox(
      width: width,
      height: 34,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: small?.copyWith(
            fontSize: fontSize,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
    return InkWell(
      onTap: title == null ? null : onExpand,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 34),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 18,
                          child: onExpand == null || title == null
                              ? null
                              : _RowChevron(
                                  expanded: expanded,
                                  tooltip: '显示原标题',
                                ),
                        ),
                        Text(
                          label,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Wrap(
                            spacing: 5,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              for (final note in notes)
                                _tag(
                                  context,
                                  note,
                                  background: Colors.transparent,
                                ),
                              for (final warning in warnings)
                                _tag(
                                  context,
                                  warning,
                                  background: scheme.tertiaryContainer,
                                  foreground: scheme.onTertiaryContainer,
                                ),
                              if (!wide && meta.isNotEmpty)
                                Text(meta.join('  '), style: small),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  _OriginalTitle(
                    title: expanded ? title : null,
                    detailUrl: detailUrl,
                    padding: const EdgeInsets.only(left: 18, bottom: 4),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 18, bottom: 4),
                      child: Text(
                        error!,
                        style: small?.copyWith(color: scheme.error),
                      ),
                    ),
                ],
              ),
            ),
            if (wide) ...[
              const SizedBox(width: Gap.md + resourceGroupColumnWidth + Gap.md),
              cell(resourceSizeColumnWidth, size),
              const SizedBox(width: Gap.md),
              cell(resourceDateColumnWidth, date, fontSize: 11),
            ],
            const SizedBox(width: Gap.sm),
            SizedBox(
              width: resourceDownloadWidth(labelled: wide),
              child: download,
            ),
            const SizedBox(width: _actionGap),
            SizedBox(
              width: resourcePlayWidth(labelled: wide),
              child: play,
            ),
          ],
        ),
      ),
    );
  }
}

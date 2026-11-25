import 'package:flutter/material.dart';

import '../../core/notices.dart';
import '../../domain/play_candidate.dart';
import '../../domain/transfer.dart';
import '../../domain/resource_title.dart';
import '../../domain/sources.dart';
import '../core/action_feedback.dart';
import '../core/external_link.dart';
import '../core/byte_units.dart';
import '../core/motion.dart';
import '../core/theme.dart';
import '../core/tone.dart';
import '../downloads/download_labels.dart';
import 'resource_labels.dart';

/// Width of the download and play columns; rows and the table header share
/// them.
double _downloadWidth({required bool labelled}) => labelled ? 84 : 36;
double _playWidth({required bool labelled}) => labelled ? 76 : 36;
const _actionGap = Gap.sm;

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
                  // A progress ring updates in place; a new state's symbol
                  // replaces the old one.
                  child: MotionSwap(
                    value: switch (icon) {
                      Icon(icon: final symbol) => symbol,
                      _ => icon.runtimeType,
                    },
                    child: icon,
                  ),
                ),
                if (label != null) ...[
                  const SizedBox(width: Gap.xs),
                  Text(
                    label!,
                    style: TextStyle(
                      fontSize: FontSize.small,
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
  Widget build(BuildContext context) =>
      DelayedBusy(busy: adding, builder: _build);

  Widget _build(BuildContext context, bool spinning) {
    final scheme = Theme.of(context).colorScheme;
    final task = this.task;
    final foreground = failed
        ? toneColor(context, NoticeTone.failed)
        : task != null
        ? scheme.primary
        : scheme.onSurface;
    final percent = task == null ? 0 : (task.progress * 100).floor();
    final (Widget icon, String label, String tooltip) = switch (task) {
      _ when spinning => (
        Padding(
          padding: const EdgeInsets.all(2),
          child: BusyIndicator(size: 14, color: foreground),
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
        '添加失败',
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
        width: _downloadWidth(labelled: showLabel),
        background: scheme.surfaceContainerHigh,
        foreground: foreground,
        onTap: adding || spinning || task != null ? null : onPressed,
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
  Widget build(BuildContext context) =>
      DelayedBusy(busy: playing, builder: _build);

  Widget _build(BuildContext context, bool spinning) {
    final scheme = Theme.of(context).colorScheme;
    return _ResourceAction(
      icon: spinning
          ? Padding(
              padding: const EdgeInsets.all(2),
              child: BusyIndicator(size: 14, color: scheme.onPrimaryContainer),
            )
          : Icon(
              Icons.play_arrow_rounded,
              size: 18,
              color: scheme.onPrimaryContainer,
            ),
      label: showLabel ? (spinning ? '打开中' : '观看') : null,
      tooltip: instant || playing ? '观看' : '观看，同时下载到本机',
      width: _playWidth(labelled: showLabel),
      background: scheme.primaryContainer,
      foreground: scheme.onPrimaryContainer,
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
  Widget build(BuildContext context) =>
      DelayedBusy(busy: loading, builder: _build);

  Widget _build(BuildContext context, bool spinning) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = onPressed == null
        ? scheme.onSurface.withValues(alpha: .38)
        : added
        ? scheme.primary
        : scheme.onSurface;
    return _ResourceAction(
      icon: spinning
          ? Padding(
              padding: const EdgeInsets.all(2),
              child: BusyIndicator(size: 14, color: foreground),
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
      onTap: loading || spinning ? null : onPressed,
    );
  }
}

/// A running search's progress. Sites are waited on under a progress bar
/// until [settled]; then the sites still loading, and the PikPak and release
/// group lookups that only add to what shows, are a quiet line.
class ResourceSearchStatus extends StatelessWidget {
  const ResourceSearchStatus({
    super.key,
    required this.providers,
    this.cloud,
    required this.settled,
  });
  final List<SourceProgress> providers;
  final SourceProgress? cloud;

  /// Whether results show and the search has run past its patience, so a
  /// slow site no longer holds the page.
  final bool settled;

  @override
  Widget build(BuildContext context) {
    final pending = [
      for (final provider in providers)
        if (provider.status == SearchStatus.loading) provider.sourceName,
    ];
    // No site has reported yet while the subject's episodes load.
    final starting = providers.isEmpty;
    final waiting = starting || (pending.isNotEmpty && !settled);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        waiting
            ? const LinearProgressIndicator(minHeight: 2)
            : const SizedBox(height: 2),
        const SizedBox(height: Gap.sm),
        Text(
          starting
              ? '正在准备搜索'
              : waiting
              ? '正在搜索 ${providers.length - pending.length}/${providers.length} 个资源站'
              : pending.isNotEmpty
              ? '${pending.take(3).join('、')}'
                    '${pending.length > 3 ? ' 等 ${pending.length} 个资源站' : ''}'
                    '响应较慢，找到的资源会自动加入'
              // PikPak stays loading until the sites' group pages finish too.
              : cloud?.status == SearchStatus.loading &&
                    cloud!.completed < cloud!.total
              ? '正在查询 PikPak ${cloud!.completed}/${cloud!.total}'
              : '正在补充字幕组信息',
          style: theme.textTheme.bodySmall?.copyWith(
            color: waiting ? null : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// Shared by the resource table header and its rows.
const resourceTableWidth = 760.0;
const resourceGroupColumnWidth = 120.0;
const resourceSizeColumnWidth = 76.0;
const resourceDateColumnWidth = 84.0;

double resourceActionsWidth({required bool wide}) =>
    _downloadWidth(labelled: wide) + _actionGap + _playWidth(labelled: wide);

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

  /// Annotations beside the title's own, such as 上次选择.
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
          padding: const EdgeInsets.only(left: 18, top: Gap.sm),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(left: 18, top: Gap.xs),
            child: InlineIssue(error!),
          ),
      ],
      actions: (wide) => Row(
        children: [
          SizedBox(
            width: _downloadWidth(labelled: wide),
            child: download?.call(wide),
          ),
          const SizedBox(width: _actionGap),
          SizedBox(
            width: _playWidth(labelled: wide),
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

/// The layout the resource rows share: the group, size and date in columns
/// on a wide row, else in a line under the tags.
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
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.lg,
            vertical: Gap.md,
          ),
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
                              fontSize: FontSize.body,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Gap.xs),
                    Padding(
                      padding: const EdgeInsets.only(left: 18),
                      child: Wrap(
                        spacing: Gap.xs,
                        runSpacing: Gap.xs,
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
                                bold: true,
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
                        padding: const EdgeInsets.only(left: 18, top: Gap.xs),
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
                      Text(
                        source,
                        style: small?.copyWith(fontSize: FontSize.caption),
                      ),
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
                  child: Text(
                    date,
                    style: figures?.copyWith(fontSize: FontSize.small),
                  ),
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
                SelectableText(
                  title!,
                  style: const TextStyle(fontSize: FontSize.small),
                ),
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
  bool bold = false,
}) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
  decoration: BoxDecoration(
    color: background ?? Theme.of(context).colorScheme.surfaceContainerLow,
    borderRadius: badgeBorderRadius,
  ),
  child: Text(
    text,
    style: Theme.of(context).textTheme.bodySmall?.copyWith(
      fontSize: FontSize.caption,
      color: foreground,
      fontWeight: bold ? FontWeight.w700 : null,
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
    this.labels,
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

  /// The tags, when not [info]'s own: a series in several subtitle
  /// versions names each.
  final List<String>? labels;
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
    labels: labels ?? info.labels,
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
      padding: const EdgeInsets.fromLTRB(26, 0, Gap.sm, Gap.sm),
      child: Material(
        color: insetSurface(context),
        borderRadius: controlBorderRadius,
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Gap.xs),
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
    Widget cell(double width, String text) => SizedBox(
      width: width,
      height: 34,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: small?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
    return InkWell(
      onTap: title == null ? null : onExpand,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Gap.sm,
          vertical: Gap.xs,
        ),
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
                        // An upload's part names run long.
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 280),
                          child: Tooltip(
                            message: label.length > 16 ? label : '',
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: FontSize.body,
                                fontWeight: FontWeight.w700,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: Gap.md),
                        Expanded(
                          child: Wrap(
                            spacing: Gap.xs,
                            runSpacing: Gap.xs,
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
                    padding: const EdgeInsets.only(left: 18, bottom: Gap.xs),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 18, bottom: Gap.xs),
                      child: InlineIssue(error!),
                    ),
                ],
              ),
            ),
            if (wide) ...[
              const SizedBox(width: Gap.md + resourceGroupColumnWidth + Gap.md),
              cell(resourceSizeColumnWidth, size),
              const SizedBox(width: Gap.md),
              cell(resourceDateColumnWidth, date),
            ],
            const SizedBox(width: Gap.sm),
            SizedBox(
              width: _downloadWidth(labelled: wide),
              child: download,
            ),
            const SizedBox(width: _actionGap),
            SizedBox(
              width: _playWidth(labelled: wide),
              child: play,
            ),
          ],
        ),
      ),
    );
  }
}

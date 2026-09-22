import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/json.dart';
import '../../data/resource_metadata.dart';
import '../../data/resource_title.dart';
import '../core/motion.dart';
import '../core/page_widgets.dart';
import '../core/theme.dart';

enum ResourceDownloadPhase { idle, adding, added, failed }

class ResourceDownloadButton extends StatelessWidget {
  const ResourceDownloadButton({
    super.key,
    required this.phase,
    required this.onPressed,
    this.error,
    this.showLabel = false,
  });
  final ResourceDownloadPhase phase;
  final VoidCallback onPressed;
  final String? error;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final label = switch (phase) {
      ResourceDownloadPhase.idle => '下载',
      ResourceDownloadPhase.adding => '正在加入下载…',
      ResourceDownloadPhase.added => '已加入下载',
      ResourceDownloadPhase.failed =>
        '添加失败，点击重试${error == null ? '' : '\n$error'}',
    };
    final action =
        [
          ResourceDownloadPhase.adding,
          ResourceDownloadPhase.added,
        ].contains(phase)
        ? null
        : onPressed;
    final icon = SizedBox.square(
      dimension: 24,
      child: AnimatedSwitcher(
        duration: motionDuration(context, 150),
        child: phase == ResourceDownloadPhase.adding
            ? const Padding(
                key: ValueKey(ResourceDownloadPhase.adding),
                padding: EdgeInsets.all(3),
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                switch (phase) {
                  ResourceDownloadPhase.added => Icons.check_circle_outline,
                  ResourceDownloadPhase.failed => Icons.refresh,
                  _ => Icons.download_outlined,
                },
                key: ValueKey(phase),
                color: phase == ResourceDownloadPhase.failed ? gold : mint,
              ),
      ),
    );
    return Semantics(
      liveRegion: phase != ResourceDownloadPhase.idle,
      child: showLabel
          ? Tooltip(
              message: label,
              child: SizedBox(
                width: 92,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  onPressed: action,
                  icon: icon,
                  label: Text(switch (phase) {
                    ResourceDownloadPhase.adding => '加入中',
                    ResourceDownloadPhase.added => '已加入',
                    ResourceDownloadPhase.failed => '重试',
                    _ => '下载',
                  }),
                ),
              ),
            )
          : IconButton(tooltip: label, onPressed: action, icon: icon),
    );
  }
}

String resourceProviderKey(Json provider) =>
    '${provider['providerId'] ?? provider['providerName'] ?? ''}';

class ResourceProgress extends StatelessWidget {
  const ResourceProgress({
    super.key,
    required this.providers,
    required this.busy,
    this.excludedProviders = const {},
    this.onProviderSelected,
  });
  final List<Json> providers;
  final bool busy;
  final Set<String> excludedProviders;
  final void Function(String, bool)? onProviderSelected;

  Widget providerChip(BuildContext context, Json provider) {
    final id = resourceProviderKey(provider);
    final selected = !excludedProviders.contains(id);
    final label =
        '${provider['providerName']} · ${resourceProviderLabel(provider)}';
    final message =
        '${provider['message'] ?? provider['metadataMessage'] ?? ''}';
    final warning = ['error', 'partial'].contains(provider['status']);
    if (onProviderSelected == null) {
      return Tooltip(
        message: message,
        child: MelonBadge(label, color: warning ? gold : mint),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return FilterChip(
      key: ValueKey('resource-provider:$id'),
      tooltip: [
        selected
            ? '点击隐藏${provider['providerName']}的资源'
            : '点击显示${provider['providerName']}的资源',
        if (message.isNotEmpty) message,
      ].join('\n'),
      selected: selected,
      showCheckmark: true,
      checkmarkColor: scheme.primary,
      backgroundColor: scheme.surfaceContainerHigh,
      selectedColor: scheme.primary.withValues(alpha: .12),
      labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: selected ? scheme.primary : scheme.onSurfaceVariant,
      ),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (warning) ...[
            const SizedBox(width: 5),
            Icon(Icons.warning_amber_rounded, size: 15, color: scheme.tertiary),
          ],
        ],
      ),
      onSelected: (value) => onProviderSelected!(id, value),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final provider in providers) providerChip(context, provider),
        ],
      ),
      if (busy) ...[
        const SizedBox(height: 12),
        const LinearProgressIndicator(minHeight: 2),
        const SizedBox(height: 8),
        Text(
          providers.every((e) => number(e['resultCount']) == 0)
              ? '正在查找资源，结果会陆续显示'
              : providers.any((e) => e['status'] == 'loading')
              ? '已找到的资源可直接下载，其余结果陆续加入'
              : '正在补充字幕组信息，资源已可下载',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
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

String resourceDetails(Json candidate) {
  final groups = (candidate['releaseGroups'] as List? ?? []).join(' & ');
  final size = resourceSizeLabel(candidate);
  final published = '${candidate['publishedAt'] ?? ''}';
  final date = DateTime.tryParse(published);
  final publishedLabel = date == null
      ? published
      : '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  return [
    candidate['providerName'],
    if (groups.isNotEmpty) groups,
    size,
    publishedLabel,
  ].where((e) => e != null && '$e'.isNotEmpty).join(' · ');
}

String resourceSizeLabel(Json candidate) {
  final provided = '${candidate['sizeLabel'] ?? ''}'.trim();
  if (provided.isNotEmpty) return provided;
  final bytes = number(candidate['sizeBytes']);
  if (bytes <= 1) return '大小未知';
  if (bytes >= 1073741824) {
    return '${(bytes / 1073741824).toStringAsFixed(1)} GiB';
  }
  if (bytes >= 1048576) return '${(bytes / 1048576).toStringAsFixed(1)} MiB';
  return '${(bytes / 1024).toStringAsFixed(1)} KiB';
}

String resourceDateLabel(Json candidate) {
  final raw = '${candidate['publishedAt'] ?? ''}';
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

class ResourceResultRow extends StatelessWidget {
  const ResourceResultRow({
    super.key,
    required this.candidate,
    required this.info,
    required this.expanded,
    required this.onExpand,
    required this.phase,
    required this.onDownload,
    this.error,
  });
  final Json candidate;
  final ResourceTitleInfo info;
  final bool expanded;
  final VoidCallback onExpand, onDownload;
  final ResourceDownloadPhase phase;
  final String? error;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 760;
      final scheme = Theme.of(context).colorScheme;
      final group = info.sourceGroups.isEmpty
          ? '待确认'
          : info.sourceGroups.join(' & ');
      final size = resourceSizeLabel(candidate);
      final date = resourceDateLabel(candidate);
      final source = '${candidate['providerName'] ?? ''}';
      final small = Theme.of(context).textTheme.bodySmall;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    info.displayTitle,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (info.labels.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('标题标注', style: small?.copyWith(fontSize: 11)),
                        for (final label in info.labels)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              label,
                              style: small?.copyWith(fontSize: 11),
                            ),
                          ),
                      ],
                    ),
                  ],
                  if (info.notes.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        info.notes.join(' · '),
                        style: small?.copyWith(
                          fontSize: 11,
                          color: info.episodeConflict ? scheme.error : null,
                        ),
                      ),
                    ),
                  if (!wide)
                    Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Text(
                        '来源分组：$group · $size · $date${source.isEmpty ? '' : ' · $source'}',
                        style: small,
                      ),
                    ),
                  TextButton.icon(
                    key: ValueKey(
                      'resource-original:${candidate['candidateId']}',
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 0,
                        vertical: 4,
                      ),
                      minimumSize: const Size(0, 30),
                      foregroundColor: scheme.onSurfaceVariant,
                      textStyle: const TextStyle(fontSize: 11),
                    ),
                    onPressed: onExpand,
                    icon: AnimatedRotation(
                      turns: expanded ? .25 : 0,
                      duration: motionDuration(context, 150),
                      child: const Icon(Icons.chevron_right, size: 15),
                    ),
                    label: Text(expanded ? '收起原名' : '完整原名'),
                  ),
                  AnimatedSize(
                    duration: motionDuration(context),
                    alignment: Alignment.topLeft,
                    curve: Curves.easeOutCubic,
                    child: expanded
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SelectableText(
                                info.title,
                                style: const TextStyle(fontSize: 12),
                              ),
                              if (candidate['detailUrl'] != null)
                                TextButton.icon(
                                  onPressed: () => _openSource(context),
                                  icon: const Icon(Icons.open_in_new, size: 13),
                                  label: const Text('查看原始发布'),
                                ),
                            ],
                          )
                        : const SizedBox.shrink(),
                  ),
                  if (error != null)
                    Text(
                      '添加失败：$error',
                      style: small?.copyWith(color: scheme.error),
                    ),
                ],
              ),
            ),
            if (wide) ...[
              const SizedBox(width: 18),
              SizedBox(
                width: 106,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(group, style: small),
                    const SizedBox(height: 3),
                    Text(source, style: small?.copyWith(fontSize: 10)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(width: 72, child: Text(size, style: small)),
              const SizedBox(width: 12),
              SizedBox(
                width: 80,
                child: Text(date, style: small?.copyWith(fontSize: 11)),
              ),
            ],
            const SizedBox(width: 8),
            ResourceDownloadButton(
              phase: phase,
              error: error,
              showLabel: wide,
              onPressed: onDownload,
            ),
          ],
        ),
      );
    },
  );

  Future<void> _openSource(BuildContext context) async {
    try {
      final uri = Uri.parse('${candidate['detailUrl']}');
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('无法打开原始发布链接。')));
    }
  }
}

bool matchesResource(Json candidate, String title, String group) {
  final release = '${candidate['title']}'.toLowerCase();
  final groups = (candidate['releaseGroups'] as List? ?? [])
      .join(' ')
      .toLowerCase();
  return release.contains(title.trim().toLowerCase()) &&
      (groups.contains(group.trim().toLowerCase()) ||
          release.contains(group.trim().toLowerCase()));
}

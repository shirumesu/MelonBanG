import 'package:flutter/material.dart';

import '../../data/json.dart';
import '../../data/resource_metadata.dart';
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
  });
  final ResourceDownloadPhase phase;
  final VoidCallback onPressed;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final label = switch (phase) {
      ResourceDownloadPhase.idle => '下载',
      ResourceDownloadPhase.adding => '正在加入下载…',
      ResourceDownloadPhase.added => '已加入下载',
      ResourceDownloadPhase.failed =>
        '添加失败，点击重试${error == null ? '' : '\n$error'}',
    };
    return Semantics(
      liveRegion: phase != ResourceDownloadPhase.idle,
      child: IconButton(
        tooltip: label,
        onPressed:
            [
              ResourceDownloadPhase.adding,
              ResourceDownloadPhase.added,
            ].contains(phase)
            ? null
            : onPressed,
        icon: SizedBox.square(
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
        ),
      ),
    );
  }
}

class ResourceProgress extends StatelessWidget {
  const ResourceProgress({
    super.key,
    required this.providers,
    required this.busy,
  });
  final List<Json> providers;
  final bool busy;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final provider in providers)
            Tooltip(
              message:
                  '${provider['message'] ?? provider['metadataMessage'] ?? ''}',
              child: MelonBadge(
                '${provider['providerName']} · ${resourceProviderLabel(provider)}',
                color: ['error', 'partial'].contains(provider['status'])
                    ? gold
                    : mint,
              ),
            ),
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
  final size =
      candidate['sizeLabel'] ??
      (number(candidate['sizeBytes']) > 0
          ? '${(number(candidate['sizeBytes']) / 1048576).toStringAsFixed(1)} MiB'
          : null);
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

bool matchesResource(Json candidate, String title, String group) {
  final release = '${candidate['title']}'.toLowerCase();
  final groups = (candidate['releaseGroups'] as List? ?? [])
      .join(' ')
      .toLowerCase();
  return release.contains(title.trim().toLowerCase()) &&
      (groups.contains(group.trim().toLowerCase()) ||
          release.contains(group.trim().toLowerCase()));
}

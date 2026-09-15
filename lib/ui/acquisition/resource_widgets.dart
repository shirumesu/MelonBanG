import 'package:flutter/material.dart';

import '../../data/json.dart';
import '../../data/resource_metadata.dart';
import '../core/page_widgets.dart';
import '../core/theme.dart';

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
          providers.any((e) => e['status'] == 'loading')
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

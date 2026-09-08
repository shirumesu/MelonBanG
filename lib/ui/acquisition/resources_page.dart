import 'package:flutter/material.dart';

import '../../data/json.dart';
import '../core/page_widgets.dart';
import '../core/theme.dart';

class ResourcesPage extends StatelessWidget {
  const ResourcesPage({
    super.key,
    required this.subject,
    required this.resourceSearch,
    required this.resourceEpisode,
    required this.providers,
    required this.candidates,
    required this.busy,
    required this.onSearch,
    required this.onDownload,
  });
  final Json? subject;
  final TextEditingController resourceSearch;
  final int? resourceEpisode;
  final List<Json> providers, candidates;
  final bool busy;
  final VoidCallback onSearch;
  final ValueChanged<Json> onDownload;
  String get episodeLabel {
    final episode = objects(subject?['episodes'])
        .where((item) => item['episodeId'] == resourceEpisode)
        .firstOrNull;
    return episode == null ? '所选章节' : '第 ${episode['sort']} 话';
  }

  @override
  Widget build(BuildContext context) => PageScroll(
    children: [
      const SizedBox(height: 10),
      MelonPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titleOf(subject ?? {}),
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              resourceEpisode == null ? '搜索适合你的字幕与视频版本' : '下载将关联到$episodeLabel',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: resourceSearch,
                    onSubmitted: (_) => onSearch(),
                    decoration: const InputDecoration(
                      labelText: '资源关键词',
                      prefixIcon: Icon(Icons.search, size: 19),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: busy ? null : onSearch,
                  child: const Text('搜索'),
                ),
              ],
            ),
            if (providers.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final provider in providers)
                    MelonBadge(
                      '${provider['providerName']} · ${provider['message'] ?? '${provider['resultCount']} 条资源'}',
                      color: provider['status'] == 'error' ? gold : mint,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      SectionTitle(
        title: '资源结果',
        subtitle: '${candidates.length} 条',
        icon: Icons.download_outlined,
        color: mint,
      ),
      for (final candidate in candidates)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: MelonPanel(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    Icons.video_file_outlined,
                    color: mint,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${candidate['title']}',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${candidate['providerName']} · ${candidate['publishedAt'] ?? ''}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                IconButton(
                  tooltip: '下载',
                  onPressed: () => onDownload(candidate),
                  icon: const Icon(Icons.download_outlined, color: mint),
                ),
              ],
            ),
          ),
        ),
      if (candidates.isEmpty && !busy)
        const EmptyState(text: '没有找到资源，试试原名或其他关键词'),
    ],
  );
}

import 'package:flutter/material.dart';

import '../../data/json.dart';
import '../core/page_widgets.dart';

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
  final List<Json> providers;
  final List<Json> candidates;
  final bool busy;
  final VoidCallback onSearch;
  final ValueChanged<Json> onDownload;
  @override
  Widget build(BuildContext context) => PageScroll(
    children: [
      SectionTitle(title: titleOf(subject ?? {})),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: resourceSearch,
              onSubmitted: (_) => onSearch(),
              decoration: const InputDecoration(labelText: '资源关键词'),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(onPressed: onSearch, child: const Text('搜索')),
        ],
      ),
      const SizedBox(height: 12),
      if (resourceEpisode != null) Text('下载将关联到所选章节 · $resourceEpisode'),
      for (final provider in providers)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            '${provider['providerName']} · ${provider['message'] ?? '${provider['resultCount']} 条资源'}',
            style: TextStyle(
              color: provider['status'] == 'error'
                  ? Colors.orange
                  : Colors.grey,
            ),
          ),
        ),
      const SizedBox(height: 12),
      for (final candidate in candidates)
        Card(
          child: ListTile(
            title: Text('${candidate['title']}'),
            subtitle: Text(
              '${candidate['providerName']} · ${candidate['publishedAt'] ?? ''}',
            ),
            trailing: IconButton(
              tooltip: '下载',
              icon: const Icon(Icons.download),
              onPressed: () => onDownload(candidate),
            ),
          ),
        ),
      if (candidates.isEmpty && !busy) EmptyState(text: '没有找到资源，试试原名或其他关键词'),
    ],
  );
}

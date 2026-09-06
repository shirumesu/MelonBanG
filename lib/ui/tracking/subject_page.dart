import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/json.dart';
import '../core/page_widgets.dart';
import '../core/subject_posters.dart';
import '../core/theme.dart';
import 'collection_labels.dart';

class SubjectPage extends StatelessWidget {
  const SubjectPage({
    super.key,
    required this.subject,
    required this.onUpdateTracking,
    required this.onFindResources,
    required this.onOpenEpisode,
    required this.onPlayEpisode,
    required this.onOpenSubject,
  });
  final Json? subject;
  final ValueChanged<Json> onUpdateTracking;
  final ValueChanged<Json?> onFindResources;
  final ValueChanged<Json> onOpenEpisode;
  final ValueChanged<Json> onPlayEpisode;
  final ValueChanged<Json> onOpenSubject;
  @override
  Widget build(BuildContext context) {
    final item = subject ?? {};
    final episodes = objects(item['episodes']);
    return PageScroll(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 175,
                  height: 246,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SubjectCover(url: item['coverUrl']),
                  ),
                ),
                const SizedBox(width: 26),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titleOf(item),
                        style: const TextStyle(
                          fontSize: 27,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${item['name'] ?? ''}',
                        style: const TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        '${item['airDate'] ?? ''}   ${item['platform'] ?? ''}   ${item['episodeTotal'] ?? '—'} 话   ★ ${item['score'] ?? '—'}',
                      ),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: collectionLabels.entries
                            .map(
                              (entry) => ChoiceChip(
                                label: Text(entry.value),
                                selected:
                                    object(item['collection'])['status'] ==
                                    entry.key,
                                onSelected: (_) => onUpdateTracking({
                                  'kind': 'subjectCollection',
                                  'subjectId': item['subjectId'],
                                  'status': entry.key,
                                }),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        children: [
                          FilledButton.icon(
                            onPressed: () => onFindResources(null),
                            icon: const Icon(Icons.search),
                            label: const Text('查找资源'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => launchUrl(
                              Uri.parse(
                                'https://bgm.tv/subject/${item['subjectId']}',
                              ),
                              mode: LaunchMode.externalApplication,
                            ),
                            icon: const Icon(Icons.open_in_new),
                            label: const Text('Bangumi'),
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
        SectionTitle(title: '故事简介'),
        SelectableText('${item['summary'] ?? '暂无简介'}'),
        if (objects(item['tags']).isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: objects(item['tags'])
                  .take(16)
                  .map((tag) => Chip(label: Text('${tag['name']}')))
                  .toList(),
            ),
          ),
        SectionTitle(title: '章节 · ${episodes.length}'),
        for (final episode in episodes)
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: episode['status'] == 'watched'
                    ? mint
                    : mint.withValues(alpha: .12),
                child: Text('${episode['sort']}'),
              ),
              title: Text(titleOf(episode)),
              subtitle: Text(episode['status'] == 'watched' ? '已看' : '未看'),
              trailing: Wrap(
                spacing: 4,
                children: [
                  IconButton(
                    tooltip: '标记已看 / 未看',
                    icon: Icon(
                      episode['status'] == 'watched'
                          ? Icons.check_circle
                          : Icons.check_circle_outline,
                    ),
                    onPressed: () => onUpdateTracking({
                      'kind': 'episodeCollection',
                      'subjectId': item['subjectId'],
                      'episodeId': episode['episodeId'],
                      'status': episode['status'] == 'watched'
                          ? 'unwatched'
                          : 'watched',
                    }),
                  ),
                  IconButton(
                    tooltip: '打开本地文件并关联此话',
                    onPressed: () => onOpenEpisode(episode),
                    icon: const Icon(Icons.folder_open),
                  ),
                  IconButton(
                    tooltip: '搜索此话资源',
                    onPressed: () => onFindResources(episode),
                    icon: const Icon(Icons.download_outlined),
                  ),
                  IconButton(
                    tooltip: '播放已缓存视频',
                    onPressed: () => onPlayEpisode(episode),
                    icon: const Icon(Icons.play_arrow),
                  ),
                ],
              ),
            ),
          ),
        if (objects(item['infoBox']).isNotEmpty) ...[
          SectionTitle(title: '作品信息'),
          for (final row in objects(item['infoBox']))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Text('${row['key']}：${row['value']}'),
            ),
        ],
        if (objects(item['relatedSubjects']).isNotEmpty) ...[
          SectionTitle(title: '关联作品'),
          SubjectPosters(
            onOpen: onOpenSubject,
            items: objects(item['relatedSubjects']),
            horizontal: true,
          ),
        ],
      ],
    );
  }
}

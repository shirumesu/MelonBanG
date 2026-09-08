import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/json.dart';
import '../core/page_widgets.dart';
import '../core/subject_posters.dart';
import '../core/theme.dart';
import 'collection_labels.dart';

class SubjectPage extends StatefulWidget {
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
  final ValueChanged<Json> onOpenEpisode, onPlayEpisode, onOpenSubject;
  @override
  State<SubjectPage> createState() => _SubjectPageState();
}

class _SubjectPageState extends State<SubjectPage> {
  late final current = ValueNotifier<Json?>(widget.subject);
  @override
  void didUpdateWidget(covariant SubjectPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The dialog is a separate route, outside this page's build subtree.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) current.value = widget.subject;
    });
  }

  @override
  void dispose() {
    current.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.subject;
    if (item == null) return const Center(child: CircularProgressIndicator());
    final episodes = objects(item['episodes']);
    final watched = episodes.where((e) => e['status'] == 'watched').length;
    final next =
        episodes.where((e) => e['status'] != 'watched').firstOrNull ??
        episodes.firstOrNull;
    return PageScroll(
      children: [
        const SizedBox(height: 10),
        MelonPanel(
          padding: const EdgeInsets.all(26),
          child: LayoutBuilder(
            builder: (context, size) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: size.maxWidth > 1000 ? 230 : 160,
                  child: AspectRatio(
                    aspectRatio: .75,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: .15),
                            blurRadius: 28,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: SubjectCover(
                          url: item['coverUrl'],
                          title: titleOf(item),
                          id: number(item['subjectId']).toInt(),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: size.maxWidth > 1000 ? 56 : 26),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titleOf(item),
                        style: const TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${item['name'] ?? ''}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (item['airDate'] != null)
                            MelonBadge('${item['airDate']}', color: coral),
                          MelonBadge('${item['platform'] ?? '动画'}'),
                          for (final tag in objects(item['tags']).take(4))
                            MelonBadge('${tag['name']}', color: sky),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '已看 EP${watched.toString().padLeft(2, '0')} / 预定全 ${item['episodeTotal'] ?? episodes.length} 话',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 16,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          RichText(
                            text: TextSpan(
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                              children: [
                                TextSpan(
                                  text: scoreLabel(item['score']),
                                  style: const TextStyle(
                                    fontSize: 46,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                TextSpan(
                                  text: ' /10',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (item['rank'] != null)
                            MelonBadge(
                              '#${item['rank']}  Bangumi Rank',
                              color: coral,
                            ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (var i = 0; i < 5; i++)
                                    Icon(
                                      number(item['score']) / 2 >= i + 1
                                          ? Icons.star_rounded
                                          : number(item['score']) / 2 > i
                                          ? Icons.star_half_rounded
                                          : Icons.star_outline_rounded,
                                      size: 18,
                                      color: gold,
                                    ),
                                ],
                              ),
                              if (item['ratingCount'] != null)
                                Text(
                                  '${item['ratingCount']} 人评分',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                      if (object(item['collectionStats']).isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _stats(context, object(item['collectionStats'])),
                      ],
                      const Divider(height: 28),
                      Wrap(
                        spacing: 8,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          FilledButton.icon(
                            onPressed: next == null
                                ? null
                                : () => widget.onPlayEpisode(next),
                            icon: const Icon(
                              Icons.play_arrow_rounded,
                              size: 19,
                            ),
                            label: Text(
                              '继续播放${next == null ? '' : ' EP${next['sort']}'}',
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: episodes.isEmpty ? null : _episodes,
                            icon: const Icon(Icons.playlist_play, size: 18),
                            label: const Text('选集'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => widget.onFindResources(null),
                            icon: const Icon(Icons.download_outlined, size: 18),
                            label: const Text('查找资源'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 5,
                        runSpacing: 5,
                        children: collectionLabels.entries
                            .map(
                              (e) => ChoiceChip(
                                label: Text(e.value),
                                selected:
                                    object(item['collection'])['status'] ==
                                    e.key,
                                onSelected: (_) => widget.onUpdateTracking({
                                  'kind': 'subjectCollection',
                                  'subjectId': item['subjectId'],
                                  'status': e.key,
                                }),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 7),
                      TextButton.icon(
                        onPressed: () => launchUrl(
                          Uri.parse(
                            'https://bgm.tv/subject/${item['subjectId']}',
                          ),
                          mode: LaunchMode.externalApplication,
                        ),
                        icon: const Icon(Icons.open_in_new, size: 14),
                        label: const Text('在 Bangumi 打开'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        MelonPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '简介',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
              SelectableText(
                '${item['summary'] ?? '暂无简介'}',
                style: const TextStyle(fontSize: 13, height: 1.85),
              ),
              if (objects(item['characters']).isNotEmpty) ...[
                const Divider(height: 36),
                const Text(
                  '主要角色',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final person in objects(item['characters']).take(8))
                      _credit(context, person),
                  ],
                ),
              ],
              if (objects(item['staff']).isNotEmpty) ...[
                const Divider(height: 36),
                const Text(
                  '制作团队',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final person in objects(item['staff']).take(8))
                      _credit(context, person),
                  ],
                ),
              ],
              if (objects(item['infoBox']).isNotEmpty) ...[
                const Divider(height: 36),
                const Text(
                  '作品信息',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                for (final row in objects(item['infoBox']))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Text(
                      '${row['key']}：${row['value']}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
              ],
            ],
          ),
        ),
        if (objects(item['relatedSubjects']).isNotEmpty) ...[
          const SectionTitle(title: '关联作品', icon: Icons.movie_filter_outlined),
          SubjectPosters(
            onOpen: widget.onOpenSubject,
            items: objects(item['relatedSubjects']),
            horizontal: true,
          ),
        ],
      ],
    );
  }

  Widget _credit(BuildContext context, Json person) => Container(
    width: 145,
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titleOf(person),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        ),
        const SizedBox(height: 6),
        Text(
          '${person['role'] ?? person['relation'] ?? ''}',
          maxLines: 2,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
      ],
    ),
  );
  Widget _stats(BuildContext context, Json stats) {
    final total = collectionLabels.keys.fold<double>(
      0,
      (sum, key) => sum + number(stats[key]),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (total > 0)
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 7,
              child: Row(
                children: [
                  for (final key in collectionLabels.keys)
                    if (number(stats[key]) > 0)
                      Expanded(
                        flex: (number(stats[key]) * 1000).round(),
                        child: ColoredBox(
                          color: collectionColor(key),
                          child: const SizedBox.expand(),
                        ),
                      ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 14,
          runSpacing: 5,
          children: [
            for (final entry in collectionLabels.entries)
              Text(
                '${number(stats[entry.key]).toInt()} ${entry.value}',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _episodes() => showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: SizedBox(
        width: 780,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ValueListenableBuilder<Json?>(
            valueListenable: current,
            builder: (context, item, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '选集 · ${titleOf(item ?? {})}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭选集',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final ep in objects(item?['episodes']))
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 5,
                          ),
                          leading: CircleAvatar(
                            backgroundColor: ep['status'] == 'watched'
                                ? mint
                                : Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerLow,
                            foregroundColor: ep['status'] == 'watched'
                                ? Colors.white
                                : null,
                            child: Text(
                              '${ep['sort']}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          title: Text(
                            titleOf(ep),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            ep['status'] == 'watched' ? '已看' : '未看',
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: '标记已看 / 未看',
                                icon: Icon(
                                  ep['status'] == 'watched'
                                      ? Icons.check_circle
                                      : Icons.check_circle_outline,
                                  color: mint,
                                ),
                                onPressed: () => widget.onUpdateTracking({
                                  'kind': 'episodeCollection',
                                  'subjectId': item?['subjectId'],
                                  'episodeId': ep['episodeId'],
                                  'status': ep['status'] == 'watched'
                                      ? 'unwatched'
                                      : 'watched',
                                }),
                              ),
                              IconButton(
                                tooltip: '打开本地文件并关联此话',
                                onPressed: () {
                                  Navigator.pop(context);
                                  widget.onOpenEpisode(ep);
                                },
                                icon: const Icon(Icons.folder_open, size: 19),
                              ),
                              IconButton(
                                tooltip: '搜索此话资源',
                                onPressed: () {
                                  Navigator.pop(context);
                                  widget.onFindResources(ep);
                                },
                                icon: const Icon(
                                  Icons.download_outlined,
                                  size: 19,
                                ),
                              ),
                              IconButton(
                                tooltip: '播放已缓存视频',
                                onPressed: () {
                                  Navigator.pop(context);
                                  widget.onPlayEpisode(ep);
                                },
                                icon: const Icon(Icons.play_arrow, size: 20),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

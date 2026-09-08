import 'package:flutter/material.dart';

import '../../data/json.dart';
import '../tracking/collection_labels.dart';
import 'page_widgets.dart';
import 'theme.dart';

const _artColors = [
  [Color(0xff7bd0c1), Color(0xff3b82c4)],
  [Color(0xfff7a8b8), Color(0xff9b6ad8)],
  [Color(0xffffd56b), Color(0xffff7a5b)],
  [Color(0xff9be7c4), Color(0xff3aa17e)],
  [Color(0xffa9c7ff), Color(0xff6a6ae0)],
  [Color(0xffffb3c7), Color(0xffff6b9d)],
  [Color(0xffc0a8ff), Color(0xff7d5fe0)],
  [Color(0xff8fe3d6), Color(0xff3aa1a8)],
];

class SubjectPosters extends StatelessWidget {
  const SubjectPosters({
    super.key,
    required this.items,
    required this.onOpen,
    this.horizontal = false,
    this.ranked = false,
    this.tracking = false,
  });
  final List<Json> items;
  final ValueChanged<Json> onOpen;
  final bool horizontal, ranked, tracking;
  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const EmptyState(text: '这里还没有番剧');
    Widget poster(int i) => _SubjectPoster(
      onOpen: onOpen,
      item: items[i],
      rank: ranked ? i + 1 : null,
      tracking: tracking,
    );
    if (horizontal) {
      return SizedBox(
        height: ranked ? 330 : 292,
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(2, 3, 2, 10),
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 16),
          itemBuilder: (_, i) =>
              SizedBox(width: ranked ? 180 : 188, child: poster(i)),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) => GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: (constraints.maxWidth / 184).floor().clamp(1, 8),
          crossAxisSpacing: 16,
          mainAxisSpacing: 20,
          childAspectRatio: .65,
        ),
        itemBuilder: (_, i) => poster(i),
      ),
    );
  }
}

class _SubjectPoster extends StatelessWidget {
  const _SubjectPoster({
    required this.item,
    required this.onOpen,
    this.rank,
    required this.tracking,
  });
  final Json item;
  final ValueChanged<Json> onOpen;
  final int? rank;
  final bool tracking;
  @override
  Widget build(BuildContext context) {
    final status =
        '${item['status'] ?? object(item['collection'])['status'] ?? ''}';
    return InkWell(
      onTap: () => onOpen(item),
      borderRadius: BorderRadius.circular(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .10),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    SubjectCover(
                      url: item['coverUrl'],
                      title: titleOf(item),
                      id: number(item['subjectId']).toInt(),
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: [.4, 1],
                          colors: [Colors.transparent, Color(0xcc000000)],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 11,
                      right: 10,
                      bottom: 12,
                      child: Text(
                        titleOf(item),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.3,
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (rank != null)
                      Positioned(
                        top: 9,
                        left: 9,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(99),
                            gradient: rank! <= 3
                                ? const LinearGradient(
                                    colors: [Color(0xffffcf6b), coral],
                                  )
                                : null,
                            color: rank! > 3 ? Colors.black38 : null,
                          ),
                          child: Text(
                            '#$rank',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    if (tracking && collectionLabels.containsKey(status))
                      Positioned(
                        top: 10,
                        left: 10,
                        child: Material(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(99),
                          child: MelonBadge(
                            collectionLabels[status]!,
                            color: collectionColor(status),
                          ),
                        ),
                      ),
                    if (tracking && item['episodeTotal'] != null)
                      Positioned(
                        top: 10,
                        right: 9,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black38,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            '全 ${item['episodeTotal']} 话',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (rank != null) ...[
            SizedBox(
              height: 54,
              child: Wrap(
                spacing: 5,
                runSpacing: 4,
                children: [
                  if (object(item['season'])['label'] != null)
                    MelonBadge(
                      '${object(item['season'])['label']}',
                      color: coral,
                    ),
                  MelonBadge('${item['platform'] ?? 'TV'}', color: sky),
                  if (item['episodeTotal'] != null)
                    MelonBadge('全${item['episodeTotal']}话', color: sky),
                ],
              ),
            ),
            const SizedBox(height: 6),
          ],
          Row(
            children: [
              Text(
                '★ ${scoreLabel(item['score'])}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: rank != null
                      ? gold
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              if (tracking)
                Text(
                  item['watchedEpisodes'] == null
                      ? '未记录进度'
                      : '看到 EP${item['watchedEpisodes']}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                )
              else if (rank == null)
                Text(
                  item['episodeTotal'] == null
                      ? '${item['platform'] ?? '动画'}'
                      : '全 ${item['episodeTotal']} 话',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

String scoreLabel(Object? value) =>
    value is num && value > 0 ? value.toStringAsFixed(1) : '—';
Color collectionColor(String status) => switch (status) {
  'wish' => sky,
  'on_hold' => gold,
  'completed' => grape,
  'dropped' => coral,
  _ => mint,
};

class SubjectCover extends StatelessWidget {
  const SubjectCover({
    super.key,
    required this.url,
    this.title = '',
    this.id = 0,
  });
  final Object? url;
  final String title;
  final int id;
  @override
  Widget build(BuildContext context) {
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _artColors[id.abs() % _artColors.length],
        ),
      ),
      child: Center(
        child: title.isEmpty
            ? const Icon(Icons.movie_outlined, color: Colors.white54, size: 36)
            : Text(
                title.characters.first,
                style: const TextStyle(
                  fontSize: 56,
                  color: Colors.white30,
                  fontWeight: FontWeight.w900,
                ),
              ),
      ),
    );
    return switch (url) {
      final String address when address.startsWith('http') => Image.network(
        address,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
      _ => fallback,
    };
  }
}

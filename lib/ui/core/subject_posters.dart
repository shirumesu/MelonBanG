import 'package:flutter/material.dart';

import '../../data/json.dart';
import 'page_widgets.dart';
import 'theme.dart';

class SubjectPosters extends StatelessWidget {
  const SubjectPosters({
    super.key,
    required this.items,
    required this.onOpen,
    this.horizontal = false,
  });
  final List<Json> items;
  final ValueChanged<Json> onOpen;
  final bool horizontal;
  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const EmptyState(text: '这里还没有番剧');
    if (horizontal) {
      return SizedBox(
        height: 252,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 16),
          itemBuilder: (_, i) => SizedBox(
            width: 145,
            child: _SubjectPoster(onOpen: onOpen, item: items[i]),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) => GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: (constraints.maxWidth / 170).floor().clamp(2, 8),
          crossAxisSpacing: 18,
          mainAxisSpacing: 18,
          childAspectRatio: .61,
        ),
        itemBuilder: (_, index) =>
            _SubjectPoster(onOpen: onOpen, item: items[index]),
      ),
    );
  }
}

class _SubjectPoster extends StatelessWidget {
  const _SubjectPoster({required this.item, required this.onOpen});
  final Json item;
  final ValueChanged<Json> onOpen;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => onOpen(item),
    borderRadius: BorderRadius.circular(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SubjectCover(url: item['coverUrl']),
                ),
              ),
              if (item['score'] != null)
                Positioned(
                  right: 7,
                  bottom: 7,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .7),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      '★ ${item['score']}',
                      style: const TextStyle(
                        color: Color(0xffffcf6b),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          titleOf(item),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 3),
        Text(
          item['episodeTotal'] == null
              ? '${item['platform'] ?? '动画'}'
              : '全 ${item['episodeTotal']} 话',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    ),
  );
}

class SubjectCover extends StatelessWidget {
  const SubjectCover({super.key, required this.url});
  final Object? url;
  @override
  Widget build(BuildContext context) => switch (url) {
    final String address when address.startsWith('http') => Image.network(
      address,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => const SubjectCover(url: null),
    ),
    _ => Container(
      color: mint.withValues(alpha: .12),
      child: const Center(
        child: Icon(Icons.movie_outlined, color: mint, size: 36),
      ),
    ),
  };
}

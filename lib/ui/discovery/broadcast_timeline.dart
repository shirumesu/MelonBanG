import 'package:flutter/material.dart';

import '../../domain/catalog.dart';
import '../../domain/episode_release.dart';
import '../core/motion.dart';
import '../core/page_widgets.dart';
import '../core/subject_cover.dart';
import '../core/theme.dart';

/// A day's shows by air time; those aired are marked 已更新 and those in
/// the collection being watched 在追, as on the home timeline.
class BroadcastTimeline extends StatelessWidget {
  const BroadcastTimeline({
    super.key,
    required this.items,
    required this.onOpen,
    this.watchingIds = const {},
  });
  final List<Subject> items;
  final ValueChanged<Subject> onOpen;
  final Set<int> watchingIds;
  @override
  Widget build(BuildContext context) => ShownClock(
    period: const Duration(minutes: 1),
    builder: (context) {
      final now = DateTime.now();
      return Column(
        children: [
          for (var i = 0; i < items.length; i++)
            _BroadcastEntry(
              key: ValueKey('${items[i].id}:$i'),
              item: items[i],
              onOpen: onOpen,
              first: i == 0,
              last: i == items.length - 1,
              aired: items[i].airingAt?.isBefore(now) ?? false,
              watching: watchingIds.contains(items[i].id),
            ),
        ],
      );
    },
  );
}

/// [BroadcastTimeline] entries in grey while the schedule loads, once the
/// wait has lasted [busyDelay].
class BroadcastTimelineSkeleton extends StatelessWidget {
  const BroadcastTimelineSkeleton({super.key});

  static const _shares = [.55, .4, .7, .5];

  @override
  Widget build(BuildContext context) => DelayedBusy(
    busy: true,
    builder: (context, shown) => !shown
        ? const SizedBox.shrink()
        : SkeletonGroup(label: '正在加载时间表', child: _entries(context)),
  );

  Widget _entries(BuildContext context) {
    final line = Theme.of(context).colorScheme.outlineVariant;
    return Column(
      children: [
        for (final (i, share) in _shares.indexed)
          Stack(
            children: [
              Positioned(
                left: 64.5,
                top: i == 0 ? 70 : 0,
                bottom: i == _shares.length - 1 ? 82 : 0,
                child: Container(width: 2, color: line),
              ),
              Positioned(
                left: 66,
                top: 69.5,
                width: 17,
                height: 1,
                child: ColoredBox(color: line),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.md),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 48,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SkeletonBlock(width: 32, height: 10),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: Gap.md),
                      child: SkeletonBlock(
                        width: 11,
                        height: 11,
                        radius: pillBorderRadius,
                      ),
                    ),
                    Expanded(
                      child: MelonPanel(
                        padding: const EdgeInsets.all(Gap.lg),
                        child: Row(
                          children: [
                            const SkeletonBlock(
                              width: 80,
                              height: 108,
                              radius: posterBorderRadius,
                            ),
                            const SizedBox(width: Gap.lg),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  FractionallySizedBox(
                                    widthFactor: share,
                                    child: const SkeletonBlock(height: 12),
                                  ),
                                  const SizedBox(height: Gap.md),
                                  const SkeletonBlock(width: 64, height: 9),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _BroadcastEntry extends StatefulWidget {
  const _BroadcastEntry({
    super.key,
    required this.item,
    required this.onOpen,
    required this.first,
    required this.last,
    required this.aired,
    required this.watching,
  });
  final Subject item;
  final ValueChanged<Subject> onOpen;
  final bool first, last, aired, watching;
  @override
  State<_BroadcastEntry> createState() => _BroadcastEntryState();
}

class _BroadcastEntryState extends State<_BroadcastEntry> {
  bool hovered = false, focused = false;
  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final active = hovered || focused;
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: Focus(
        canRequestFocus: false,
        onFocusChange: (value) => setState(() => focused = value),
        child: Stack(
          children: [
            Positioned(
              left: 64.5,
              top: widget.first ? 70 : 0,
              bottom: widget.last ? 82 : 0,
              child: AnimatedContainer(
                width: 2,
                duration: motionDuration(context, 200),
                color: active
                    ? scheme.primary.withValues(alpha: .4)
                    : scheme.outlineVariant,
              ),
            ),
            Positioned(
              left: 66,
              top: 69.5,
              width: 17,
              height: 1,
              child: ColoredBox(
                color: active
                    ? scheme.primary.withValues(alpha: .4)
                    : scheme.outlineVariant,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.md),
              child: Row(
                children: [
                  SizedBox(
                    width: 48,
                    child: Text(
                      _time(item),
                      style: TextStyle(
                        fontSize: FontSize.small,
                        fontWeight: FontWeight.w400,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  AnimatedContainer(
                    duration: motionDuration(context, 200),
                    width: 11,
                    height: 11,
                    margin: const EdgeInsets.symmetric(horizontal: Gap.md),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                      boxShadow: active
                          ? [
                              BoxShadow(
                                color: Theme.of(context).colorScheme.primary
                                    .withValues(alpha: .14),
                                spreadRadius: 4,
                              ),
                            ]
                          : null,
                    ),
                  ),
                  Expanded(
                    child: AnimatedContainer(
                      duration: motionDuration(context, 200),
                      curve: Curves.easeOut,
                      transform: Matrix4.translationValues(
                        active && !MediaQuery.disableAnimationsOf(context)
                            ? 2
                            : 0,
                        active && !MediaQuery.disableAnimationsOf(context)
                            ? -2
                            : 0,
                        0,
                      ),
                      child: MelonPanel(
                        onTap: () => widget.onOpen(item),
                        padding: const EdgeInsets.all(Gap.lg),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 80,
                              height: 108,
                              child: CoverFrame(
                                child: SubjectCover(
                                  url: item.coverUrl,
                                  title: item.title,
                                  id: item.id,
                                ),
                              ),
                            ),
                            const SizedBox(width: Gap.lg),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: FontSize.emphasis,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (item.episodeTotal != null ||
                                      widget.aired) ...[
                                    const SizedBox(height: Gap.sm),
                                    Row(
                                      children: [
                                        if (item.episodeTotal != null)
                                          Text(
                                            '全 ${item.episodeTotal} 话',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          ),
                                        if (item.episodeTotal != null &&
                                            widget.aired)
                                          const SizedBox(width: Gap.sm),
                                        if (widget.aired)
                                          Text(
                                            '已更新',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w400,
                                                  color: scheme.primary,
                                                ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (widget.watching)
                              const Padding(
                                padding: EdgeInsets.only(left: Gap.sm),
                                child: MelonBadge('在追'),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _time(Subject item) {
    final instant = item.airingAt;
    return instant == null ? '放送' : shanghaiClock(instant);
  }
}

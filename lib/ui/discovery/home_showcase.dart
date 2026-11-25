import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../domain/catalog.dart';
import '../core/motion.dart';
import '../core/page_widgets.dart';
import '../core/subject_cover.dart';
import '../core/subject_posters.dart';
import '../core/theme.dart';

const showcaseHeight = 328.0;

/// The spotlight and ranking in grey while 本季热度 loads.
class ShowcaseSkeleton extends StatelessWidget {
  const ShowcaseSkeleton({super.key, required this.wide});
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final spotlight = MelonPanel(
      padding: const EdgeInsets.all(Gap.xl),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AspectRatio(
            aspectRatio: .72,
            child: SkeletonBlock(radius: posterBorderRadius),
          ),
          const SizedBox(width: Gap.xl),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SkeletonBlock(width: 28, height: 14),
                  const SizedBox(height: Gap.md),
                  SkeletonBlock(width: constraints.maxWidth * .6, height: 28),
                  const SizedBox(height: Gap.sm),
                  SkeletonBlock(width: constraints.maxWidth * .35, height: 14),
                  const SizedBox(height: Gap.lg),
                  SkeletonBlock(width: constraints.maxWidth * .7, height: 24),
                  const SizedBox(height: Gap.lg),
                  for (final share in const [.95, .9, .6]) ...[
                    SkeletonBlock(
                      width: constraints.maxWidth * share,
                      height: 13,
                    ),
                    const SizedBox(height: Gap.sm),
                  ],
                  const Spacer(),
                  const SkeletonBlock(
                    width: 92,
                    height: 32,
                    radius: controlBorderRadius,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    return SkeletonGroup(
      label: '正在加载本季热度',
      child: SizedBox(
        height: showcaseHeight,
        child: !wide
            ? spotlight
            : Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: spotlight),
                  const SizedBox(width: Gap.lg),
                  SizedBox(
                    width: homeSideColumnWidth,
                    child: MelonPanel(
                      padding: const EdgeInsets.all(Gap.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const SkeletonBlock(width: 72, height: 16),
                          for (var i = 0; i < 8; i++)
                            FractionallySizedBox(
                              widthFactor: .92 - (i * 7 % 30) / 100,
                              child: const SkeletonBlock(height: 14),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class TrendingShowcase extends StatefulWidget {
  const TrendingShowcase({
    super.key,
    required this.items,
    required this.wide,
    required this.onOpen,
  });
  final List<Subject> items;
  final bool wide;
  final ValueChanged<Subject> onOpen;

  @override
  State<TrendingShowcase> createState() => _TrendingShowcaseState();
}

class _TrendingShowcaseState extends State<TrendingShowcase> {
  int index = 0;

  /// Which way the last change moved, so the next title enters from there.
  int direction = 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    index = PageStorage.maybeOf(context)?.readState(context) as int? ?? index;
  }

  void select(int value) {
    final current = index.clamp(0, widget.items.length - 1);
    if (value == current) return;
    setState(() {
      direction = value > current ? 1 : -1;
      index = value % widget.items.length;
    });
    PageStorage.maybeOf(context)?.writeState(context, index);
  }

  @override
  Widget build(BuildContext context) {
    final current = index.clamp(0, widget.items.length - 1);
    final spotlight = _Spotlight(
      item: widget.items[current],
      direction: direction,
      rank: current + 1,
      onOpen: widget.onOpen,
      onPrevious: () => select(current - 1),
      onNext: () => select(current + 1),
    );
    if (!widget.wide) {
      return SizedBox(height: showcaseHeight, child: spotlight);
    }
    return SizedBox(
      height: showcaseHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: spotlight),
          const SizedBox(width: Gap.lg),
          SizedBox(
            width: homeSideColumnWidth,
            child: _RankList(
              items: widget.items,
              selected: current,
              onSelect: select,
            ),
          ),
        ],
      ),
    );
  }
}

class _Spotlight extends StatelessWidget {
  const _Spotlight({
    required this.item,
    required this.direction,
    required this.rank,
    required this.onOpen,
    required this.onPrevious,
    required this.onNext,
  });
  final Subject item;

  /// 1 when moving down the ranking, -1 when moving back up.
  final int direction;
  final int rank;
  final ValueChanged<Subject> onOpen;
  final VoidCallback onPrevious, onNext;

  @override
  Widget build(BuildContext context) {
    final id = item.id;
    final title = item.title;
    final original = item.name ?? '';
    final summary = (item.summary ?? '').replaceAll(RegExp(r'\s+'), ' ');
    final tags = <String>[
      ?item.season?.label,
      ?item.platform,
      if (item.episodeTotal != null) '全 ${item.episodeTotal} 话',
      ...item.metaTags.where((tag) => tag != item.platform && tag != '日本'),
    ].take(5);
    const white = Colors.white;
    final muted = white.withValues(alpha: .72);
    return ClipRRect(
      borderRadius: panelBorderRadius,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0xff1d2a30)),
          // A tiny decode stretched over the panel is already soft, so a
          // light blur finishes it; the old and new backdrops cross-fade
          // under one blur.
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Transform.scale(
              scale: 1.4,
              child: AnimatedSwitcher(
                duration: motionDuration(context, 400),
                layoutBuilder: (current, previous) => Stack(
                  fit: StackFit.expand,
                  children: [...previous, ?current],
                ),
                child: FittedBox(
                  key: ValueKey(id),
                  fit: BoxFit.cover,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(
                    width: 36,
                    height: 50,
                    child: SubjectCover(
                      url: item.coverUrl,
                      title: title,
                      id: id,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xb3101a1e), Color(0x80101a1e)],
              ),
            ),
          ),
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: () => onOpen(item),
              child: Padding(
                padding: const EdgeInsets.all(Gap.xl),
                child: AnimatedSwitcher(
                  duration: motionDuration(context, 320),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  // The new title slides in from the side it came from while
                  // the old one leaves the other way.
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: animation.drive(
                        Tween(
                          begin: Offset(
                            (child.key == ValueKey(id) ? .04 : -.04) *
                                direction,
                            0,
                          ),
                          end: Offset.zero,
                        ),
                      ),
                      child: child,
                    ),
                  ),
                  child: Row(
                    key: ValueKey(id),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AspectRatio(
                        aspectRatio: .72,
                        child: DecoratedBox(
                          decoration: const BoxDecoration(
                            borderRadius: posterBorderRadius,
                            boxShadow: [
                              BoxShadow(
                                color: Color(0x66000000),
                                blurRadius: 2,
                                offset: Offset(0, 1),
                              ),
                              BoxShadow(
                                color: Color(0x59000000),
                                blurRadius: 24,
                                offset: Offset(0, 10),
                              ),
                            ],
                          ),
                          child: CoverFrame(
                            child: SubjectCover(
                              url: item.coverUrl,
                              title: title,
                              id: id,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: Gap.xl),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '#$rank',
                              style: TextStyle(
                                color: rank <= 3 ? gold : muted,
                                fontSize: FontSize.body,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                            const SizedBox(height: Gap.sm),
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: white,
                                fontSize: FontSize.headline,
                                height: 1.25,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (original.isNotEmpty && original != title)
                              Text(
                                original,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: muted,
                                  fontSize: FontSize.small,
                                ),
                              ),
                            const SizedBox(height: Gap.lg),
                            Wrap(
                              spacing: Gap.sm,
                              runSpacing: Gap.sm,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  '★ ${scoreLabel(item.score)}',
                                  style: const TextStyle(
                                    color: gold,
                                    fontSize: FontSize.title,
                                    fontFeatures: [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                                for (final tag in tags)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: Gap.sm,
                                      vertical: Gap.xs,
                                    ),
                                    decoration: BoxDecoration(
                                      color: white.withValues(alpha: .14),
                                      borderRadius: badgeBorderRadius,
                                    ),
                                    child: Text(
                                      tag,
                                      style: const TextStyle(
                                        color: white,
                                        fontSize: FontSize.small,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: Gap.lg),
                            Expanded(
                              child: ClipRect(
                                child: Align(
                                  alignment: Alignment.topLeft,
                                  child: Text(
                                    summary,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: muted,
                                      fontSize: FontSize.body,
                                      height: 1.6,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Row(
                              children: [
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: white,
                                    // The button stays white in both themes,
                                    // so its text takes the accent's ink
                                    // from the light theme.
                                    foregroundColor: appTheme(
                                      false,
                                      accent: accentOf(context).accent,
                                    ).colorScheme.onPrimaryContainer,
                                  ),
                                  onPressed: () => onOpen(item),
                                  child: const Text('查看详情'),
                                ),
                                const Spacer(),
                                for (final (icon, tooltip, action) in [
                                  (Icons.chevron_left, '上一部', onPrevious),
                                  (Icons.chevron_right, '下一部', onNext),
                                ])
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      left: Gap.sm,
                                    ),
                                    child: IconButton(
                                      tooltip: tooltip,
                                      onPressed: action,
                                      style: IconButton.styleFrom(
                                        backgroundColor: white.withValues(
                                          alpha: .16,
                                        ),
                                        foregroundColor: white,
                                        hoverColor: white.withValues(
                                          alpha: .12,
                                        ),
                                      ),
                                      icon: Icon(icon),
                                    ),
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
            ),
          ),
        ],
      ),
    );
  }
}

class _RankList extends StatelessWidget {
  const _RankList({
    required this.items,
    required this.selected,
    required this.onSelect,
  });
  final List<Subject> items;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MelonPanel(
      padding: const EdgeInsets.all(Gap.sm),
      child: MotionSelection<int>(
        selected: selected,
        highlight: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: .35),
            borderRadius: insetRadius(panelBorderRadius, Gap.sm),
          ),
        ),
        builder: (context, keyOf) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.sm, Gap.xs, 0, Gap.sm),
              child: Row(
                children: [
                  Icon(
                    Icons.local_fire_department_outlined,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: Gap.sm),
                  Text('本季热度', style: Theme.of(context).textTheme.titleSmall),
                ],
              ),
            ),
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: Material(
                  key: keyOf(i),
                  color: Colors.transparent,
                  borderRadius: insetRadius(panelBorderRadius, Gap.sm),
                  child: InkWell(
                    borderRadius: insetRadius(panelBorderRadius, Gap.sm),
                    onTap: () => onSelect(i),
                    child: Semantics(
                      selected: i == selected,
                      button: true,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 24,
                              child: Text(
                                '${i + 1}',
                                style: TextStyle(
                                  fontSize: FontSize.body,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                  color: i < 3
                                      ? badgeInk(
                                          gold,
                                          Theme.of(context).brightness ==
                                              Brightness.dark,
                                        )
                                      : scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                items[i].title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: FontSize.body),
                              ),
                            ),
                            const SizedBox(width: Gap.sm),
                            Text(
                              '★ ${scoreLabel(items[i].score)}',
                              style: TextStyle(
                                fontSize: FontSize.small,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                                color: scheme.tertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

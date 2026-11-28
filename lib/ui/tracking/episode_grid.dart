import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/notices.dart';
import '../../domain/catalog.dart';
import '../core/help_hint.dart';
import '../core/motion.dart';
import '../core/page_widgets.dart';
import '../core/selection_controls.dart';
import '../core/theme.dart';
import '../core/tone.dart';

/// All episodes as numbered cells, the specials on rows of their own after
/// the main episodes, behind an SP label; past 100 main episodes, fifty at
/// a time with the specials on a page of their own. A click plays the
/// episode's cache or opens its resources, a right-click offers more and a
/// long press marks; still pressed, dragging selects the range from the
/// pressed cell to the pointer. Releasing well outside the cells, the right
/// button or Escape cancels the mark.
class EpisodeGrid extends StatefulWidget {
  const EpisodeGrid({
    super.key,
    required this.episodes,
    required this.nextId,
    required this.statusOf,
    required this.aired,
    required this.cached,
    required this.onSelect,
    required this.onOpen,
    required this.onPlay,
    required this.onMark,
    required this.onHover,
  });
  final List<Episode> episodes;

  /// The episode the collapsed grid keeps in view.
  final int? nextId;

  final EpisodeStatus Function(Episode) statusOf;
  final bool Function(Episode) aired;

  /// Whether the episode has a playable cache, shown as a primary outline.
  final bool Function(Episode) cached;
  final ValueChanged<Episode> onSelect, onOpen, onPlay;
  final void Function(List<Episode> episodes, EpisodeStatus status) onMark;
  final ValueChanged<Episode?> onHover;

  @override
  State<EpisodeGrid> createState() => _EpisodeGridState();
}

class _EpisodeGridState extends State<EpisodeGrid> {
  static const _gap = 8.0, _minWidth = 40.0, _height = 32.0, _rows = 4;
  static const _cancelMargin = 48.0;

  /// Main episodes past which the grid pages, and how many a page holds:
  /// a year-round show's thousand episodes would fill screens.
  static const _pagedFrom = 100, _pageSize = 50;
  bool expanded = false;

  /// The page chosen; until then the one holding [EpisodeGrid.nextId].
  int? page;

  /// The cell under the pointer. Its outline is drawn over the cells, so
  /// moving between them rebuilds none.
  final hovered = ValueNotifier<int?>(null);

  /// Pending mark while a long press is held: the range between the pressed
  /// and the current episode, by id so it survives data refreshes.
  EpisodeStatus? dragStatus;
  int? anchorId, currentId;
  bool outside = false;

  /// Main episodes in order, then the specials by number as Bangumi lists
  /// them.
  late List<Episode> ordered = _order();

  List<Episode> _order() => [
    for (final episode in widget.episodes)
      if (episode.main) episode,
    ...widget.episodes.where((e) => !e.main).toList()
      ..sort((a, b) => a.sort.compareTo(b.sort)),
  ];

  @override
  void didUpdateWidget(covariant EpisodeGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.episodes, widget.episodes)) ordered = _order();
  }

  Set<int> get dragIds {
    if (dragStatus == null) return const {};
    final ids = [for (final episode in ordered) episode.id];
    final a = ids.indexOf(anchorId!), b = ids.indexOf(currentId!);
    if (a < 0 || b < 0) return const {};
    return ids.sublist(math.min(a, b), math.max(a, b) + 1).toSet();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    hovered.dispose();
    super.dispose();
  }

  void _turn(int value) {
    hovered.value = null;
    setState(() => page = value);
  }

  /// The page holding the next episode to watch, else the latest aired.
  int _autoPage(List<Episode> episodes, int main, int pages) {
    final next = episodes.indexWhere((e) => e.id == widget.nextId);
    if (next >= 0) return next < main ? next ~/ _pageSize : pages - 1;
    final aired = episodes.take(main).toList().lastIndexWhere(widget.aired);
    return aired < 0 ? 0 : aired ~/ _pageSize;
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _cancel();
      return true;
    }
    return false;
  }

  void _start(Episode episode) {
    HardwareKeyboard.instance.addHandler(_onKey);
    setState(() {
      dragStatus = widget.statusOf(episode) == EpisodeStatus.watched
          ? EpisodeStatus.unwatched
          : EpisodeStatus.watched;
      outside = false;
      anchorId = currentId = episode.id;
    });
  }

  void _cancel() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    if (dragStatus == null) return;
    setState(() {
      dragStatus = null;
    });
  }

  void _end() {
    final status = dragStatus;
    final commit = status != null && !outside;
    final dragIds = this.dragIds;
    final episodes = [
      for (final episode in ordered)
        if (dragIds.contains(episode.id) && widget.statusOf(episode) != status)
          episode,
    ];
    _cancel();
    if (commit && episodes.isNotEmpty) widget.onMark(episodes, status);
  }

  Future<void> _menu(Offset position, Episode episode) async {
    final watched = widget.statusOf(episode) == EpisodeStatus.watched;
    final action = await showMenu<String>(
      context: context,
      color: menuSurface(context),
      popUpAnimationStyle: AnimationStyle(
        duration: motionDuration(context, 150),
        reverseDuration: motionDuration(context, 100),
        curve: Curves.easeOutCubic,
      ),
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        const PopupMenuItem(value: 'play', child: Text('观看')),
        const PopupMenuItem(value: 'resources', child: Text('查找资源')),
        PopupMenuItem(value: 'mark', child: Text(watched ? '标为未看' : '标为已看')),
      ],
    );
    switch (action) {
      case 'play':
        widget.onPlay(episode);
      case 'resources':
        widget.onOpen(episode);
      case 'mark':
        widget.onMark([
          episode,
        ], watched ? EpisodeStatus.unwatched : EpisodeStatus.watched);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = math.max(
          1,
          ((constraints.maxWidth + _gap) / (_minWidth + _gap)).floor(),
        );
        final width =
            (constraints.maxWidth - _gap * (columns - 1)) / columns - .01;
        final episodes = ordered;
        final main = episodes.where((e) => e.main).length;
        final specials = episodes.length - main;
        final paged = main > _pagedFrom;
        final pages = [
          if (paged) ...[
            for (var i = 0; i < main; i += _pageSize)
              episodes.sublist(i, math.min(main, i + _pageSize)),
            if (specials > 0) episodes.sublist(main),
          ],
        ];
        final current = paged
            ? (page ?? _autoPage(episodes, main, pages.length)).clamp(
                0,
                pages.length - 1,
              )
            : 0;
        // Cells by position: the specials start a row after the main
        // episodes, behind the SP label at [label]; other gaps are null.
        // Paged, each page holds one kind.
        final slots = <Episode?>[
          if (paged)
            ...pages[current]
          else ...[
            ...episodes.take(main),
            if (specials > 0) ...[
              ...List.filled((columns - main % columns) % columns, null),
              null,
              ...episodes.skip(main),
            ],
          ],
        ];
        final label = specials > 0 && !paged ? slots.length - specials - 1 : -1;
        final rows = (slots.length / columns).ceil();
        final collapsible = !paged && rows > _rows;
        var first = 0, count = slots.length;
        if (collapsible && !expanded) {
          final next = slots.indexWhere((e) => e?.id == widget.nextId);
          final row = ((next < 0 ? 0 : next) ~/ columns - 1).clamp(
            0,
            rows - _rows,
          );
          first = row * columns;
          count = math.min(slots.length - first, _rows * columns);
        }
        final visible = slots.sublist(first, first + count);
        final visibleRows = (visible.length / columns).ceil();
        final gridHeight = visibleRows * (_height + _gap) - _gap;
        int? indexAt(Offset position) {
          if (position.dx < 0 || position.dy < 0) return null;
          final column = (position.dx / (width + _gap)).floor();
          final row = (position.dy / (_height + _gap)).floor();
          if (column >= columns) return null;
          final index = row * columns + column;
          return index < visible.length && visible[index] != null
              ? index
              : null;
        }

        final selected = dragIds;
        void drag(Offset position) {
          if (dragStatus == null) return;
          final away =
              position.dx < -_cancelMargin ||
              position.dy < -_cancelMargin ||
              position.dx > constraints.maxWidth + _cancelMargin ||
              position.dy > gridHeight + _cancelMargin;
          final index = indexAt(position);
          final id = index == null || away ? currentId : visible[index]!.id;
          if (away == outside && id == currentId) return;
          setState(() {
            outside = away;
            currentId = id;
          });
        }

        Widget cell(int index) {
          final episode = visible[index];
          if (episode == null) {
            return SizedBox(
              width: width,
              height: _height,
              child: first + index != label
                  ? null
                  : Tooltip(
                      message: specialsHelp,
                      child: Center(
                        child: Text(
                          'SP',
                          style: TextStyle(
                            fontSize: FontSize.small,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
            );
          }
          final status = selected.contains(episode.id)
              ? dragStatus!
              : widget.statusOf(episode);
          final watched = status == EpisodeStatus.watched;
          final aired = widget.aired(episode);
          final cached = widget.cached(episode);
          final (background, foreground, outline) = watched
              ? (
                  scheme.primaryContainer,
                  scheme.onPrimaryContainer,
                  scheme.primaryContainer,
                )
              : aired
              ? (
                  Colors.transparent,
                  scheme.onSurfaceVariant,
                  scheme.outlineVariant,
                )
              : (
                  scheme.surfaceContainerHigh,
                  scheme.onSurfaceVariant.withValues(alpha: .45),
                  scheme.surfaceContainerHigh,
                );
          final border = cached
              ? scheme.primary.withValues(alpha: .45)
              : outline;
          return Semantics(
            button: true,
            label:
                '${episode.placedLabel} ${watched ? '已看' : (aired ? '未看' : '未更新')}'
                '${cached ? ' 已缓存' : ''}',
            onTap: () => widget.onSelect(episode),
            child: AnimatedContainer(
              duration: motionDuration(context, 120),
              width: width,
              height: _height,
              decoration: BoxDecoration(
                color: background,
                borderRadius: badgeBorderRadius,
                border: Border.all(color: border, width: cached ? 1.5 : 1),
              ),
              child: Center(
                child: AnimatedDefaultTextStyle(
                  duration: motionDuration(context, 120),
                  style: appFont.copyWith(
                    fontSize: FontSize.small,
                    color: foreground,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  child: EpisodeNumber(episode),
                ),
              ),
            ),
          );
        }

        Widget swatch(Color fill, Color border, {double width = 1}) =>
            Container(
              width: 12,
              height: 12,
              margin: const EdgeInsets.only(right: Gap.xs),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: badgeBorderRadius,
                border: Border.all(color: border, width: width),
              ),
            );
        final anyCached = widget.episodes.any(widget.cached);
        Widget legend(Widget mark, String text) =>
            Row(mainAxisSize: MainAxisSize.min, children: [mark, Text(text)]);
        final target = dragStatus == EpisodeStatus.watched ? '已看' : '未看';
        final hint = dragStatus == null
            ? null
            : outside
            ? '松开将取消'
            : '已选 ${selected.length} 话，松开标为$target，Esc 取消';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (paged)
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.md),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: '前 $_pageSize 话',
                      onPressed: current > 0 ? () => _turn(current - 1) : null,
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    MelonChoiceMenu<int>(
                      tooltip: '选择话数范围',
                      options: {
                        for (final (i, range) in pages.indexed)
                          i: range.first.main
                              ? '第 ${range.first.number}–${range.last.number} 话'
                              : '番外与特别篇  ${range.length}',
                      },
                      value: current,
                      onSelected: _turn,
                    ),
                    IconButton(
                      tooltip: '后 $_pageSize 话',
                      onPressed: current < pages.length - 1
                          ? () => _turn(current + 1)
                          : null,
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                    const SizedBox(width: Gap.sm),
                    Flexible(
                      child: Text(
                        specials > 0 ? '共 $main 话  番外 $specials' : '共 $main 话',
                        style: small,
                      ),
                    ),
                  ],
                ),
              ),
            AnimatedSize(
              duration: motionDuration(context, 280),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topLeft,
              child: Listener(
                onPointerDown: (event) {
                  if (event.buttons & kSecondaryMouseButton != 0) _cancel();
                },
                onPointerMove: (event) {
                  if (event.buttons & kSecondaryMouseButton != 0) _cancel();
                },
                child: RawGestureDetector(
                  gestures: {
                    TapGestureRecognizer:
                        GestureRecognizerFactoryWithHandlers<
                          TapGestureRecognizer
                        >(
                          TapGestureRecognizer.new,
                          (recognizer) => recognizer
                            ..onTapUp = (details) {
                              final index = indexAt(details.localPosition);
                              if (index != null) {
                                widget.onSelect(visible[index]!);
                              }
                            }
                            ..onSecondaryTapUp = (details) {
                              final index = indexAt(details.localPosition);
                              if (index != null && dragStatus == null) {
                                unawaited(
                                  _menu(
                                    details.globalPosition,
                                    visible[index]!,
                                  ),
                                );
                              }
                            },
                        ),
                    LongPressGestureRecognizer:
                        GestureRecognizerFactoryWithHandlers<
                          LongPressGestureRecognizer
                        >(
                          () => LongPressGestureRecognizer(
                            duration: const Duration(milliseconds: 600),
                          ),
                          (recognizer) => recognizer
                            ..onLongPressStart = (details) {
                              final index = indexAt(details.localPosition);
                              if (index != null) _start(visible[index]!);
                            }
                            ..onLongPressMoveUpdate = (details) {
                              drag(details.localPosition);
                            }
                            ..onLongPressEnd = (_) {
                              _end();
                            }
                            ..onLongPressCancel = _cancel,
                        ),
                  },
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    onHover: (event) {
                      final index = indexAt(event.localPosition);
                      if (index != hovered.value) {
                        hovered.value = index;
                        widget.onHover(index == null ? null : visible[index]!);
                      }
                    },
                    onExit: (_) {
                      hovered.value = null;
                      widget.onHover(null);
                    },
                    child: Stack(
                      children: [
                        Wrap(
                          spacing: _gap,
                          runSpacing: _gap,
                          children: [
                            for (var i = 0; i < visible.length; i++) cell(i),
                          ],
                        ),
                        ValueListenableBuilder<int?>(
                          valueListenable: hovered,
                          builder: (context, index, _) {
                            if (index == null ||
                                index >= visible.length ||
                                dragStatus != null) {
                              return const SizedBox.shrink();
                            }
                            return Positioned(
                              left: index % columns * (width + _gap),
                              top: index ~/ columns * (_height + _gap),
                              width: width,
                              height: _height,
                              child: IgnorePointer(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: badgeBorderRadius,
                                    border: Border.all(
                                      color: scheme.primary,
                                      width: widget.cached(visible[index]!)
                                          ? 1.5
                                          : 1,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: Gap.md),
            DefaultTextStyle.merge(
              style: small?.copyWith(fontSize: FontSize.caption),
              child: Wrap(
                spacing: Gap.lg,
                runSpacing: Gap.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  legend(
                    swatch(scheme.primaryContainer, scheme.primaryContainer),
                    '已看',
                  ),
                  legend(
                    swatch(Colors.transparent, scheme.outlineVariant),
                    '未看',
                  ),
                  legend(
                    swatch(
                      scheme.surfaceContainerHigh,
                      scheme.surfaceContainerHigh,
                    ),
                    '未更新',
                  ),
                  if (anyCached)
                    legend(
                      swatch(
                        Colors.transparent,
                        scheme.primary.withValues(alpha: .45),
                        width: 1.5,
                      ),
                      '已缓存',
                    ),
                  if (hint == null)
                    const HelpHint(
                      message: '点击观看已缓存的一话，未缓存时选择资源\n长按标为已看，按住拖动可选多话\n右键查看更多操作',
                    )
                  else
                    Text(
                      hint,
                      style: TextStyle(
                        color: outside
                            ? toneColor(context, NoticeTone.warning)
                            : scheme.primary,
                      ),
                    ),
                  if (collapsible)
                    TextButton(
                      style: compactTextButtonStyle,
                      onPressed: () => setState(() => expanded = !expanded),
                      child: Text(expanded ? '收起' : '展开全部 $main 话'),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Explains the specials under the main episodes.
const specialsHelp = '番外与特别篇\n小字为放送位置，17.5 表示在第 17、18 话之间播出';

/// An episode's number in a grid cell, with where a special aired beneath
/// it in smaller type.
class EpisodeNumber extends StatelessWidget {
  const EpisodeNumber(this.episode, {super.key});
  final Episode episode;

  @override
  Widget build(BuildContext context) {
    final between = episode.between;
    if (between == null) return Text(episode.number, maxLines: 1);
    final color = DefaultTextStyle.of(context).style.color;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(episode.number, maxLines: 1, style: const TextStyle(height: 1.1)),
        Text(
          between,
          maxLines: 1,
          style: TextStyle(
            fontSize: FontSize.caption,
            height: 1.1,
            color: color?.withValues(alpha: .7),
          ),
        ),
      ],
    );
  }
}

/// [EpisodeGrid]'s cells in grey while the episodes load, as many as the
/// collapsed grid would show; until [shown], only the space.
class EpisodeGridSkeleton extends StatelessWidget {
  const EpisodeGridSkeleton({super.key, this.count, this.shown = true});

  /// The subject's episode count; a dozen when unknown.
  final int? count;
  final bool shown;

  @override
  Widget build(BuildContext context) {
    const gap = _EpisodeGridState._gap, height = _EpisodeGridState._height;
    final small = Theme.of(context).textTheme.bodySmall;
    return SkeletonGroup(
      label: '正在加载剧集',
      shown: shown,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = math.max(
            1,
            ((constraints.maxWidth + gap) / (_EpisodeGridState._minWidth + gap))
                .floor(),
          );
          final width =
              (constraints.maxWidth - gap * (columns - 1)) / columns - .01;
          final cells = (count ?? 12).clamp(
            1,
            _EpisodeGridState._rows * columns,
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (var i = 0; i < cells; i++)
                    SkeletonBlock(width: width, height: height),
                ],
              ),
              const SizedBox(height: Gap.md),
              SkeletonLine(
                style: small?.copyWith(fontSize: FontSize.caption),
                width: 180,
              ),
            ],
          );
        },
      ),
    );
  }
}

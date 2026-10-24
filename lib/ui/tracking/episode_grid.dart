import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/catalog.dart';
import '../core/motion.dart';
import '../core/selection_controls.dart';
import '../core/theme.dart';

/// All episodes as numbered cells, the specials after the main episodes on
/// rows of their own behind an SP label. Click plays the episode's cache or opens
/// its resources, right-click offers more, and a long press marks; while still pressed,
/// dragging selects the range from the pressed cell to the pointer, so
/// dragging back shrinks it. Releasing well outside the cells, the right
/// button or Escape cancels the pending mark.
class EpisodeGrid extends StatefulWidget {
  const EpisodeGrid({
    super.key,
    required this.episodes,
    required this.nextId,
    required this.statusOf,
    required this.aired,
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
  final ValueChanged<Episode> onSelect, onOpen, onPlay;
  final void Function(List<Episode> episodes, EpisodeStatus status) onMark;
  final ValueChanged<Episode?> onHover;

  @override
  State<EpisodeGrid> createState() => _EpisodeGridState();
}

class _EpisodeGridState extends State<EpisodeGrid> {
  static const _gap = 6.0, _minWidth = 40.0, _height = 30.0, _rows = 4;
  static const _cancelMargin = 48.0;
  bool expanded = false;
  int? hovered;

  /// Pending mark while a long press is held: the range between the pressed
  /// and the current episode, by id so it survives data refreshes.
  EpisodeStatus? dragStatus;
  int? anchorId, currentId;
  bool outside = false;

  /// Main episodes in order, then the specials by number as Bangumi lists
  /// them.
  List<Episode> get ordered => [
    for (final episode in widget.episodes)
      if (episode.main) episode,
    ...widget.episodes.where((e) => !e.main).toList()
      ..sort((a, b) => a.sort.compareTo(b.sort)),
  ];

  Set<int> get dragIds {
    if (dragStatus == null) return const {};
    final ids = [for (final episode in ordered) _id(episode)];
    final a = ids.indexOf(anchorId!), b = ids.indexOf(currentId!);
    if (a < 0 || b < 0) return const {};
    return ids.sublist(math.min(a, b), math.max(a, b) + 1).toSet();
  }

  static int _id(Episode episode) => episode.id;

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
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
      anchorId = currentId = _id(episode);
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
        if (dragIds.contains(_id(episode)) &&
            widget.statusOf(episode) != status)
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
        // Cells by position: the specials start a row after the main
        // episodes, behind the SP label at [label]; other gaps are null.
        final slots = <Episode?>[
          ...episodes.take(main),
          if (specials > 0) ...[
            ...List.filled((columns - main % columns) % columns, null),
            null,
            ...episodes.skip(main),
          ],
        ];
        final label = specials > 0 ? slots.length - specials - 1 : -1;
        final rows = (slots.length / columns).ceil();
        final collapsible = rows > _rows;
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
          final id = index == null || away ? currentId : _id(visible[index]!);
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
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
            );
          }
          final status = selected.contains(_id(episode))
              ? dragStatus!
              : widget.statusOf(episode);
          final watched = status == EpisodeStatus.watched;
          final aired = widget.aired(episode);
          final (background, foreground, border) = watched
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
          return Semantics(
            button: true,
            label:
                '${episode.placedLabel} ${watched ? '已看' : (aired ? '未看' : '未更新')}',
            onTap: () => widget.onSelect(episode),
            child: AnimatedContainer(
              duration: motionDuration(context, 120),
              width: width,
              height: _height,
              decoration: BoxDecoration(
                color: background,
                borderRadius: badgeBorderRadius,
                border: Border.all(
                  color: hovered == index && dragStatus == null
                      ? scheme.primary
                      : border,
                ),
              ),
              child: Center(
                child: AnimatedDefaultTextStyle(
                  duration: motionDuration(context, 120),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: foreground,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  child: EpisodeNumber(episode),
                ),
              ),
            ),
          );
        }

        Widget swatch(Color fill, Color border) => Container(
          width: 12,
          height: 12,
          margin: const EdgeInsets.only(right: 5),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: border),
          ),
        );
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
            // 展开 and 收起 grow and shrink the grid instead of jumping.
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
                      if (index != hovered) {
                        setState(() => hovered = index);
                        widget.onHover(index == null ? null : visible[index]!);
                      }
                    },
                    onExit: (_) {
                      setState(() => hovered = null);
                      widget.onHover(null);
                    },
                    child: Wrap(
                      spacing: _gap,
                      runSpacing: _gap,
                      children: [
                        for (var i = 0; i < visible.length; i++) cell(i),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: Gap.sm + 2),
            DefaultTextStyle.merge(
              style: small?.copyWith(fontSize: 11),
              child: Wrap(
                spacing: Gap.lg,
                runSpacing: 4,
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
                  if (hint == null)
                    Tooltip(
                      message: '点击观看已缓存的一话，未缓存时选择资源\n长按标为已看，按住拖动可选多话\n右键查看更多操作',
                      child: Icon(
                        Icons.help_outline_rounded,
                        size: 14,
                        color: scheme.onSurfaceVariant,
                      ),
                    )
                  else
                    Text(
                      hint,
                      style: TextStyle(
                        color: outside ? scheme.error : scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  if (collapsible)
                    TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 28),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
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
const specialsHelp =
    'SP、OVA、番外、总集篇等，按 Bangumi 的编号列出\n'
    '下方小字是放送位置，17.5 即在第 17、18 话之间播出\n'
    '自动连播按放送顺序一起播放，总集篇和特番可在设置中跳过';

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
            fontSize: 9,
            height: 1.1,
            fontWeight: FontWeight.w500,
            color: color?.withValues(alpha: .7),
          ),
        ),
      ],
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../features/playback/playback_preferences.dart';
import '../core/selection_controls.dart';
import '../core/theme.dart';

/// The release group filter's menu: the preferred groups first, in their
/// order, then the others by result count. Dragging a group above or below
/// the line, or within the preferred ones, sets the preference and its
/// order; hovering offers the same as text.
class GroupFilterPanel extends StatefulWidget {
  const GroupFilterPanel({
    super.key,
    required this.prefs,
    required this.names,
    required this.counts,
    required this.selected,
    required this.onToggle,
  });
  final PlaybackPreferences prefs;

  /// Groups of the results, the most common first.
  final List<String> names;
  final Map<String, int> counts;
  final Set<String> selected;
  final void Function(String name, bool selected) onToggle;

  @override
  State<GroupFilterPanel> createState() => _GroupFilterPanelState();
}

class _GroupFilterPanelState extends State<GroupFilterPanel> {
  static const _line = '\u0000line';
  static const _rowHeight = 38.0;
  String? hovered;

  void prefer(List<String> preferred) =>
      widget.prefs.setPreferredGroups(preferred);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.prefs,
    builder: (context, _) {
      final preferred = widget.prefs.preferredGroups;
      final wanted = {for (final name in preferred) name.toLowerCase()};
      final others = [
        for (final name in widget.names)
          if (!wanted.contains(name.toLowerCase())) name,
      ];
      final rows = [...preferred, _line, ...others];
      final scheme = Theme.of(context).colorScheme;
      final small = Theme.of(context).textTheme.bodySmall;
      Widget caption(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Text(text, style: small?.copyWith(fontSize: 11)),
      );
      Widget row(int index, String name) {
        final isPreferred = index < preferred.length;
        final count = widget.counts[name] ?? 0;
        final on = widget.selected.contains(name);
        return MouseRegion(
          key: ValueKey(name),
          onEnter: (_) => setState(() => hovered = name),
          onExit: (_) => setState(() {
            if (hovered == name) hovered = null;
          }),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: count > 0 || on ? () => widget.onToggle(name, !on) : null,
              child: SizedBox(
                height: _rowHeight,
                child: Row(
                  children: [
                    ReorderableDragStartListener(
                      index: index,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.grab,
                        child: SizedBox(
                          width: 28,
                          height: _rowHeight,
                          child: Icon(
                            Icons.drag_indicator_rounded,
                            size: 16,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                    FilterCheck(on),
                    const SizedBox(width: 10),
                    if (isPreferred) ...[
                      Container(
                        width: 18,
                        height: 18,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: accentOf(context).accent
                              .withValues(alpha: .16),
                          borderRadius: badgeBorderRadius,
                        ),
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: scheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: count > 0 || on
                              ? null
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: Gap.sm),
                    if (hovered == name)
                      TextButton(
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 28),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          textStyle: appFont.copyWith(fontSize: 12),
                        ),
                        onPressed: () => prefer(
                          isPreferred
                              ? (List.of(preferred)..remove(name))
                              : [...preferred, name],
                        ),
                        child: Text(isPreferred ? '取消偏好' : '设为偏好'),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          '$count',
                          style: small?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      return SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            caption(
              preferred.isEmpty ? '偏好 · 把字幕组拖到这条线上方，优先推荐' : '偏好 · 优先推荐，拖动调整顺序',
            ),
            SizedBox(
              height: math.min(rows.length * _rowHeight + 8, 380),
              child: ReorderableListView.builder(
                buildDefaultDragHandles: false,
                itemCount: rows.length,
                onReorderItem: (from, to) {
                  final order = [...rows];
                  order.insert(to, order.removeAt(from));
                  prefer(order.takeWhile((name) => name != _line).toList());
                },
                itemBuilder: (context, index) => rows[index] == _line
                    ? Column(
                        key: const ValueKey(_line),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Divider(height: 9, indent: 8, endIndent: 8),
                          caption(others.isEmpty ? '没有其他字幕组' : '其他字幕组'),
                        ],
                      )
                    : row(index, rows[index]),
              ),
            ),
            const Divider(height: 9, indent: 8, endIndent: 8),
            Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: () => widget.prefs.setOnlyPreferredGroups(
                  !widget.prefs.onlyPreferredGroups,
                ),
                child: SizedBox(
                  height: _rowHeight,
                  child: Row(
                    children: [
                      const SizedBox(width: 28),
                      FilterCheck(widget.prefs.onlyPreferredGroups),
                      const SizedBox(width: 10),
                      const Text('只显示偏好字幕组', style: TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

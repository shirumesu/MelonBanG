import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/catalog.dart';
import '../core/motion.dart';
import '../core/theme.dart';

/// Lets the user pick the episodes of one resource to download, by range
/// text (`1-3, 5, 8-12`) or by cells; Shift-click selects a run. Returns the
/// chosen episodes in order, or null when cancelled.
Future<List<Episode>?> showResourceBatchDialog(
  BuildContext context, {
  required String title,
  required String source,
  required List<Episode> episodes,
  required Set<int> available,
  Set<int> added = const {},
  Set<int> cached = const {},
}) => showDialog<List<Episode>>(
  context: context,
  builder: (_) => _BatchDialog(
    title: title,
    source: source,
    episodes: episodes,
    available: available,
    added: added,
    cached: cached,
  ),
);

/// `1–5, 7, 9–12` for episode numbers.
String episodeSpans(Iterable<double> numbers) {
  String show(double n) => n == n.roundToDouble() ? '${n.toInt()}' : '$n';
  final sorted = numbers.toSet().toList()..sort();
  final spans = <String>[];
  for (var i = 0; i < sorted.length; i++) {
    var j = i;
    while (j + 1 < sorted.length && sorted[j + 1] == sorted[j] + 1) {
      j++;
    }
    spans.add(
      i == j ? show(sorted[i]) : '${show(sorted[i])}–${show(sorted[j])}',
    );
    i = j;
  }
  return spans.join(', ');
}

class _BatchDialog extends StatefulWidget {
  const _BatchDialog({
    required this.title,
    required this.source,
    required this.episodes,
    required this.available,
    required this.added,
    required this.cached,
  });
  final String title, source;
  final List<Episode> episodes;

  /// Episodes the resource holds; [added] ones were already added from it,
  /// and [cached] ones have a cache task from elsewhere.
  final Set<int> available, added, cached;

  @override
  State<_BatchDialog> createState() => _BatchDialogState();
}

class _BatchDialogState extends State<_BatchDialog> {
  final range = TextEditingController();
  late final Set<int> selected;
  int? anchor;

  /// Episodes that can be chosen, in order.
  late final List<Episode> choices = [
    for (final episode in widget.episodes)
      if (widget.available.contains(episode.id) &&
          !widget.added.contains(episode.id))
        episode,
  ];

  @override
  void initState() {
    super.initState();
    selected = {
      for (final episode in choices)
        if (!widget.cached.contains(episode.id)) episode.id,
    };
    writeRange();
  }

  @override
  void dispose() {
    range.dispose();
    super.dispose();
  }

  /// Shows the selection as spans over the choosable episodes, so a gap the
  /// resource does not hold stays inside one span.
  void writeRange() {
    final spans = <String>[];
    for (var i = 0; i < choices.length; i++) {
      if (!selected.contains(choices[i].id)) continue;
      var j = i;
      while (j + 1 < choices.length && selected.contains(choices[j + 1].id)) {
        j++;
      }
      spans.add(
        i == j
            ? choices[i].number
            : '${choices[i].number}-${choices[j].number}',
      );
      i = j;
    }
    range.text = spans.join(', ');
  }

  void readRange(String text) {
    final ids = <int>{};
    final parts = text
        .replaceAll(RegExp(r'\s*[-–~～]\s*'), '-')
        .split(RegExp(r'[,，、;；\s]+'));
    for (final part in parts) {
      final match = RegExp(r'^(\d+(?:\.\d+)?)(?:-(\d+(?:\.\d+)?))?$')
          .firstMatch(part);
      if (match == null) continue;
      final a = double.parse(match[1]!),
          b = double.parse(match[2] ?? match[1]!);
      for (final episode in choices) {
        if (episode.sort >= math.min(a, b) && episode.sort <= math.max(a, b)) {
          ids.add(episode.id);
        }
      }
    }
    setState(
      () => selected
        ..clear()
        ..addAll(ids),
    );
  }

  void toggle(Episode episode) {
    final on = !selected.contains(episode.id);
    final from = anchor == null || !HardwareKeyboard.instance.isShiftPressed
        ? null
        : choices.indexWhere((e) => e.id == anchor);
    final to = choices.indexOf(episode);
    setState(() {
      for (final e
          in from == null || from < 0
              ? [episode]
              : choices.sublist(math.min(from, to), math.max(from, to) + 1)) {
        on ? selected.add(e.id) : selected.remove(e.id);
      }
      anchor = episode.id;
      writeRange();
    });
  }

  void selectAll(bool on) => setState(() {
    on ? selected.addAll(choices.map((e) => e.id)) : selected.clear();
    writeRange();
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    final count = selected.length;
    Widget cell(Episode episode) {
      final id = episode.id;
      final held = widget.available.contains(id);
      final added = widget.added.contains(id);
      final on = selected.contains(id);
      final cached = widget.cached.contains(id);
      final (background, foreground, border) = on
          ? (scheme.primary, scheme.onPrimary, scheme.primary)
          : added
          ? (
              scheme.primaryContainer,
              scheme.onPrimaryContainer,
              scheme.primaryContainer,
            )
          : held
          ? (Colors.transparent, scheme.onSurfaceVariant, scheme.outlineVariant)
          : (
              scheme.surfaceContainerHigh,
              scheme.onSurfaceVariant.withValues(alpha: .4),
              scheme.surfaceContainerHigh,
            );
      final label = episode.main ? episode.number : 'SP${episode.number}';
      return Tooltip(
        message: !held
            ? '这个资源没有第 ${episode.number} 话'
            : added
            ? '已加入缓存'
            : cached
            ? '已有其他缓存'
            : '第 ${episode.number} 话',
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: badgeBorderRadius,
            onTap: held && !added ? () => toggle(episode) : null,
            child: AnimatedContainer(
              duration: motionDuration(context, 120),
              width: 44,
              height: 30,
              decoration: BoxDecoration(
                color: background,
                borderRadius: badgeBorderRadius,
                border: Border.all(color: border),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  added
                      ? Icon(Icons.check_rounded, size: 15, color: foreground)
                      : Text(
                          label,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: foreground,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                  if (cached && !added)
                    Positioned(
                      top: 3,
                      right: 3,
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: on ? scheme.onPrimary : sky,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return AlertDialog(
      title: Row(
        children: [
          const Text('批量下载'),
          const SizedBox(width: Gap.sm),
          Tooltip(
            message: '输入集数区间，或点击格子增减；按住 Shift 点击选择连续的集数',
            child: Icon(
              Icons.help_outline_rounded,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(widget.source, style: small),
            const SizedBox(height: Gap.lg),
            TextField(
              controller: range,
              autofocus: true,
              onChanged: readRange,
              decoration: InputDecoration(
                prefixText: '集数  ',
                hintText: '如 1-3, 5, 8-12',
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: count == choices.length
                          ? null
                          : () => selectAll(true),
                      child: const Text('全选'),
                    ),
                    TextButton(
                      onPressed: count == 0 ? null : () => selectAll(false),
                      child: const Text('清空'),
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Gap.md),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 248),
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final episode in widget.episodes) cell(episode),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: count == 0
              ? null
              : () => Navigator.pop(context, [
                  for (final episode in choices)
                    if (selected.contains(episode.id)) episode,
                ]),
          child: Text(count == 0 ? '下载' : '下载 $count 集'),
        ),
      ],
    );
  }
}

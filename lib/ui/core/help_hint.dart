import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// A ? mark whose tooltip also opens on click, for how-to notes beside a
/// title. The note shows to its right, so it never covers the subtitle under
/// the title; write it as short lines. [size] is the mark's, in a button
/// 10 wider.
class HelpHint extends StatefulWidget {
  const HelpHint({super.key, required this.message, this.size = 14});
  final String message;
  final double size;

  @override
  State<HelpHint> createState() => _HelpHintState();
}

class _HelpHintState extends State<HelpHint> {
  final tooltip = GlobalKey<TooltipState>();

  @override
  Widget build(BuildContext context) => Tooltip(
    key: tooltip,
    message: widget.message,
    constraints: const BoxConstraints(maxWidth: 320),
    padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: Gap.xs),
    textAlign: TextAlign.start,
    positionDelegate: _beside,
    child: IconButton(
      onPressed: () => tooltip.currentState?.ensureTooltipVisible(),
      icon: const Icon(Icons.help_outline_rounded),
      iconSize: widget.size,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(
        width: widget.size + 10,
        height: widget.size + 10,
      ),
      visualDensity: VisualDensity.compact,
    ),
  );

  /// Right of the mark and vertically centred on it; left when the window
  /// is too narrow.
  static Offset _beside(TooltipPositionContext context) {
    const gap = 6.0, margin = 8.0;
    final overlay = context.overlaySize, size = context.tooltipSize;
    final half = context.targetSize.width / 2;
    final right = context.target.dx + half + gap;
    final x = right + size.width <= overlay.width - margin
        ? right
        : math.max(margin, context.target.dx - half - gap - size.width);
    final y = (context.target.dy - size.height / 2)
        .clamp(margin, math.max(margin, overlay.height - size.height - margin))
        .toDouble();
    return Offset(x, y);
  }
}

import 'package:flutter/material.dart';

import '../core/byte_units.dart';
import '../core/motion.dart';
import '../core/selection_controls.dart';
import '../core/theme.dart';

/// Floats at the foot of the cache page while several rows are picked:
/// how many and how large, with the way to delete them or let them go. It
/// keeps showing where the page has scrolled away from the picks.
class CacheSelectionBar extends StatelessWidget {
  const CacheSelectionBar({
    super.key,
    required this.count,
    required this.bytes,
    required this.onDelete,
    required this.onClear,
  });

  /// Shown from two picks; one row is acted on from its own buttons.
  static bool shows(int count) => count > 1;

  final int count, bytes;
  final VoidCallback onDelete, onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visible = shows(count);
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSwitcher(
        duration: motionDuration(context, 180),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, .4),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: !visible
            ? const SizedBox.shrink()
            : Material(
                key: const ValueKey('cache-selection'),
                color: menuSurface(context),
                elevation: 3,
                shadowColor: Theme.of(context).popupMenuTheme.shadowColor,
                shape: const RoundedRectangleBorder(
                  borderRadius: panelBorderRadius,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Gap.lg,
                    Gap.sm,
                    Gap.sm,
                    Gap.sm,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        bytes > 0
                            ? '已选 $count 项 · ${ByteUnitsScope.of(context).format(bytes)}'
                            : '已选 $count 项',
                        style: const TextStyle(fontSize: FontSize.body),
                      ),
                      const SizedBox(width: Gap.lg),
                      TextButton(onPressed: onClear, child: const Text('取消选择')),
                      const SizedBox(width: Gap.xs),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: scheme.errorContainer,
                          foregroundColor: scheme.onErrorContainer,
                        ),
                        onPressed: onDelete,
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('删除'),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

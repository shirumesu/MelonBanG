import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'motion.dart';
import 'theme.dart';

class MelonSegmentedControl<T> extends StatefulWidget {
  const MelonSegmentedControl({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.allowDrag = false,
    this.semanticLabel,
  });

  final Map<T, String> options;
  final T? value;
  final ValueChanged<T>? onChanged;
  final bool allowDrag;
  final String? semanticLabel;

  @override
  State<MelonSegmentedControl<T>> createState() =>
      _MelonSegmentedControlState<T>();
}

class _MelonSegmentedControlState<T> extends State<MelonSegmentedControl<T>> {
  final _focus = <T, FocusNode>{};
  double? _dragPosition;
  int? _dragTarget;
  bool _dragInside = true;

  @override
  void didUpdateWidget(covariant MelonSegmentedControl<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    for (final key in _focus.keys.toList()) {
      if (!widget.options.containsKey(key)) _focus.remove(key)!.dispose();
    }
    if (widget.onChanged == null ||
        oldWidget.options.length != widget.options.length) {
      _dragPosition = null;
      _dragTarget = null;
    }
  }

  @override
  void dispose() {
    for (final node in _focus.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _drag(Offset point, double width, bool rtl) {
    final segmentWidth = (width - 6) / widget.options.length;
    final physical = ((point.dx - 3) / segmentWidth - .5).clamp(
      0.0,
      widget.options.length - 1.0,
    );
    final target = ((point.dx - 3) / segmentWidth).floor().clamp(
      0,
      widget.options.length - 1,
    );
    setState(() {
      _dragInside =
          point.dy >= -12 &&
          point.dy <= 56 &&
          point.dx >= -12 &&
          point.dx <= width + 12;
      _dragPosition = physical;
      _dragTarget = rtl ? widget.options.length - 1 - target : target;
    });
  }

  void _finishDrag({bool cancelled = false}) {
    final target = _dragTarget;
    final commit = !cancelled && _dragInside && target != null;
    setState(() {
      _dragPosition = null;
      _dragTarget = null;
    });
    if (commit) {
      final value = widget.options.keys.elementAt(target);
      if (value != widget.value) widget.onChanged?.call(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.options.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final entries = widget.options.entries.toList();
    final selected = entries.indexWhere((e) => e.key == widget.value);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final draggable = widget.allowDrag && widget.onChanged != null;
    return Semantics(
      label: widget.semanticLabel,
      container: true,
      explicitChildNodes: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.hasBoundedWidth
              ? constraints.maxWidth
              : entries.length * 84.0 + 6;
          final segmentWidth = (width - 6) / entries.length;
          final physical = selected < 0
              ? 0
              : rtl
              ? entries.length - 1 - selected
              : selected;
          return GestureDetector(
            onHorizontalDragStart: draggable
                ? (details) => _drag(details.localPosition, width, rtl)
                : null,
            onHorizontalDragUpdate: draggable
                ? (details) => _drag(details.localPosition, width, rtl)
                : null,
            onHorizontalDragEnd: draggable ? (_) => _finishDrag() : null,
            onHorizontalDragCancel: draggable
                ? () => _finishDrag(cancelled: true)
                : null,
            child: Material(
              color: scheme.surfaceContainerLow,
              borderRadius: controlBorderRadius,
              child: SizedBox(
                width: width,
                height: 44,
                child: Stack(
                  children: [
                    if (selected >= 0 || _dragPosition != null)
                      AnimatedPositioned(
                        key: const ValueKey('selection-indicator'),
                        duration: _dragPosition == null
                            ? motionDuration(context, 220)
                            : Duration.zero,
                        curve: Curves.easeOutCubic,
                        left:
                            3 +
                            (_dragPosition ?? physical.toDouble()) *
                                segmentWidth,
                        top: 3,
                        bottom: 3,
                        width: segmentWidth,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            borderRadius: BorderRadius.circular(9),
                            boxShadow: [
                              BoxShadow(
                                color: Theme.of(context).shadowColor,
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(3),
                      child: Row(
                        children: [
                          for (var i = 0; i < entries.length; i++)
                            Expanded(
                              child: Focus(
                                canRequestFocus: false,
                                onKeyEvent: (_, event) {
                                  if (event is! KeyDownEvent) {
                                    return KeyEventResult.ignored;
                                  }
                                  final key = event.logicalKey;
                                  var next = i;
                                  if (key == LogicalKeyboardKey.arrowLeft) {
                                    next += rtl ? 1 : -1;
                                  } else if (key ==
                                      LogicalKeyboardKey.arrowRight) {
                                    next += rtl ? -1 : 1;
                                  } else if (key == LogicalKeyboardKey.home) {
                                    next = 0;
                                  } else if (key == LogicalKeyboardKey.end) {
                                    next = entries.length - 1;
                                  } else {
                                    return KeyEventResult.ignored;
                                  }
                                  _focus[entries[next.clamp(
                                            0,
                                            entries.length - 1,
                                          )]
                                          .key]
                                      ?.requestFocus();
                                  return KeyEventResult.handled;
                                },
                                child: Semantics(
                                  selected: selected == i,
                                  inMutuallyExclusiveGroup: true,
                                  button: true,
                                  child: InkWell(
                                    focusNode: _focus.putIfAbsent(
                                      entries[i].key,
                                      FocusNode.new,
                                    ),
                                    onTap: widget.onChanged == null
                                        ? null
                                        : () {
                                            if (widget.value !=
                                                entries[i].key) {
                                              widget.onChanged!(entries[i].key);
                                            }
                                          },
                                    borderRadius: BorderRadius.circular(9),
                                    child: Center(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                        ),
                                        child: AnimatedDefaultTextStyle(
                                          duration: motionDuration(
                                            context,
                                            140,
                                          ),
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelMedium!
                                              .copyWith(
                                                color: widget.onChanged == null
                                                    ? scheme.onSurfaceVariant
                                                          .withValues(alpha: .5)
                                                    : selected == i
                                                    ? scheme.primary
                                                    : scheme.onSurfaceVariant,
                                                fontWeight: selected == i
                                                    ? FontWeight.w600
                                                    : FontWeight.w400,
                                              ),
                                          child: Text(
                                            entries[i].value,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    ),
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
            ),
          );
        },
      ),
    );
  }
}

class MelonChoiceMenu<T> extends StatelessWidget {
  const MelonChoiceMenu({
    super.key,
    required this.options,
    required this.value,
    required this.onSelected,
    this.icon,
    this.label,
    this.tooltip,
  });

  final Map<T, String> options;
  final T value;
  final ValueChanged<T>? onSelected;
  final IconData? icon;
  final String? label, tooltip;

  @override
  Widget build(BuildContext context) => MenuAnchor(
    crossAxisUnconstrained: false,
    style: MenuStyle(
      backgroundColor: WidgetStatePropertyAll(
        Theme.of(context).colorScheme.surface,
      ),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      padding: const WidgetStatePropertyAll(EdgeInsets.all(5)),
      shape: const WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: controlBorderRadius),
      ),
      elevation: const WidgetStatePropertyAll(3),
    ),
    menuChildren: [
      for (final entry in options.entries)
        MenuItemButton(
          onPressed: onSelected == null ? null : () => onSelected!(entry.key),
          leadingIcon: SizedBox.square(
            dimension: 18,
            child: entry.key == value
                ? Icon(
                    Icons.check_rounded,
                    size: 17,
                    color: Theme.of(context).colorScheme.primary,
                  )
                : null,
          ),
          child: Text(entry.value),
        ),
    ],
    builder: (context, controller, _) => Tooltip(
      message: tooltip ?? label ?? options[value] ?? '',
      child: OutlinedButton(
        onPressed: onSelected == null
            ? null
            : () => controller.isOpen ? controller.close() : controller.open(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16),
              const SizedBox(width: 7),
            ],
            Flexible(
              child: Text(
                label ?? options[value] ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 17),
          ],
        ),
      ),
    ),
  );
}

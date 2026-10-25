import 'dart:math' as math;

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
                            borderRadius: BorderRadius.circular(5),
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
                                    borderRadius: BorderRadius.circular(5),
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
            _MenuChevron(open: controller.isOpen),
          ],
        ),
      ),
    ),
  );
}

/// A menu button's arrow, turning over while its menu is open.
class _MenuChevron extends StatelessWidget {
  const _MenuChevron({required this.open});
  final bool open;

  @override
  Widget build(BuildContext context) => AnimatedRotation(
    turns: open ? .5 : 0,
    duration: motionDuration(context, 220),
    curve: Curves.easeOutCubic,
    child: const Icon(Icons.keyboard_arrow_down_rounded, size: 17),
  );
}

class MelonFilterOption<T> {
  const MelonFilterOption(
    this.value,
    this.label, {
    this.detail,
    this.detailColor,
    this.enabled = true,
    this.more = const [],
  });
  final T value;
  final String label;
  final String? detail;
  final Color? detailColor;
  final bool enabled;

  /// Finer choices opening below this one in a grid, such as a year's
  /// quarters.
  final List<MelonFilterOption<T>> more;
}

class MelonFilterSection<T> {
  const MelonFilterSection(this.options, {this.title});
  final String? title;
  final List<MelonFilterOption<T>> options;
}

/// Multi-select filter: a compact button that opens a checklist and stays open
/// while toggling. [active] fills the button so applied filters stand out.
/// Without [multiple] it picks one option, marked by a check, and closes.
class MelonFilterMenu<T> extends StatelessWidget {
  const MelonFilterMenu({
    super.key,
    required this.label,
    required this.sections,
    required this.selected,
    required this.onToggle,
    this.active,
    this.summary,
    this.icon,
    this.warning = false,
    this.tooltip,
    this.actions = const [],
    this.compact = false,
    this.multiple = true,
    this.columns = 1,
  });

  final String label;
  final List<MelonFilterSection<T>> sections;
  final Set<T> selected;
  final void Function(T value, bool selected) onToggle;

  /// Defaults to "anything selected".
  final bool? active;

  /// Shown after the label when active, e.g. "1080p" or "2 项".
  final String? summary;
  final IconData? icon;
  final bool warning;
  final String? tooltip;

  /// Menu footer actions such as "清除".
  final List<(String, VoidCallback)> actions;

  /// Text-only trigger for use inside a field.
  final bool compact;
  final bool multiple;

  /// Options per row, for long lists of short names.
  final int columns;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    final on = active ?? selected.isNotEmpty;
    Widget check(bool value) => AnimatedContainer(
      duration: motionDuration(context, 120),
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: value ? scheme.primary : Colors.transparent,
        borderRadius: const BorderRadius.all(Radius.circular(5)),
        border: Border.all(
          color: value ? scheme.primary : scheme.onSurfaceVariant,
          width: 1.5,
        ),
      ),
      child: AnimatedScale(
        scale: value ? 1 : 0,
        duration: motionDuration(context, 160),
        curve: value ? Curves.easeOutBack : Curves.easeIn,
        child: Icon(Icons.check_rounded, size: 12, color: scheme.onPrimary),
      ),
    );
    final menu = MenuController();
    Widget mark(bool value) => multiple
        ? check(value)
        : SizedBox.square(
            dimension: 16,
            child: value
                ? Icon(Icons.check_rounded, size: 16, color: scheme.primary)
                : null,
          );
    // Options with finer choices sit in a grid of centred cells; the finer
    // choices open below the hovered one.
    final cells = sections.any(
      (section) => section.options.any((option) => option.more.isNotEmpty),
    );
    final width = cells ? 120.0 : 112.0;
    void pick(T value) {
      onToggle(value, !selected.contains(value));
      if (!multiple) menu.close();
    }

    ButtonStyle pill(bool on, {bool picked = false, double left = 0}) =>
        ButtonStyle(
          padding: WidgetStatePropertyAll(EdgeInsets.only(left: left)),
          minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
          backgroundColor: on
              ? WidgetStatePropertyAll(scheme.primaryContainer)
              : null,
          foregroundColor: on || picked
              ? WidgetStatePropertyAll(
                  on ? scheme.onPrimaryContainer : scheme.primary,
                )
              : null,
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: controlBorderRadius),
          ),
        );
    Widget centred(String label, double width, bool bold) => SizedBox(
      width: width,
      child: Center(
        child: Text(
          label,
          style: TextStyle(fontWeight: bold ? FontWeight.w700 : null),
        ),
      ),
    );
    Widget cell(MelonFilterOption<T> option) {
      final on = selected.contains(option.value);
      final picked = option.more.any((finer) => selected.contains(finer.value));
      if (option.more.isEmpty) {
        return MenuItemButton(
          style: pill(on),
          onPressed: () => pick(option.value),
          child: centred(option.label, width - 4, on),
        );
      }
      // The submenu keeps a gap for its arrow; the same gap on the left
      // keeps the label centred.
      final gap = math.max(
        4.0,
        12 + Theme.of(context).visualDensity.horizontal * 2,
      );
      return SubmenuButton(
        style: pill(on, picked: picked, left: gap),
        submenuIcon: const WidgetStatePropertyAll(SizedBox.shrink()),
        alignmentOffset: const Offset(0, 3),
        menuStyle: const MenuStyle(
          alignment: AlignmentDirectional.bottomStart,
          padding: WidgetStatePropertyAll(EdgeInsets.all(3)),
        ),
        menuChildren: [
          Row(
            children: [
              for (final finer in option.more)
                SizedBox(
                  width: 34,
                  child: MenuItemButton(
                    style: pill(selected.contains(finer.value)),
                    onPressed: () => pick(finer.value),
                    child: centred(
                      finer.label,
                      34,
                      selected.contains(finer.value),
                    ),
                  ),
                ),
            ],
          ),
        ],
        // Hovering opens the finer choices; a click picks the option itself.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => pick(option.value),
          child: SizedBox(
            height: 36,
            child: centred(option.label, width - 4 - gap * 2, on || picked),
          ),
        ),
      );
    }

    Widget item(MelonFilterOption<T> option) => MenuItemButton(
      closeOnActivate: !multiple,
      style: ButtonStyle(
        minimumSize: WidgetStatePropertyAll(Size(columns == 1 ? 200 : 0, 38)),
      ),
      onPressed: option.enabled || selected.contains(option.value)
          ? () => onToggle(option.value, !selected.contains(option.value))
          : null,
      leadingIcon: mark(selected.contains(option.value)),
      trailingIcon: option.detail == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(left: Gap.lg),
              child: Text(
                option.detail!,
                style: small?.copyWith(
                  color: option.detailColor,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Text(option.label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
    return MenuAnchor(
      controller: menu,
      crossAxisUnconstrained: false,
      style: MenuStyle(
        maximumSize: WidgetStatePropertyAll(
          Size(columns > 1 ? columns * width + 10 : 360, 440),
        ),
      ),
      menuChildren: [
        for (final (index, section) in sections.indexed) ...[
          if (index > 0) const Divider(height: 9, indent: 8, endIndent: 8),
          if (section.title case final title?)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
              child: Text(title, style: small?.copyWith(fontSize: 11)),
            ),
          if (columns == 1)
            for (final option in section.options) item(option)
          else
            for (var i = 0; i < section.options.length; i += columns)
              Row(
                children: [
                  for (final option in section.options.skip(i).take(columns))
                    SizedBox(
                      width: width,
                      child: cells
                          ? Padding(
                              padding: const EdgeInsets.all(2),
                              child: cell(option),
                            )
                          : item(option),
                    ),
                ],
              ),
        ],
        if (actions.isNotEmpty) ...[
          const Divider(height: 9, indent: 8, endIndent: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              for (final (text, action) in actions)
                TextButton(onPressed: action, child: Text(text)),
            ],
          ),
        ],
      ],
      builder: (context, controller, _) {
        void toggle() =>
            controller.isOpen ? controller.close() : controller.open();
        final text = on && summary != null ? '$label $summary' : label;
        final content = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            if (warning) ...[
              const SizedBox(width: 5),
              Icon(
                Icons.error_outline_rounded,
                size: 15,
                color: scheme.tertiary,
              ),
            ],
            const SizedBox(width: 4),
            _MenuChevron(open: controller.isOpen),
          ],
        );
        return Tooltip(
          message: tooltip ?? '',
          child: compact
              ? TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: on
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  onPressed: toggle,
                  child: content,
                )
              : TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: on
                        ? scheme.primaryContainer
                        : scheme.surfaceContainerHigh,
                    foregroundColor: on
                        ? scheme.onPrimaryContainer
                        : scheme.onSurface,
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onPressed: toggle,
                  child: content,
                ),
        );
      },
    );
  }
}

/// The fill of popup menus.
Color menuSurface(BuildContext context) =>
    Theme.of(context).popupMenuTheme.color!;

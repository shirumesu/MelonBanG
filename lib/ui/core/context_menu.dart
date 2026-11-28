import 'package:flutter/material.dart';

import 'motion.dart';
import 'selection_controls.dart';
import 'theme.dart';

/// Opens a menu where a secondary click landed, [position] in global
/// coordinates, and gives the chosen value, or null when dismissed.
Future<T?> showContextMenu<T>(
  BuildContext context, {
  required Offset position,
  required List<PopupMenuEntry<T>> items,
  Color? color,
  ShapeBorder? shape,
  EdgeInsetsGeometry? menuPadding,
}) {
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  return showMenu<T>(
    context: context,
    color: color ?? menuSurface(context),
    shape: shape,
    menuPadding: menuPadding,
    popUpAnimationStyle: AnimationStyle(
      duration: motionDuration(context, 150),
      reverseDuration: motionDuration(context, 100),
      curve: Curves.easeOutCubic,
    ),
    position: RelativeRect.fromRect(
      position & const Size(1, 1),
      Offset.zero & overlay.size,
    ),
    items: items,
  );
}

/// An entry of a context menu. With [checked] set, every entry of the menu
/// should set it, so the labels line up after the room kept for the mark.
/// [destructive] ones, such as deleting, read in the failure colour.
PopupMenuItem<T> contextMenuItem<T>(
  T value,
  String label, {
  bool enabled = true,
  bool? checked,
  bool destructive = false,
}) => PopupMenuItem<T>(
  value: value,
  enabled: enabled,
  height: 36,
  child: _ContextMenuLabel(
    label,
    checked: checked,
    destructive: destructive && enabled,
  ),
);

class _ContextMenuLabel extends StatelessWidget {
  const _ContextMenuLabel(
    this.label, {
    required this.checked,
    required this.destructive,
  });
  final String label;
  final bool? checked;
  final bool destructive;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (checked case final checked?) ...[
        SizedBox(
          width: 20,
          child: checked ? const Icon(Icons.check_rounded, size: 16) : null,
        ),
        const SizedBox(width: Gap.xs),
      ],
      Text(
        label,
        style: TextStyle(
          fontSize: FontSize.body,
          color: destructive ? Theme.of(context).colorScheme.error : null,
        ),
      ),
    ],
  );
}

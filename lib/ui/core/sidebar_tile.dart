import 'package:flutter/material.dart';

import 'theme.dart';

/// The highlight a `MotionSelection` glides under the selected
/// [SidebarTile].
Widget sidebarHighlight(BuildContext context) => DecoratedBox(
  decoration: BoxDecoration(
    borderRadius: controlBorderRadius,
    gradient: accentOf(context).navigation,
  ),
);

/// An entry of the main sidebar or the settings contents column, drawn over
/// a [sidebarHighlight] when selected.
class SidebarTile extends StatelessWidget {
  const SidebarTile({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.trailing,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: ListTile(
      dense: true,
      selected: selected,
      selectedColor: accentOf(context).onNavigation,
      iconColor: Theme.of(context).colorScheme.onSurfaceVariant,
      titleTextStyle: Theme.of(context).textTheme.titleSmall,
      selectedTileColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: controlBorderRadius),
      contentPadding: const EdgeInsets.symmetric(horizontal: Gap.md),
      leading: Icon(icon, size: 20),
      title: Text(label),
      trailing: trailing,
      onTap: onTap,
    ),
  );
}

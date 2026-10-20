import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Player tweaks on top of the shell theme; the side panel follows the app's
/// light or dark theme.
ThemeData playerTheme([ThemeData? theme]) {
  final base = theme ?? appTheme(true);
  final scheme = base.colorScheme;
  return base.copyWith(
    colorScheme: scheme,
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      fillColor: scheme.surfaceContainerLow,
    ),
    iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 20),
    progressIndicatorTheme: base.progressIndicatorTheme.copyWith(
      color: scheme.primary,
      linearTrackColor: scheme.onSurface.withValues(alpha: .12),
    ),
    listTileTheme: base.listTileTheme.copyWith(
      selectedTileColor: scheme.primary.withValues(alpha: .1),
      selectedColor: scheme.primary,
    ),
    sliderTheme: base.sliderTheme.copyWith(
      trackHeight: 3,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
      activeTrackColor: scheme.primary,
      thumbColor: scheme.primary,
      inactiveTrackColor: scheme.onSurface.withValues(alpha: .18),
    ),
  );
}

/// Popovers and menus that float over the video: dark and neutral in either
/// theme, with white for the selection instead of the mint accent.
const overlaySurface = Color(0xf21e2229);

ThemeData overlayTheme() {
  final base = appTheme(true);
  final scheme = base.colorScheme.copyWith(
    primary: Colors.white,
    onPrimary: const Color(0xff15181d),
    surface: overlaySurface,
    onSurface: Colors.white,
    onSurfaceVariant: Colors.white70,
    surfaceContainerLow: Colors.white.withValues(alpha: .08),
    surfaceContainerHigh: Colors.white.withValues(alpha: .12),
    outlineVariant: Colors.white24,
  );
  return base.copyWith(
    colorScheme: scheme,
    sliderTheme: base.sliderTheme.copyWith(
      trackHeight: 3,
      activeTrackColor: Colors.white,
      inactiveTrackColor: Colors.white24,
      thumbColor: Colors.white,
      overlayColor: Colors.white12,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
      showValueIndicator: ShowValueIndicator.never,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? const Color(0xff15181d)
            : Colors.white70,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.white
            : Colors.white12,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    menuTheme: const MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(overlaySurface),
        surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
        padding: WidgetStatePropertyAll(EdgeInsets.all(6)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: controlBorderRadius),
        ),
        elevation: WidgetStatePropertyAll(8),
      ),
    ),
  );
}

import 'package:flutter/material.dart';

import '../core/overlay_glass.dart';

/// Player tweaks on top of the shell theme; the side panel follows the app's
/// light or dark theme.
ThemeData playerTheme(ThemeData base) {
  final scheme = base.colorScheme;
  return base.copyWith(
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

/// Outlined buttons on the dark overlay: a faint fill with a light edge.
final overlayOutlinedButtonStyle = OutlinedButton.styleFrom(
  foregroundColor: Colors.white,
  backgroundColor: overlayFill,
  side: const BorderSide(color: overlayOutline),
);

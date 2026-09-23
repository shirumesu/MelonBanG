import 'package:flutter/material.dart';

import '../core/theme.dart';

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
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        side: const WidgetStatePropertyAll(BorderSide.none),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.onSurfaceVariant,
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary.withValues(alpha: .14)
              : scheme.surfaceContainerLow,
        ),
      ),
    ),
  );
}

enum PlayerMenu { audio, danmaku, subtitles }

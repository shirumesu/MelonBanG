import 'dart:ui' show ImageFilter;

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
/// theme, with white for the selection instead of the mint accent. Pure black
/// like the control bar's gradient; a blue-grey reads as a foreign card.
const overlaySurface = Color(0xe6121315);

/// The tint of [OverlayGlass], lighter because the blur already mutes the
/// picture behind it.
const _glassTint = Color(0x9e121315);

/// The surface of popovers over the video: a blurred, dark glass through
/// which the picture still shows, with a hairline edge instead of a shadow.
/// [visibility] fades it in; an [Opacity] around a backdrop blur would blur
/// nothing on some renderers, so the fade happens inside.
class OverlayGlass extends StatelessWidget {
  const OverlayGlass({
    super.key,
    required this.child,
    this.borderRadius = controlBorderRadius,
    this.visibility = 1,
  });
  final Widget child;
  final BorderRadius borderRadius;
  final double visibility;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: borderRadius,
    child: BackdropFilter(
      filter: ImageFilter.blur(
        sigmaX: 20 * visibility,
        sigmaY: 20 * visibility,
      ),
      child: Opacity(
        opacity: visibility,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _glassTint,
            borderRadius: borderRadius,
            border: Border.all(color: Colors.white.withValues(alpha: .1)),
          ),
          child: Material(type: MaterialType.transparency, child: child),
        ),
      ),
    ),
  );
}

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
  );
}

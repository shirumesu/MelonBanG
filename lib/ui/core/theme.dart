import 'package:flutter/material.dart';

const mint = Color(0xff22b388);
const coral = Color(0xffff6b81);
const gold = Color(0xffffb83d);
const sky = Color(0xff8bbcf6);
const grape = Color(0xffb6a4f0);

ThemeData appTheme(bool dark) {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: mint,
        brightness: dark ? Brightness.dark : Brightness.light,
      ).copyWith(
        primary: mint,
        onPrimary: Colors.white,
        secondary: coral,
        surface: dark ? const Color(0xff1e2430) : Colors.white,
        surfaceContainerLowest: dark ? const Color(0xff151922) : Colors.white,
        surfaceContainerLow: dark
            ? const Color(0xff262d3a)
            : const Color(0xfff7f8fa),
        surfaceContainer: dark
            ? const Color(0xff262d3a)
            : const Color(0xfff4f5f7),
        surfaceContainerHigh: dark
            ? const Color(0xff2b3442)
            : const Color(0xffeef0f4),
        surfaceContainerHighest: dark
            ? const Color(0xff354052)
            : const Color(0xffe5e7ec),
        onSurface: dark ? const Color(0xffe7eef1) : const Color(0xff243239),
        onSurfaceVariant: dark
            ? const Color(0xffa0afb9)
            : const Color(0xff84919a),
        outlineVariant: dark
            ? const Color(0xff354052)
            : const Color(0xffe5e7ec),
      );
  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: scheme.outlineVariant),
  );
  final theme = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark
        ? scheme.surfaceContainerLowest
        : scheme.surfaceContainer,
    fontFamily: 'Microsoft YaHei UI',
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 24,
    ),
    cardTheme: CardThemeData(
      margin: EdgeInsets.zero,
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: .12),
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: scheme.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(
        borderSide: BorderSide(color: scheme.primary),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        shape: const StadiumBorder(),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.onSurface,
        backgroundColor: scheme.surface,
        side: BorderSide(color: scheme.outlineVariant),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surface,
      selectedColor: mint.withValues(alpha: .18),
      side: BorderSide(color: scheme.outlineVariant),
      shape: const StadiumBorder(),
      labelStyle: TextStyle(
        fontSize: 12,
        color: scheme.onSurface,
        fontWeight: FontWeight.w600,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      showCheckmark: false,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: mint,
      unselectedLabelColor: scheme.onSurface,
      dividerColor: scheme.outlineVariant,
    ),
  );
  final textTheme = theme.textTheme.apply(
    bodyColor: scheme.onSurface,
    displayColor: scheme.onSurface,
  );
  return theme.copyWith(
    badgeTheme: BadgeThemeData(
      largeSize: 24,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      textStyle: textTheme.bodyMedium!.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
    textTheme: textTheme.copyWith(
      titleMedium: textTheme.bodyMedium!.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w800,
      ),
      titleSmall: textTheme.bodyMedium!.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
      bodySmall: textTheme.bodyMedium!.copyWith(
        fontSize: 12,
        color: scheme.onSurfaceVariant,
      ),
    ),
  );
}

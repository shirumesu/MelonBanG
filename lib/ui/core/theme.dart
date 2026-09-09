import 'package:flutter/material.dart';

const mint = Color(0xff22b388);
const coral = Color(0xffff6b81);
const gold = Color(0xffffb83d);
const sky = Color(0xff8bbcf6);
const grape = Color(0xffb6a4f0);

const posterBorderRadius = BorderRadius.all(Radius.circular(14));
const panelBorderRadius = BorderRadius.all(Radius.circular(16));
const controlBorderRadius = BorderRadius.all(Radius.circular(12));
const badgeBorderRadius = BorderRadius.all(Radius.circular(8));
const navigationGradient = LinearGradient(
  colors: [Color(0xff65cfad), Color(0xff8bddbf)],
);

List<BoxShadow> posterShadows(BuildContext context) => [
  BoxShadow(
    color: Theme.of(context).shadowColor,
    blurRadius: 6,
    offset: const Offset(0, 2),
  ),
];

LinearGradient sidebarSurface(BuildContext context) => LinearGradient(
  colors: [
    Theme.of(context).colorScheme.surface,
    Theme.of(context).scaffoldBackgroundColor,
  ],
  stops: const [.82, 1],
);

ThemeData appTheme(bool dark) {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: mint,
        brightness: dark ? Brightness.dark : Brightness.light,
      ).copyWith(
        primary: dark ? const Color(0xff73d7b2) : const Color(0xff168364),
        onPrimary: dark ? const Color(0xff123a2a) : Colors.white,
        primaryContainer: dark
            ? const Color(0xff304f42)
            : const Color(0xffdef1e8),
        onPrimaryContainer: dark
            ? const Color(0xffcbefdc)
            : const Color(0xff164d39),
        secondary: coral,
        secondaryContainer: dark
            ? const Color(0xff483139)
            : const Color(0xfff8e5eb),
        onSecondaryContainer: dark
            ? const Color(0xffff8fa5)
            : const Color(0xffb54763),
        tertiary: dark ? const Color(0xffe0bd70) : const Color(0xffa57520),
        surface: dark ? const Color(0xff1e2430) : const Color(0xfffbfcfb),
        surfaceContainerLowest: dark
            ? const Color(0xff151922)
            : const Color(0xfffbfcfb),
        surfaceContainerLow: dark
            ? const Color(0xff262d3a)
            : const Color(0xfff6f8f6),
        surfaceContainer: dark
            ? const Color(0xff262d3a)
            : const Color(0xfff3f5f4),
        surfaceContainerHigh: dark
            ? const Color(0xff2b3442)
            : const Color(0xffeaf0ec),
        surfaceContainerHighest: dark
            ? const Color(0xff354052)
            : const Color(0xffdce3df),
        onSurface: dark ? const Color(0xffe7eef1) : const Color(0xff263833),
        onSurfaceVariant: dark
            ? const Color(0xffa0afb9)
            : const Color(0xff6f7d78),
        outlineVariant: dark
            ? const Color(0xff354052)
            : const Color(0xffe1e8e3),
      );
  final inputBorder = OutlineInputBorder(
    borderRadius: posterBorderRadius,
    borderSide: BorderSide.none,
  );
  final theme = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark
        ? scheme.surfaceContainerLowest
        : scheme.surfaceContainer,
    fontFamily: 'Microsoft YaHei UI',
    shadowColor: const Color(0xff203b30).withValues(alpha: dark ? .16 : .06),
    hoverColor: scheme.primary.withValues(alpha: .05),
    focusColor: scheme.primary.withValues(alpha: .12),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: panelBorderRadius),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 24,
    ),
    cardTheme: CardThemeData(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: panelBorderRadius),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: dark ? .3 : .16),
      shape: const RoundedRectangleBorder(borderRadius: controlBorderRadius),
    ),
    listTileTheme: ListTileThemeData(
      shape: const RoundedRectangleBorder(borderRadius: controlBorderRadius),
      selectedColor: scheme.primary,
      selectedTileColor: scheme.primaryContainer,
      iconColor: scheme.onSurfaceVariant,
    ),
    switchTheme: const SwitchThemeData(
      trackOutlineColor: WidgetStatePropertyAll(Colors.transparent),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: scheme.surfaceContainerHigh,
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
        minimumSize: const Size(64, 40),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        shape: const RoundedRectangleBorder(borderRadius: controlBorderRadius),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.onSurface,
        backgroundColor: scheme.surface,
        side: BorderSide(color: scheme.outlineVariant),
        shape: const RoundedRectangleBorder(borderRadius: controlBorderRadius),
        minimumSize: const Size(64, 40),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: const RoundedRectangleBorder(borderRadius: controlBorderRadius),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surface,
      selectedColor: scheme.primaryContainer,
      side: BorderSide.none,
      shape: const RoundedRectangleBorder(borderRadius: badgeBorderRadius),
      labelStyle: TextStyle(
        fontSize: 12,
        color: scheme.onSurface,
        fontWeight: FontWeight.w600,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      showCheckmark: false,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: scheme.primary,
      unselectedLabelColor: scheme.onSurface,
      dividerColor: Colors.transparent,
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

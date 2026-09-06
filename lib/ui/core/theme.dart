import 'package:flutter/material.dart';

const mint = Color(0xff22b388);

ThemeData appTheme(bool dark) {
  final scheme = ColorScheme.fromSeed(
    seedColor: mint,
    brightness: dark ? Brightness.dark : Brightness.light,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme.copyWith(primary: mint),
    scaffoldBackgroundColor: dark
        ? const Color(0xff172322)
        : const Color(0xffeef3f1),
    fontFamily: 'Microsoft YaHei UI',
    cardTheme: CardThemeData(
      elevation: 0,
      color: dark ? const Color(0xff21312e) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xff21312e) : Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    ),
  );
}

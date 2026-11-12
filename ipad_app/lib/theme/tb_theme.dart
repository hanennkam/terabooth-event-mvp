import 'package:flutter/material.dart';

abstract final class TbColors {
  static const ink = Color(0xFF0D0E11);
  static const surface = Color(0xFF17191F);
  static const surfaceRaised = Color(0xFF20232B);
  static const line = Color(0xFF30343E);
  static const cream = Color(0xFFF5EFE4);
  static const muted = Color(0xFFA6A8B0);
  static const gold = Color(0xFFE8B45A);
  static const rose = Color(0xFFE06A8B);
  static const mint = Color(0xFF63C9A2);
  static const red = Color(0xFFFF7D7D);
  static const blue = Color(0xFF7FB5FF);
}

abstract final class TbSpace {
  static const xs = 6.0;
  static const sm = 10.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
}

abstract final class TbRadius {
  static const sm = 12.0;
  static const md = 18.0;
  static const lg = 28.0;
}

ThemeData tbTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  final scheme =
      ColorScheme.fromSeed(
        seedColor: TbColors.gold,
        brightness: Brightness.dark,
      ).copyWith(
        primary: TbColors.gold,
        onPrimary: TbColors.ink,
        secondary: TbColors.rose,
        surface: TbColors.surface,
        onSurface: TbColors.cream,
        error: TbColors.red,
        outline: TbColors.line,
      );
  final text = base.textTheme.copyWith(
    displayLarge: base.textTheme.displayLarge?.copyWith(
      fontSize: 62,
      fontWeight: FontWeight.w800,
      letterSpacing: -2.0,
      height: 0.98,
      color: TbColors.cream,
    ),
    displayMedium: base.textTheme.displayMedium?.copyWith(
      fontSize: 46,
      fontWeight: FontWeight.w800,
      letterSpacing: -1.4,
      height: 1.0,
      color: TbColors.cream,
    ),
    displaySmall: base.textTheme.displaySmall?.copyWith(
      fontSize: 36,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.8,
      color: TbColors.cream,
    ),
    headlineLarge: base.textTheme.headlineLarge?.copyWith(
      fontSize: 30,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.4,
      color: TbColors.cream,
    ),
    headlineMedium: base.textTheme.headlineMedium?.copyWith(
      fontSize: 24,
      fontWeight: FontWeight.w700,
      color: TbColors.cream,
    ),
    titleLarge: base.textTheme.titleLarge?.copyWith(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: TbColors.cream,
    ),
    titleMedium: base.textTheme.titleMedium?.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: TbColors.cream,
    ),
    bodyLarge: base.textTheme.bodyLarge?.copyWith(
      fontSize: 16,
      height: 1.45,
      color: TbColors.cream,
    ),
    bodyMedium: base.textTheme.bodyMedium?.copyWith(
      fontSize: 14,
      height: 1.4,
      color: TbColors.muted,
    ),
    labelLarge: base.textTheme.labelLarge?.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.6,
    ),
  );
  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(TbRadius.sm),
    borderSide: const BorderSide(color: TbColors.line),
  );
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: TbColors.ink,
    textTheme: text,
    dividerColor: TbColors.line,
    iconTheme: const IconThemeData(color: TbColors.cream),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: TbColors.surfaceRaised,
      hintStyle: const TextStyle(color: TbColors.muted),
      labelStyle: const TextStyle(color: TbColors.muted),
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(
        borderSide: const BorderSide(color: TbColors.gold, width: 1.4),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: TbColors.gold,
        foregroundColor: TbColors.ink,
        disabledBackgroundColor: TbColors.surfaceRaised,
        disabledForegroundColor: TbColors.muted,
        minimumSize: const Size(0, 58),
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TbRadius.md),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: TbColors.cream,
        minimumSize: const Size(0, 54),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        side: const BorderSide(color: TbColors.line),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TbRadius.md),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: TbColors.gold,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: TbColors.surfaceRaised,
      contentTextStyle: TextStyle(color: TbColors.cream),
      behavior: SnackBarBehavior.floating,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: TbColors.gold,
      linearTrackColor: TbColors.surfaceRaised,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: TbColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(TbRadius.lg),
      ),
      titleTextStyle: text.headlineMedium,
      contentTextStyle: text.bodyMedium,
    ),
  );
}

// lib/core/theme/app_theme.dart
library;

import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  // ── Brand Colours ──────────────────────────────────────────────────────────
  static const Color primaryTeal        = Color(0xFF00897B);
  static const Color primaryTealLight   = Color(0xFF4DB6AC);
  static const Color primaryTealDark    = Color(0xFF00695C);
  static const Color primaryTealSurface = Color(0xFFE0F2F1);

  static const Color secondaryAmber     = Color(0xFFFFB300);
  static const Color secondaryAmberDark = Color(0xFFFF8F00);

  static const Color errorRed           = Color(0xFFE53935);
  static const Color successGreen       = Color(0xFF43A047);
  static const Color warningOrange      = Color(0xFFFB8C00);

  // ── Fee Status Colours ─────────────────────────────────────────────────────
  static const Color statusPending = Color(0xFFFFB300);
  static const Color statusOverdue = Color(0xFFE53935);
  static const Color statusPaid    = Color(0xFF43A047);

  // ── Light Theme ────────────────────────────────────────────────────────────
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3:             true,
      colorScheme:              _lightColorScheme,
      fontFamily:               'Inter',
      textTheme:                _textTheme,
      appBarTheme:              _lightAppBarTheme,
      cardTheme:                _lightCardTheme,
      inputDecorationTheme:     _lightInputTheme,
      elevatedButtonTheme:      _elevatedButtonTheme,
      outlinedButtonTheme:      _outlinedButtonTheme,
      textButtonTheme:          _textButtonTheme,
      bottomNavigationBarTheme: _lightBottomNavTheme,
      chipTheme:                _chipTheme,
      scaffoldBackgroundColor:  const Color(0xFFF5F7FA),
      dividerTheme: const DividerThemeData(
        color:     Color(0xFFE0E0E0),
        thickness: 1,
        space:     1,
      ),
    );
  }

  // ── Dark Theme ─────────────────────────────────────────────────────────────
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3:             true,
      colorScheme:              _darkColorScheme,
      fontFamily:               'Inter',
      textTheme:                _textTheme.apply(
        bodyColor:    const Color(0xFFECEFF1),
        displayColor: const Color(0xFFECEFF1),
      ),
      scaffoldBackgroundColor:  const Color(0xFF0F1923),
      appBarTheme:              _darkAppBarTheme,
      cardTheme:                _darkCardTheme,
      inputDecorationTheme:     _darkInputTheme,
      elevatedButtonTheme:      _elevatedButtonTheme,
      outlinedButtonTheme:      _outlinedButtonTheme,
      textButtonTheme:          _textButtonTheme,
      bottomNavigationBarTheme: _darkBottomNavTheme,
      chipTheme:                _darkChipTheme,
      dividerTheme: const DividerThemeData(
        color:     Color(0xFF2A3A4A),
        thickness: 1,
        space:     1,
      ),
    );
  }

  // ── Light Colour Scheme ────────────────────────────────────────────────────
  static const ColorScheme _lightColorScheme = ColorScheme(
    brightness:              Brightness.light,
    primary:                 primaryTeal,
    onPrimary:               Colors.white,
    primaryContainer:        primaryTealSurface,
    onPrimaryContainer:      primaryTealDark,
    secondary:               secondaryAmber,
    onSecondary:             Colors.white,
    secondaryContainer:      Color(0xFFFFF8E1),
    onSecondaryContainer:    Color(0xFF7B5000),
    error:                   errorRed,
    onError:                 Colors.white,
    errorContainer:          Color(0xFFFFEBEE),
    onErrorContainer:        Color(0xFFB71C1C),
    surface:                 Colors.white,
    onSurface:               Color(0xFF1A2332),
    surfaceContainerHighest: Color(0xFFF0F4F8),
    outline:                 Color(0xFFCFD8DC),
    outlineVariant:          Color(0xFFECEFF1),
    shadow:                  Colors.black,
    scrim:                   Colors.black,
    inverseSurface:          Color(0xFF1A2332),
    onInverseSurface:        Colors.white,
    inversePrimary:          primaryTealLight,
  );

  // ── Dark Colour Scheme ─────────────────────────────────────────────────────
  static const ColorScheme _darkColorScheme = ColorScheme(
    brightness:              Brightness.dark,
    primary:                 primaryTealLight,
    onPrimary:               Color(0xFF003D36),
    primaryContainer:        primaryTealDark,
    onPrimaryContainer:      Color(0xFFB2DFDB),
    secondary:               secondaryAmber,
    onSecondary:             Color(0xFF3E2800),
    secondaryContainer:      Color(0xFF7B5000),
    onSecondaryContainer:    Color(0xFFFFF8E1),
    error:                   Color(0xFFEF9A9A),
    onError:                 Color(0xFF7F0000),
    errorContainer:          Color(0xFFB71C1C),
    onErrorContainer:        Color(0xFFFFEBEE),
    surface:                 Color(0xFF182030),
    onSurface:               Color(0xFFECEFF1),
    surfaceContainerHighest: Color(0xFF1E2D3D),
    outline:                 Color(0xFF37474F),
    outlineVariant:          Color(0xFF263238),
    shadow:                  Colors.black,
    scrim:                   Colors.black,
    inverseSurface:          Color(0xFFECEFF1),
    onInverseSurface:        Color(0xFF1A2332),
    inversePrimary:          primaryTeal,
  );

  // ── Typography ─────────────────────────────────────────────────────────────
  static final TextTheme _textTheme = TextTheme(
    displayLarge:   _ts(57, FontWeight.w400),
    displayMedium:  _ts(45, FontWeight.w400),
    displaySmall:   _ts(36, FontWeight.w400),
    headlineLarge:  _ts(32, FontWeight.w700),
    headlineMedium: _ts(28, FontWeight.w600),
    headlineSmall:  _ts(24, FontWeight.w600),
    titleLarge:     _ts(22, FontWeight.w600),
    titleMedium:    _ts(16, FontWeight.w600),
    titleSmall:     _ts(14, FontWeight.w600),
    bodyLarge:      _ts(16, FontWeight.w400),
    bodyMedium:     _ts(14, FontWeight.w400),
    bodySmall:      _ts(12, FontWeight.w400),
    labelLarge:     _ts(14, FontWeight.w500),
    labelMedium:    _ts(12, FontWeight.w500),
    labelSmall:     _ts(11, FontWeight.w500),
  );

  static TextStyle _ts(double size, FontWeight weight) => TextStyle(
    fontFamily:    'Inter',
    fontSize:      size,
    fontWeight:    weight,
    letterSpacing: size > 20 ? -0.5 : 0,
  );

  // ── AppBar Themes ──────────────────────────────────────────────────────────
  static const AppBarTheme _lightAppBarTheme = AppBarTheme(
    elevation:              0,
    scrolledUnderElevation: 0.5,
    centerTitle:            false,
    backgroundColor:        Colors.white,
    foregroundColor:        Color(0xFF1A2332),
    surfaceTintColor:       Colors.transparent,
    titleTextStyle: TextStyle(
      fontFamily: 'Inter',
      fontSize:   18,
      fontWeight: FontWeight.w700,
      color:      Color(0xFF1A2332),
    ),
  );

  static const AppBarTheme _darkAppBarTheme = AppBarTheme(
    elevation:              0,
    scrolledUnderElevation: 0.5,
    centerTitle:            false,
    backgroundColor:        Color(0xFF182030),
    foregroundColor:        Color(0xFFECEFF1),
    surfaceTintColor:       Colors.transparent,
    titleTextStyle: TextStyle(
      fontFamily: 'Inter',
      fontSize:   18,
      fontWeight: FontWeight.w700,
      color:      Color(0xFFECEFF1),
    ),
  );

  // ── Card Themes ────────────────────────────────────────────────────────────
  static final CardThemeData _lightCardTheme = CardThemeData(
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: Color(0xFFECEFF1), width: 1),
    ),
    color:  Colors.white,
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
  );

  static final CardThemeData _darkCardTheme = CardThemeData(
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: Color(0xFF263238), width: 1),
    ),
    color:  const Color(0xFF1E2D3D),
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
  );

  // ── Input Themes ───────────────────────────────────────────────────────────
  static final InputDecorationTheme _lightInputTheme = InputDecorationTheme(
    filled:    true,
    fillColor: const Color(0xFFF5F7FA),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide:   const BorderSide(color: Color(0xFFCFD8DC)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide:   const BorderSide(color: Color(0xFFCFD8DC)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide:   const BorderSide(color: primaryTeal, width: 2),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide:   const BorderSide(color: errorRed),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide:   const BorderSide(color: errorRed, width: 2),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    labelStyle: const TextStyle(
      fontFamily: 'Inter',
      fontSize:   14,
      color:      Color(0xFF607D8B),
    ),
    hintStyle: const TextStyle(
      fontFamily: 'Inter',
      fontSize:   14,
      color:      Color(0xFF90A4AE),
    ),
  );

  static final InputDecorationTheme _darkInputTheme = InputDecorationTheme(
    filled:    true,
    fillColor: const Color(0xFF1E2D3D),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide:   const BorderSide(color: Color(0xFF37474F)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide:   const BorderSide(color: Color(0xFF37474F)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide:   const BorderSide(color: primaryTealLight, width: 2),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide:   const BorderSide(color: Color(0xFFEF9A9A)),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide:   const BorderSide(color: Color(0xFFEF9A9A), width: 2),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    labelStyle: const TextStyle(
      fontFamily: 'Inter',
      fontSize:   14,
      color:      Color(0xFF90A4AE),
    ),
    hintStyle: const TextStyle(
      fontFamily: 'Inter',
      fontSize:   14,
      color:      Color(0xFF607D8B),
    ),
  );

  // ── Button Themes ──────────────────────────────────────────────────────────
  static final ElevatedButtonThemeData _elevatedButtonTheme =
      ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: primaryTeal,
      foregroundColor: Colors.white,
      minimumSize:     const Size(double.infinity, 52),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      textStyle: const TextStyle(
        fontFamily: 'Inter',
        fontSize:   15,
        fontWeight: FontWeight.w600,
      ),
      elevation: 0,
    ),
  );

  static final OutlinedButtonThemeData _outlinedButtonTheme =
      OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: primaryTeal,
      minimumSize:     const Size(double.infinity, 52),
      side:            const BorderSide(color: primaryTeal, width: 1.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      textStyle: const TextStyle(
        fontFamily: 'Inter',
        fontSize:   15,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  static final TextButtonThemeData _textButtonTheme = TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: primaryTeal,
      textStyle: const TextStyle(
        fontFamily: 'Inter',
        fontSize:   14,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  // ── Bottom Nav Themes ──────────────────────────────────────────────────────
  // ✅ Light — high contrast on white background
  static const BottomNavigationBarThemeData _lightBottomNavTheme =
      BottomNavigationBarThemeData(
    type:                BottomNavigationBarType.fixed,
    selectedItemColor:   primaryTeal,
    unselectedItemColor: Color(0xFF546E7A), // Blue Grey 600 — clearly visible
    backgroundColor:     Colors.white,
    elevation:           0,
    selectedLabelStyle: TextStyle(
      fontFamily: 'Inter',
      fontSize:   11,
      fontWeight: FontWeight.w700,
    ),
    unselectedLabelStyle: TextStyle(
      fontFamily: 'Inter',
      fontSize:   11,
      fontWeight: FontWeight.w500,
    ),
  );

  // ✅ Dark — high contrast on dark background
  static const BottomNavigationBarThemeData _darkBottomNavTheme =
      BottomNavigationBarThemeData(
    type:                BottomNavigationBarType.fixed,
    selectedItemColor:   primaryTealLight,
    unselectedItemColor: Color(0xFFB0BEC5), // Blue Grey 200 — clearly visible
    backgroundColor:     Color(0xFF182030),
    elevation:           0,
    selectedLabelStyle: TextStyle(
      fontFamily: 'Inter',
      fontSize:   11,
      fontWeight: FontWeight.w700,
    ),
    unselectedLabelStyle: TextStyle(
      fontFamily: 'Inter',
      fontSize:   11,
      fontWeight: FontWeight.w500,
    ),
  );

  // ── Chip Themes ────────────────────────────────────────────────────────────
  static final ChipThemeData _chipTheme = ChipThemeData(
    backgroundColor: const Color(0xFFECEFF1),
    selectedColor:   primaryTealSurface,
    labelStyle: const TextStyle(
      fontFamily: 'Inter',
      fontSize:   12,
      fontWeight: FontWeight.w500,
      color:      Color(0xFF37474F),
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
  );

  static final ChipThemeData _darkChipTheme = ChipThemeData(
    backgroundColor: const Color(0xFF1E2D3D),
    selectedColor:   primaryTealDark,
    labelStyle: const TextStyle(
      fontFamily: 'Inter',
      fontSize:   12,
      fontWeight: FontWeight.w500,
      color:      Color(0xFFB0BEC5),
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
  );

  // ── Fee Status Helpers ─────────────────────────────────────────────────────
  static Color feeStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'paid':    return statusPaid;
      case 'overdue': return statusOverdue;
      default:        return statusPending;
    }
  }

  static Color feeStatusBackground(String status) {
    switch (status.toLowerCase()) {
      case 'paid':    return const Color(0xFFE8F5E9);
      case 'overdue': return const Color(0xFFFFEBEE);
      default:        return const Color(0xFFFFF8E1);
    }
  }
}
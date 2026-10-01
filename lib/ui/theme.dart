import 'package:flutter/material.dart';

/// PAVEX red, the brand colour of the client and management portals: `oklch(0.55 0.22 27)` in
/// light mode, a lighter `oklch(0.66 0.2 27)` on dark backgrounds.
const pavexRed = Color(0xFFD40C1A);
const pavexRedOnDark = Color(0xFFF45249);

/// The portals' amber accent (`--brand-accent`), used sparingly for money to collect and warnings.
const pavexAmber = Color(0xFFF9AD26);
const successGreen = Color(0xFF15803D);
const warningAmber = Color(0xFFB45309);

/// Neutral greys from the portals' tokens, so the app reads as the same product: red marks
/// actions and status, while backgrounds and cards stay grey rather than tinted red.
class _Palette {
  const _Palette({
    required this.primary,
    required this.background,
    required this.card,
    required this.foreground,
    required this.muted,
    required this.border,
    required this.subtle,
  });

  final Color primary;
  final Color background;
  final Color card;
  final Color foreground;
  final Color muted;
  final Color border;
  final Color subtle;

  static const light = _Palette(
    primary: pavexRed,
    background: Color(0xFFF4F5F7),
    card: Color(0xFFFFFFFF),
    foreground: Color(0xFF171B20),
    muted: Color(0xFF5F646B),
    border: Color(0xFFE1E3E7),
    subtle: Color(0xFFEEF0F3),
  );

  static const dark = _Palette(
    primary: pavexRedOnDark,
    background: Color(0xFF0D1013),
    card: Color(0xFF16181D),
    foreground: Color(0xFFF0F2F4),
    muted: Color(0xFFA0A5AC),
    border: Color(0xFF2A2E35),
    subtle: Color(0xFF1E2127),
  );
}

ThemeData pavexTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final palette = dark ? _Palette.dark : _Palette.light;
  final scheme = ColorScheme.fromSeed(seedColor: pavexRed, brightness: brightness).copyWith(
    primary: palette.primary,
    onPrimary: Colors.white,
    primaryContainer: palette.primary.withValues(alpha: dark ? 0.22 : 0.1),
    onPrimaryContainer: palette.primary,
    secondary: pavexAmber,
    onSecondary: const Color(0xFF3A2405),
    surface: palette.card,
    onSurface: palette.foreground,
    onSurfaceVariant: palette.muted,
    surfaceTint: Colors.transparent,
    surfaceContainerLowest: palette.card,
    surfaceContainerLow: palette.card,
    surfaceContainer: palette.subtle,
    surfaceContainerHigh: palette.subtle,
    surfaceContainerHighest: palette.subtle,
    outline: palette.muted,
    outlineVariant: palette.border,
    error: palette.primary,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: brightness);
  return base.copyWith(
    scaffoldBackgroundColor: palette.background,
    dividerColor: palette.border,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: palette.card,
      foregroundColor: palette.foreground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      shape: Border(bottom: BorderSide(color: palette.border)),
      titleTextStyle: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: palette.foreground),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: palette.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: palette.border)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: palette.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.foreground,
        side: BorderSide(color: palette.border),
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: palette.primary)),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.card,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: palette.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: palette.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: palette.primary, width: 1.5)),
    ),
    chipTheme: base.chipTheme.copyWith(
      selectedColor: palette.primary.withValues(alpha: dark ? 0.22 : 0.1),
      side: BorderSide(color: palette.border),
      labelStyle: TextStyle(color: palette.foreground, fontWeight: FontWeight.w600),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? Colors.white : null),
      trackColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? palette.primary : null),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: palette.card,
      surfaceTintColor: Colors.transparent,
      indicatorColor: palette.primary.withValues(alpha: dark ? 0.22 : 0.1),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(color: states.contains(WidgetState.selected) ? palette.primary : palette.muted),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
          color: states.contains(WidgetState.selected) ? palette.primary : palette.muted,
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: dark ? palette.subtle : palette.foreground,
      contentTextStyle: TextStyle(color: dark ? palette.foreground : Colors.white),
    ),
  );
}

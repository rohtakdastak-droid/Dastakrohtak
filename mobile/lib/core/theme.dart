import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers.dart';

const brandBlue = Color(0xFF0EA5E9);
const brandDeep = Color(0xFF0369A1);
const success = Color(0xFF059669);
const warning = Color(0xFFD97706);
const danger = Color(0xFFDC2626);

class ThemeController extends StateNotifier<ThemeMode> {
  final void Function(String) persist;
  ThemeController(super.initial, this.persist);
  void toggle(Brightness current) {
    state = current == Brightness.dark ? ThemeMode.light : ThemeMode.dark;
    persist(state.name);
  }
}

// Read synchronously from preferences before the first frame, so there is no theme flash.
final themeModeProvider =
    StateNotifierProvider<ThemeController, ThemeMode>((ref) {
  final prefs = ref.watch(preferencesProvider);
  final saved = prefs.getString('theme_mode');
  final initial = ThemeMode.values
      .firstWhere((m) => m.name == saved, orElse: () => ThemeMode.system);
  return ThemeController(
      initial, (value) => prefs.setString('theme_mode', value));
});

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
      seedColor: brandBlue,
      brightness: brightness,
      primary: dark ? const Color(0xFF38BDF8) : brandBlue,
      onPrimary: dark ? const Color(0xFF082F49) : Colors.white,
      secondary: const Color(0xFF10B981),
      error: const Color(0xFFEF4444),
      surface: dark ? const Color(0xFF0B1220) : Colors.white,
      onSurface: dark ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A));
  final ink = scheme.onSurface;
  final field = dark ? const Color(0xFF162032) : const Color(0xFFF8FAFC);
  final line = dark ? const Color(0xFF1E293B) : const Color(0xFFEEF2F6);
  return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
          backgroundColor: scheme.surface,
          foregroundColor: ink,
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 0,
          titleTextStyle: TextStyle(
              color: ink, fontWeight: FontWeight.w800, fontSize: 20)),
      textTheme: TextTheme(
          headlineLarge: TextStyle(
              color: ink,
              fontWeight: FontWeight.w800,
              fontSize: 30,
              height: 1.15),
          headlineMedium:
              TextStyle(color: ink, fontWeight: FontWeight.w800, fontSize: 24),
          titleLarge:
              TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: 18),
          titleMedium:
              TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: 15),
          bodyMedium: TextStyle(
              color: dark ? const Color(0xFFCBD5E1) : const Color(0xFF374151)),
          bodySmall: TextStyle(
              color: dark ? const Color(0xFF94A3B8) : const Color(0xFF6B7280))),
      inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: field,
          hintStyle: TextStyle(
              color: dark ? const Color(0xFF64748B) : const Color(0xFF9CA3AF)),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: scheme.primary, width: 1.5)),
          errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: scheme.error, width: 1.2))),
      cardTheme: CardThemeData(
          elevation: 0,
          color: dark ? const Color(0xFF111A2B) : Colors.white,
          surfaceTintColor: Colors.transparent,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: line))),
      dividerTheme: DividerThemeData(color: line),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              textStyle:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)))),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
              side: BorderSide(color: line, width: 1.4),
              foregroundColor: ink,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)))),
      chipTheme: ChipThemeData(
          side: BorderSide(color: line),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
      navigationBarTheme: NavigationBarThemeData(
          backgroundColor: scheme.surface,
          indicatorColor: scheme.primary.withValues(alpha: dark ? 0.25 : 0.14),
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          labelTextStyle: WidgetStatePropertyAll(
              TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: ink)),
          iconTheme: WidgetStatePropertyAll(IconThemeData(color: ink))));
}

extension ThemeX on BuildContext {
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
  bool get dark => Theme.of(this).brightness == Brightness.dark;
  Color get muted => Theme.of(this).textTheme.bodySmall!.color!;
  Color get tint =>
      Theme.of(this).colorScheme.primary.withValues(alpha: dark ? 0.18 : 0.10);
}

import 'package:flutter/material.dart';

/// Premium minimalist palette for Plamus (dark / light).
class PlamusColors {
  PlamusColors._();

  /// Default primary accent (deep purple) - can be overridden by user preference.
  static const Color primary = Color(0xFF7B2CBF);

  /// Dark scaffold background.
  static const Color darkBackground = Color(0xFF000000);

  /// Dark sidebar surface.
  static const Color darkSidebar = Color(0xFF0A0A0A);

  /// Dark theme primary text.
  static const Color darkText = Color(0xFFFFFFFF);

  /// Light scaffold background.
  static const Color lightBackground = Color(0xFFFFFFFF);

  /// Light sidebar surface.
  static const Color lightSidebar = Color(0xFFF5F5F5);

  /// Light theme primary text.
  static const Color lightText = Color(0xFF1A1A1A);
}

/// Builds [ThemeData] for the requested [ThemeMode] with dynamic accent color.
class PlamusTheme {
  PlamusTheme._();

  /// Dark Material 3 theme tuned for a music desktop app.
  static ThemeData dark({Color? accentColor}) {
    final accent = accentColor ?? PlamusColors.primary;
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        surface: PlamusColors.darkBackground,
        primary: accent,
        onPrimary: Colors.white,
        onSurface: PlamusColors.darkText,
      ),
      scaffoldBackgroundColor: PlamusColors.darkBackground,
    );
    return base.copyWith(
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: PlamusColors.darkSidebar,
        selectedIconTheme: IconThemeData(color: accent),
        selectedLabelTextStyle: const TextStyle(color: PlamusColors.darkText),
        unselectedLabelTextStyle: TextStyle(color: PlamusColors.darkText.withValues(alpha: 0.65)),
      ),
      listTileTheme: ListTileThemeData(
        textColor: PlamusColors.darkText,
        iconColor: PlamusColors.darkText.withValues(alpha: 0.85),
      ),
      dividerTheme: DividerThemeData(color: Colors.white.withValues(alpha: 0.08)),
      sliderTheme: SliderThemeData(
        trackHeight: 4,
        activeTrackColor: accent,
        inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
        thumbColor: accent,
        overlayColor: accent.withValues(alpha: 0.2),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
        trackShape: const RoundedRectSliderTrackShape(),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        ),
      ),
      dialogTheme: const DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(30))),
      ),
      cardTheme: const CardThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(30))),
        elevation: 0,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accent;
          return null;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accent.withValues(alpha: 0.5);
          return null;
        }),
      ),
    );
  }

  /// Light Material 3 theme.
  static ThemeData light({Color? accentColor}) {
    final accent = accentColor ?? PlamusColors.primary;
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.light(
        surface: PlamusColors.lightBackground,
        primary: accent,
        onPrimary: Colors.white,
        onSurface: PlamusColors.lightText,
      ),
      scaffoldBackgroundColor: PlamusColors.lightBackground,
    );
    return base.copyWith(
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: PlamusColors.lightSidebar,
        selectedIconTheme: IconThemeData(color: accent),
        selectedLabelTextStyle: const TextStyle(color: PlamusColors.lightText),
        unselectedLabelTextStyle: TextStyle(color: PlamusColors.lightText.withValues(alpha: 0.65)),
      ),
      listTileTheme: ListTileThemeData(
        textColor: PlamusColors.lightText,
        iconColor: PlamusColors.lightText.withValues(alpha: 0.85),
      ),
      dividerTheme: DividerThemeData(color: Colors.black.withValues(alpha: 0.06)),
      sliderTheme: SliderThemeData(
        trackHeight: 4,
        activeTrackColor: accent,
        inactiveTrackColor: Colors.black.withValues(alpha: 0.1),
        thumbColor: accent,
        overlayColor: accent.withValues(alpha: 0.2),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
        trackShape: const RoundedRectSliderTrackShape(),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        ),
      ),
      dialogTheme: const DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(30))),
      ),
      cardTheme: const CardThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(30))),
        elevation: 0,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accent;
          return null;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accent.withValues(alpha: 0.5);
          return null;
        }),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Drives light/dark switching and accent color customization for the whole app via [Provider].
class ThemeController extends ChangeNotifier {
  /// Default signature deep purple.
  static const Color defaultAccentColor = Color(0xFF7B2CBF);

  /// Starts in dark mode (default listening experience).
  ThemeMode _mode = ThemeMode.dark;

  /// Current accent color (defaults to signature purple).
  Color _accentColor = defaultAccentColor;

  ThemeController() {
    _loadPreferences();
  }

  /// Current Flutter [ThemeMode].
  ThemeMode get mode => _mode;

  /// True when using the dark palette.
  bool get isDark => _mode == ThemeMode.dark;

  /// Current accent color.
  Color get accentColor => _accentColor;

  /// Load saved preferences from shared_preferences.
  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isDarkMode = prefs.getBool('isDarkMode') ?? true;
      _mode = isDarkMode ? ThemeMode.dark : ThemeMode.light;

      final colorValue = prefs.getInt('accentColor');
      if (colorValue != null) {
        _accentColor = Color(colorValue);
      }
      notifyListeners();
    } catch (e) {
      // Ignore errors, use defaults
    }
  }

  /// Toggles between light and dark.
  Future<void> toggle() async {
    _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isDarkMode', isDark);
    } catch (e) {
      // Ignore save errors
    }
  }

  /// Sets an explicit mode.
  Future<void> setMode(ThemeMode mode) async {
    _mode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isDarkMode', isDark);
    } catch (e) {
      // Ignore save errors
    }
  }

  /// Sets a custom accent color and persists it.
  Future<void> setAccentColor(Color color) async {
    _accentColor = color;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('accentColor', color.value & 0xFFFFFFFF);
    } catch (e) {
      // Ignore save errors
    }
  }

  /// Resets accent color to default purple.
  Future<void> resetAccentColor() async {
    _accentColor = defaultAccentColor;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('accentColor');
    } catch (e) {
      // Ignore save errors
    }
  }
}

// lib/theme_helper.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';
import 'neu_theme.dart';

// ─── SharedPreferences keys ───────────────────────────────────────────────────
const _kDarkMode     = 'settings_dark_mode';
const _kAppTheme     = 'settings_app_theme';
const _kVisualTheme  = 'settings_visual_theme';

class ThemeHelper {
  static Color getThemeColor(ColorTheme theme, {bool isDarkMode = false}) {
    if (isDarkMode) {
      return switch (theme) {
        ColorTheme.default_ => Colors.teal.shade700.withValues(alpha: 0.3),
        ColorTheme.sunset   => Colors.orange.shade700.withValues(alpha: 0.3),
        ColorTheme.orange   => Colors.orange.shade600.withValues(alpha: 0.3),
        ColorTheme.forest   => Colors.green.shade700.withValues(alpha: 0.3),
        ColorTheme.lavender => Colors.purple.shade700.withValues(alpha: 0.3),
        ColorTheme.rose     => Colors.pink.shade700.withValues(alpha: 0.3),
      };
    }
    return switch (theme) {
      ColorTheme.default_ => Colors.teal.shade100,
      ColorTheme.sunset   => Colors.orange.shade200,
      ColorTheme.orange   => Colors.orange.shade300,
      ColorTheme.forest   => Colors.green.shade200,
      ColorTheme.lavender => Colors.purple.shade200,
      ColorTheme.rose     => Colors.pink.shade200,
    };
  }

  static Color getTextColorForBackground(Color bg) =>
      bg.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;

  static Color getSecondaryTextColorForBackground(Color bg) =>
      bg.computeLuminance() > 0.5 ? Colors.black54 : Colors.white70;

  static String getThemeName(ColorTheme theme) => switch (theme) {
    ColorTheme.default_ => 'Default',
    ColorTheme.sunset   => 'Sunset',
    ColorTheme.orange   => 'Orange',
    ColorTheme.forest   => 'Forest',
    ColorTheme.lavender => 'Lavender',
    ColorTheme.rose     => 'Rose',
  };

  static Icon getNoteTypeIcon(NoteType type) => switch (type) {
    NoteType.normal    => const Icon(Icons.note_rounded, size: 14),
    NoteType.checklist => const Icon(Icons.check_box_rounded, size: 14),
    NoteType.itinerary => const Icon(Icons.flight_rounded, size: 14),
    NoteType.mealPlan  => const Icon(Icons.restaurant_menu_rounded, size: 14),
    NoteType.recipe    => const Icon(Icons.menu_book_rounded, size: 14),
  };
}

class AppSettingsProvider extends ChangeNotifier {
  AppTheme _appTheme           = AppTheme.teal;
  bool _isDarkMode             = false;
  AppVisualTheme _visualTheme  = AppVisualTheme.neumorphic;

  // Held after loadSettings() completes — used for synchronous writes.
  SharedPreferences? _prefs;

  AppTheme       get appTheme    => _appTheme;
  bool           get isDarkMode  => _isDarkMode;
  AppVisualTheme get visualTheme => _visualTheme;

  AppSettingsProvider() {
    // Sync the static Neu class with the default value immediately,
    // then overwrite once we have loaded persisted prefs.
    Neu.setTheme(_visualTheme);
    _loadSettings();
  }

  // ── Persistence ─────────────────────────────────────────────────────────────

  Future<void> _loadSettings() async {
    _prefs = await SharedPreferences.getInstance();

    // Dark mode
    _isDarkMode = _prefs!.getBool(_kDarkMode) ?? false;

    // App color theme
    final appThemeIdx = _prefs!.getInt(_kAppTheme) ?? AppTheme.teal.index;
    _appTheme = AppTheme.values[appThemeIdx.clamp(0, AppTheme.values.length - 1)];

    // Visual style theme
    final visualIdx = _prefs!.getInt(_kVisualTheme) ?? AppVisualTheme.neumorphic.index;
    _visualTheme = AppVisualTheme.values[visualIdx.clamp(0, AppVisualTheme.values.length - 1)];
    Neu.setTheme(_visualTheme);

    notifyListeners();
  }

  Future<void> _saveSettings() async {
    // _prefs is guaranteed non-null after _loadSettings() but may not be ready
    // on the very first frame; guard defensively.
    _prefs ??= await SharedPreferences.getInstance();
    await Future.wait([
      _prefs!.setBool(_kDarkMode,    _isDarkMode),
      _prefs!.setInt(_kAppTheme,     _appTheme.index),
      _prefs!.setInt(_kVisualTheme,  _visualTheme.index),
    ]);
  }

  // ── Public setters ───────────────────────────────────────────────────────────

  static Color seedColor(AppTheme theme) => switch (theme) {
    AppTheme.amber  => Colors.amber,
    AppTheme.teal   => Colors.teal,
    AppTheme.indigo => Colors.indigo,
    AppTheme.rose   => Colors.pink,
    AppTheme.slate  => Colors.blueGrey,
  };

  static String themeName(AppTheme theme) => switch (theme) {
    AppTheme.amber  => 'Amber',
    AppTheme.teal   => 'Teal',
    AppTheme.indigo => 'Indigo',
    AppTheme.rose   => 'Rose',
    AppTheme.slate  => 'Slate',
  };

  void setAppTheme(AppTheme theme) {
    _appTheme = theme;
    notifyListeners();
    _saveSettings();
  }

  void toggleDarkMode() {
    _isDarkMode = !_isDarkMode;
    notifyListeners();
    _saveSettings();
  }

  /// Switch visual theme. Neu.setTheme() propagates to all screens instantly.
  void setVisualTheme(AppVisualTheme theme) {
    _visualTheme = theme;
    Neu.setTheme(theme);
    notifyListeners();
    _saveSettings();
  }
}
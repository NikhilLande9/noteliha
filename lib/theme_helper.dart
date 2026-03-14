import 'package:flutter/material.dart';
import 'models.dart';

class ThemeHelper {
  static Color getThemeColor(ColorTheme theme, {bool isDarkMode = false}) {
    if (isDarkMode) {
      return switch (theme) {
        ColorTheme.default_ => Colors.teal.shade700,
        ColorTheme.sunset => Colors.orange.shade700,
        ColorTheme.orange => Colors.orange.shade600,
        ColorTheme.forest => Colors.green.shade700,
        ColorTheme.lavender => Colors.purple.shade700,
        ColorTheme.rose => Colors.pink.shade700,
      };
    }
    return switch (theme) {
      ColorTheme.default_ => Colors.teal.shade100,
      ColorTheme.sunset => Colors.orange.shade200,
      ColorTheme.orange => Colors.orange.shade300,
      ColorTheme.forest => Colors.green.shade200,
      ColorTheme.lavender => Colors.purple.shade200,
      ColorTheme.rose => Colors.pink.shade200,
    };
  }

  static Color getTextColorForBackground(Color bg) =>
      bg.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;

  static Color getSecondaryTextColorForBackground(Color bg) =>
      bg.computeLuminance() > 0.5 ? Colors.black54 : Colors.white70;

  static String getThemeName(ColorTheme theme) => switch (theme) {
        ColorTheme.default_ => 'Default',
        ColorTheme.sunset => 'Sunset',
        ColorTheme.orange => 'Orange',
        ColorTheme.forest => 'Forest',
        ColorTheme.lavender => 'Lavender',
        ColorTheme.rose => 'Rose',
      };

  static Icon getNoteTypeIcon(NoteType type) => switch (type) {
        NoteType.normal => const Icon(Icons.note_rounded, size: 14),
        NoteType.checklist => const Icon(Icons.check_box_rounded, size: 14),
        NoteType.itinerary => const Icon(Icons.flight_rounded, size: 14),
        NoteType.mealPlan =>
          const Icon(Icons.restaurant_menu_rounded, size: 14),
        NoteType.recipe => const Icon(Icons.menu_book_rounded, size: 14),
      };
}

class AppSettingsProvider extends ChangeNotifier {
  AppTheme _appTheme = AppTheme.teal;
  bool _isDarkMode = false;

  AppTheme get appTheme => _appTheme;
  bool get isDarkMode => _isDarkMode;

  static Color seedColor(AppTheme theme) => switch (theme) {
        AppTheme.amber => Colors.amber,
        AppTheme.teal => Colors.teal,
        AppTheme.indigo => Colors.indigo,
        AppTheme.rose => Colors.pink,
        AppTheme.slate => Colors.blueGrey,
      };

  static String themeName(AppTheme theme) => switch (theme) {
        AppTheme.amber => 'Amber',
        AppTheme.teal => 'Teal',
        AppTheme.indigo => 'Indigo',
        AppTheme.rose => 'Rose',
        AppTheme.slate => 'Slate',
      };

  void setAppTheme(AppTheme theme) {
    _appTheme = theme;
    notifyListeners();
  }

  void toggleDarkMode() {
    _isDarkMode = !_isDarkMode;
    notifyListeners();
  }
}

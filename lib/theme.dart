import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppColour {
  babyBlue(
    'Baby Blue',
    Color(0xFF83C9F4),
    Color(0xFF378BC4),
    Color(0xFFEAF6FF),
  ),
  softPurple(
    'Soft Purple',
    Color(0xFFC4A7F5),
    Color(0xFF8863C7),
    Color(0xFFF3EDFF),
  );

  const AppColour(this.label, this.primary, this.accent, this.softSurface);
  final String label;
  final Color primary;
  final Color accent;
  final Color softSurface;
}

abstract final class AppTheme {
  static ThemeData build(AppColour colour, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final generated = ColorScheme.fromSeed(
      seedColor: colour.accent,
      brightness: brightness,
    );
    final textAccent = generated.primary;
    final scheme = generated.copyWith(
      primary: colour.primary,
      onPrimary: const Color(0xFF17202B),
      primaryContainer: dark ? null : colour.softSurface,
      onPrimaryContainer: dark ? null : const Color(0xFF17202B),
      secondary: colour.accent,
      onSecondary: colour == AppColour.babyBlue ? Colors.black : Colors.white,
      surface: dark ? null : colour.softSurface,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: textAccent),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(foregroundColor: textAccent),
      ),
      listTileTheme: ListTileThemeData(
        selectedColor: scheme.onPrimaryContainer,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: textAccent,
        selectionColor: scheme.primary.withValues(alpha: .35),
        selectionHandleColor: textAccent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: const OutlineInputBorder(),
        floatingLabelStyle: TextStyle(color: textAccent),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: textAccent, width: 2),
        ),
      ),
      cardTheme: const CardThemeData(margin: EdgeInsets.symmetric(vertical: 8)),
    );
  }

  /// Charts must read these roles during build to follow appearance changes.
  static List<Color> chartColours(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return [scheme.primary, scheme.secondary, scheme.tertiary, scheme.outline];
  }
}

class AppearancePreferences extends ChangeNotifier {
  AppearancePreferences(this._storage);
  final SharedPreferencesAsync _storage;
  AppColour colour = AppColour.babyBlue;
  ThemeMode mode = ThemeMode.system;
  String? error;
  Future<void> _pending = Future<void>.value();

  static Future<AppearancePreferences> load({
    SharedPreferencesAsync? storage,
  }) async {
    final result = AppearancePreferences(storage ?? SharedPreferencesAsync());
    try {
      final colourName = await result._storage.getString('appearance.colour');
      final modeName = await result._storage.getString('appearance.mode');
      result.colour =
          AppColour.values.where((v) => v.name == colourName).firstOrNull ??
          AppColour.babyBlue;
      result.mode =
          ThemeMode.values.where((v) => v.name == modeName).firstOrNull ??
          ThemeMode.system;
    } catch (_) {
      result.error = 'Could not read appearance preferences. Using defaults.';
    }
    return result;
  }

  Future<void> setColour(AppColour value) {
    colour = value;
    return _save('appearance.colour', value.name);
  }

  Future<void> setMode(ThemeMode value) {
    mode = value;
    return _save('appearance.mode', value.name);
  }

  Future<void> _save(String key, String value) {
    error = null;
    notifyListeners();
    // Serialize writes so the last tap also wins after restarting.
    _pending = _pending.then((_) async {
      try {
        await _storage.setString(key, value);
      } catch (_) {
        error =
            'Could not save appearance. Please select your preference again.';
        notifyListeners();
      }
    });
    return _pending;
  }
}

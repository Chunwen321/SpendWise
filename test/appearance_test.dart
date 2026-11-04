import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spendwise/main.dart';
import 'package:spendwise/theme.dart';

class MemoryPreferences implements SharedPreferencesAsync {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  final values = <String, String>{};
  @override
  Future<String?> getString(String key) async => values[key];
  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  test('defaults, persistence, unknown values and rapid changes', () async {
    final storage = MemoryPreferences();
    final preferences = await AppearancePreferences.load(storage: storage);
    expect(preferences.colour, AppColour.babyBlue);
    expect(preferences.mode, ThemeMode.system);
    final first = preferences.setColour(AppColour.softPurple);
    final last = preferences.setColour(AppColour.babyBlue);
    await Future.wait([first, last, preferences.setMode(ThemeMode.dark)]);
    final restored = await AppearancePreferences.load(storage: storage);
    expect(restored.colour, AppColour.babyBlue);
    expect(restored.mode, ThemeMode.dark);
    storage.values['appearance.colour'] = 'unknown';
    storage.values['appearance.mode'] = 'unknown';
    final fallback = await AppearancePreferences.load(storage: storage);
    expect(fallback.colour, AppColour.babyBlue);
    expect(fallback.mode, ThemeMode.system);
  });

  test('all palettes use readable text pairs and dark surfaces', () {
    double contrast(Color a, Color b) {
      final x = a.computeLuminance();
      final y = b.computeLuminance();
      return ((x > y ? x : y) + .05) / ((x > y ? y : x) + .05);
    }

    for (final colour in AppColour.values) {
      for (final brightness in Brightness.values) {
        final theme = AppTheme.build(colour, brightness);
        final s = theme.colorScheme;
        expect(theme.useMaterial3, isTrue);
        expect(s.primary, colour.primary);
        expect(s.secondary, colour.accent);
        for (final pair in [
          (s.primary, s.onPrimary),
          (s.secondary, s.onSecondary),
          (s.surface, s.onSurface),
          (s.primaryContainer, s.onPrimaryContainer),
          (
            s.surface,
            theme.textButtonTheme.style!.foregroundColor!.resolve({})!,
          ),
          (
            s.surface,
            theme.outlinedButtonTheme.style!.foregroundColor!.resolve({})!,
          ),
          (s.primaryContainer, theme.listTileTheme.selectedColor!),
        ]) {
          expect(contrast(pair.$1, pair.$2), greaterThanOrEqualTo(4.5));
        }
        if (brightness == Brightness.dark) {
          expect(s.surface.computeLuminance(), lessThan(.05));
        } else {
          expect(s.surface, colour.softSurface);
        }
      }
    }
  });

  testWidgets('switches instantly and follows device brightness in System', (
    tester,
  ) async {
    final preferences = await AppearancePreferences.load(
      storage: MemoryPreferences(),
    );
    await tester.pumpWidget(SpendWiseApp(preferences: preferences));
    expect(find.text('Baby Blue'), findsOneWidget);
    expect(find.text('Soft Purple'), findsOneWidget);
    await tester.tap(find.text('Soft Purple'));
    await tester.pumpAndSettle();
    var context = tester.element(find.byType(SettingsScreen));
    expect(Theme.of(context).colorScheme.primary, AppColour.softPurple.primary);
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(Theme.of(context).brightness, Brightness.dark);
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(Theme.of(context).brightness, Brightness.light);
    await tester.tap(find.text('System'));
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpAndSettle();
    context = tester.element(find.byType(SettingsScreen));
    expect(Theme.of(context).brightness, Brightness.dark);
  });
}

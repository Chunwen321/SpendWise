import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'database/app_database.dart';
import 'repositories/finance_repository.dart';
import 'theme.dart';
import 'providers/finance_store.dart';
import 'screens/main_shell.dart';
import 'screens/security.dart';
import 'services/app_lock_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await AppearancePreferences.load();
  runApp(DatabaseBootstrap(preferences: preferences));
}

class DatabaseBootstrap extends StatefulWidget {
  const DatabaseBootstrap({super.key, required this.preferences});
  final AppearancePreferences preferences;
  @override
  State<DatabaseBootstrap> createState() => _DatabaseBootstrapState();
}

class _DatabaseBootstrapState extends State<DatabaseBootstrap> {
  late Future<AppDatabase> _opening = AppDatabase.open();
  final lock = AppLockService()..load();

  @override
  void dispose() {
    _opening.then((db) => db.close(), onError: (Object _) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<AppDatabase>(
    future: _opening,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        return ChangeNotifierProvider<FinanceStore>(
          create: (_) =>
              FinanceStore(FinanceRepository(snapshot.data!))..refresh(),
          child: SpendWiseApp(
            preferences: widget.preferences,
            home: MainShell(preferences: widget.preferences, lock: lock),
            lock: lock,
          ),
        );
      }
      return MaterialApp(
        theme: AppTheme.build(widget.preferences.colour, Brightness.light),
        darkTheme: AppTheme.build(widget.preferences.colour, Brightness.dark),
        themeMode: widget.preferences.mode,
        home: Scaffold(
          body: Center(
            child: snapshot.hasError
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Could not open SpendWise storage. Your data has not been reset.',
                      ),
                      FilledButton(
                        onPressed: () => setState(() {
                          _opening = AppDatabase.open();
                        }),
                        child: const Text('Retry'),
                      ),
                    ],
                  )
                : const CircularProgressIndicator(),
          ),
        ),
      );
    },
  );
}

class SpendWiseApp extends StatelessWidget {
  const SpendWiseApp({
    super.key,
    required this.preferences,
    this.home,
    this.lock,
  });
  final AppearancePreferences preferences;
  final Widget? home;
  final AppLockService? lock;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: preferences,
    builder: (context, _) => MaterialApp(
      title: 'SpendWise',
      theme: AppTheme.build(preferences.colour, Brightness.light),
      darkTheme: AppTheme.build(preferences.colour, Brightness.dark),
      themeMode: preferences.mode,
      builder: (context, child) =>
          lock == null ? child! : SecurityGate(service: lock!, child: child!),
      home: home ?? SettingsScreen(preferences: preferences),
    ),
  );
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.preferences});
  final AppearancePreferences preferences;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Appearance')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Appearance', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Colour theme',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (final colour in AppColour.values)
                  ListTile(
                    selected: preferences.colour == colour,
                    selectedTileColor: Theme.of(context)
                        .colorScheme
                        .primaryContainer,
                    leading: CircleAvatar(backgroundColor: colour.primary),
                    title: Text(colour.label),
                    trailing: preferences.colour == colour
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () => preferences.setColour(colour),
                  ),
                const SizedBox(height: 24),
                Text(
                  'Display mode',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final mode in ThemeMode.values)
                      ChoiceChip(
                        label: Text(switch (mode) {
                          ThemeMode.light => 'Light',
                          ThemeMode.dark => 'Dark',
                          ThemeMode.system => 'System',
                        }),
                        selected: preferences.mode == mode,
                        onSelected: (_) => preferences.setMode(mode),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'System follows your device’s light or dark setting.',
                ),
                if (preferences.error != null)
                  Text(
                    preferences.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

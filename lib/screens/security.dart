import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_lock_service.dart';
import 'main_shell.dart';

class SecurityGate extends StatefulWidget {
  const SecurityGate({super.key, required this.service, required this.child});
  final AppLockService service;
  final Widget child;
  @override
  State<SecurityGate> createState() => _SecurityGateState();
}

class _SecurityGateState extends State<SecurityGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.service.resume();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      widget.service.background();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.service,
    builder: (context, _) {
      final lock = widget.service;
      return Stack(
        children: [
          ExcludeFocus(
            excluding: !lock.ready || lock.locked || lock.hidden,
            child: Offstage(
              offstage: !lock.ready || lock.locked || lock.hidden,
              child: widget.child,
            ),
          ),
          if (!lock.ready || lock.locked || lock.hidden)
            Positioned.fill(
              child: Material(
                child: lock.hidden
                    ? const Center(child: Icon(Icons.lock_outline, size: 48))
                    : LockScreen(service: lock),
              ),
            ),
        ],
      );
    },
  );
}

class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.service});
  final AppLockService service;
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final pin = TextEditingController();
  @override
  void dispose() {
    pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lock = widget.service;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 48),
                  const SizedBox(height: 20),
                  Text(
                    'Unlock SpendWise',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  if (lock.error != null)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(lock.error!),
                    ),
                  if (!lock.ready)
                    FilledButton(
                      onPressed: lock.load,
                      child: const Text('Retry secure storage'),
                    )
                  else ...[
                    TextField(
                      controller: pin,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      decoration: const InputDecoration(
                        labelText: '6-digit PIN',
                      ),
                      onSubmitted: (_) async {
                        await lock.verify(pin.text);
                        pin.clear();
                      },
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: lock.busy
                          ? null
                          : () async {
                              await lock.verify(pin.text);
                              if (!context.mounted) return;
                              pin.clear();
                              if (lock.remainingSeconds > 0) {
                                message(
                                  context,
                                  'Try again in ${lock.remainingSeconds} seconds.',
                                );
                              }
                            },
                      child: Text(lock.busy ? 'Verifying…' : 'Unlock'),
                    ),
                    if (lock.biometrics)
                      TextButton.icon(
                        onPressed: lock.busy ? null : lock.biometricUnlock,
                        icon: const Icon(Icons.fingerprint),
                        label: const Text('Use biometrics'),
                      ),
                    const Text(
                      'Forgotten PINs cannot be bypassed. Keep encrypted backups and their passphrases safe.',
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SecuritySettings extends StatefulWidget {
  const SecuritySettings({super.key, required this.service});
  final AppLockService service;
  @override
  State<SecuritySettings> createState() => _SecuritySettingsState();
}

class _SecuritySettingsState extends State<SecuritySettings> {
  final pin = TextEditingController(), repeat = TextEditingController();
  bool busy = false;
  @override
  void dispose() {
    pin.dispose();
    repeat.dispose();
    super.dispose();
  }

  Future<void> action(Future<void> Function() work) async {
    setState(() => busy = true);
    try {
      await work();
      pin.clear();
      repeat.clear();
    } catch (_) {
      if (mounted) {
        message(
          context,
          'Could not update app lock. Check your PIN and biometric enrollment.',
        );
      }
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.service,
    builder: (context, _) {
      final lock = widget.service;
      return Scaffold(
        appBar: AppBar(title: const Text('App lock')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'App lock protects access to the interface. It does not encrypt the financial database. There is no PIN recovery bypass. Export encrypted backups regularly.',
            ),
            const SizedBox(height: 20),
            TextField(
              controller: pin,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              decoration: InputDecoration(
                labelText: lock.enabled
                    ? 'Current PIN to disable'
                    : 'New 6-digit PIN',
              ),
            ),
            if (!lock.enabled) ...[
              const SizedBox(height: 12),
              TextField(
                controller: repeat,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Confirm PIN'),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
              ),
              FilledButton(
                onPressed: busy
                    ? null
                    : () => action(() async {
                        if (pin.text != repeat.text) {
                          throw StateError('PINs differ.');
                        }
                        await lock.configure(pin.text);
                      }),
                child: const Text('Enable app lock'),
              ),
            ] else ...[
              SwitchListTile(
                title: const Text('Allow biometrics'),
                value: lock.biometrics,
                onChanged: busy
                    ? null
                    : (v) => action(() => lock.setOptions(biometric: v)),
              ),
              DropdownButtonFormField<int>(
                initialValue: lock.timeout,
                decoration: const InputDecoration(
                  labelText: 'Lock after backgrounding',
                ),
                items: [
                  for (final e in {
                    0: 'Immediately',
                    30: '30 seconds',
                    60: '1 minute',
                    300: '5 minutes',
                  }.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: busy
                    ? null
                    : (v) => action(() => lock.setOptions(seconds: v)),
              ),
              FilledButton(
                onPressed: busy
                    ? null
                    : () => action(() => lock.disable(pin.text)),
                child: const Text('Verify PIN and disable lock'),
              ),
              OutlinedButton(
                onPressed: lock.lock,
                child: const Text('Lock now'),
              ),
            ],
          ],
        ),
      );
    },
  );
}

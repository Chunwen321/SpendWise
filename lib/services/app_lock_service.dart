import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import 'backup_service.dart';

Future<String> pinDigest(Map<String, String> args) async => base64Encode(
  await (await passwordKey(
    '${args['pin']}:${args['pepper']}',
    base64Decode(args['salt']!),
  )).extractBytes(),
);

class AppLockService extends ChangeNotifier {
  AppLockService({FlutterSecureStorage? storage, LocalAuthentication? auth})
    : storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(resetOnError: false),
          ),
      auth = auth ?? LocalAuthentication();
  final FlutterSecureStorage storage;
  final LocalAuthentication auth;
  Map<String, dynamic> record = {};
  bool ready = false, locked = true, hidden = false, busy = false;
  String? error;
  DateTime? backgroundAt;
  bool get enabled => record['hash'] != null;
  bool get biometrics => record['biometrics'] == true;
  int get timeout => record['timeout'] as int? ?? 60;
  int get remainingSeconds => max(
    0,
    ((record['retryAt'] as int? ?? 0) -
            DateTime.now().millisecondsSinceEpoch +
            999) ~/
        1000,
  );
  Future<void> load() async {
    try {
      final value = await storage.read(key: 'spendwise.lock');
      record = value == null ? {} : jsonDecode(value) as Map<String, dynamic>;
      if (record.isNotEmpty &&
          (record['hash'] is! String ||
              record['salt'] is! String ||
              record['pepper'] is! String)) {
        throw StateError('Invalid lock record');
      }
      ready = true;
      locked = enabled;
      error = null;
    } catch (_) {
      error = 'Secure storage is unavailable. Retry to access SpendWise.';
      ready = false;
      locked = true;
    }
    notifyListeners();
  }

  Future<void> _write(Map<String, dynamic> next) async {
    await storage.write(key: 'spendwise.lock', value: jsonEncode(next));
    record = next;
  }

  Future<void> configure(String pin) async {
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) {
      throw ArgumentError('Use exactly six digits.');
    }
    final salt = base64Encode(secureBytes(16));
    final pepper = base64Encode(secureBytes(32));
    final hash = await compute(pinDigest, {
      'pin': pin,
      'salt': salt,
      'pepper': pepper,
    });
    await _write({
      'hash': hash,
      'salt': salt,
      'pepper': pepper,
      'timeout': 60,
      'biometrics': false,
      'failures': 0,
      'retryAt': 0,
    });
    locked = false;
    notifyListeners();
  }

  Future<bool> verify(String pin) async {
    if (!enabled || busy || remainingSeconds > 0) return false;
    busy = true;
    notifyListeners();
    try {
      final hash = await compute(pinDigest, {
        'pin': pin,
        'salt': record['salt'] as String,
        'pepper': record['pepper'] as String,
      });
      final expected = base64Decode(record['hash'] as String),
          actual = base64Decode(hash);
      var difference = actual.length ^ expected.length;
      for (var i = 0; i < min(actual.length, expected.length); i++) {
        difference |= actual[i] ^ expected[i];
      }
      if (difference == 0) {
        await _write({...record, 'failures': 0, 'retryAt': 0});
        locked = false;
        error = null;
        return true;
      }
      final failures = (record['failures'] as int? ?? 0) + 1;
      final delay = min(300, pow(2, min(failures, 9)).toInt());
      await _write({
        ...record,
        'failures': failures,
        'retryAt': DateTime.now().millisecondsSinceEpoch + delay * 1000,
      });
      error = 'Incorrect PIN. Try again in $delay seconds.';
      return false;
    } catch (_) {
      error = 'Could not verify PIN. Secure storage must be available.';
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> biometricUnlock() async {
    if (!enabled || !biometrics || busy || remainingSeconds > 0) return false;
    busy = true;
    notifyListeners();
    try {
      final success = await auth.authenticate(
        localizedReason: 'Unlock SpendWise',
        biometricOnly: true,
      );
      if (success) {
        await _write({...record, 'failures': 0, 'retryAt': 0});
        locked = false;
        error = null;
      }
      return success;
    } catch (_) {
      error = 'Biometrics unavailable. Use your PIN.';
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> setOptions({int? seconds, bool? biometric}) async {
    if (!enabled || locked) throw StateError('Unlock first.');
    if (biometric == true &&
        (!(await auth.canCheckBiometrics) ||
            (await auth.getAvailableBiometrics()).isEmpty)) {
      throw StateError('No biometrics enrolled.');
    }
    await _write({...record, 'timeout': ?seconds, 'biometrics': ?biometric});
    notifyListeners();
  }

  Future<void> disable(String pin) async {
    if (!await verify(pin)) throw StateError('PIN verification failed.');
    await storage.delete(key: 'spendwise.lock');
    record = {};
    locked = false;
    notifyListeners();
  }

  void lock() {
    if (enabled) {
      locked = true;
      error = null;
      notifyListeners();
    }
  }

  void background() {
    hidden = true;
    backgroundAt ??= DateTime.now();
    notifyListeners();
  }

  void resume() {
    if (enabled &&
        !busy &&
        backgroundAt != null &&
        DateTime.now().difference(backgroundAt!).inSeconds >= timeout) {
      locked = true;
    }
    hidden = false;
    backgroundAt = null;
    notifyListeners();
  }
}

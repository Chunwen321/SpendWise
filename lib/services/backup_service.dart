import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';

const backupLimit = 32 * 1024 * 1024;
const backupIterations = 600000;
List<int> secureBytes(int count) {
  final random = Random.secure();
  return List.generate(count, (_) => random.nextInt(256));
}

Future<SecretKey> passwordKey(String password, List<int> salt) => Pbkdf2(
  macAlgorithm: Hmac.sha256(),
  iterations: backupIterations,
  bits: 256,
).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);

Future<List<int>> encryptBackup(Map<String, Object?> args) async {
  final salt = secureBytes(16);
  final key = await passwordKey(args['password'] as String, salt);
  final box = await AesGcm.with256bits().encrypt(
    utf8.encode(jsonEncode(args['payload'])),
    secretKey: key,
    aad: utf8.encode('SpendWise:1'),
  );
  return utf8.encode(
    jsonEncode({
      'format': 'SpendWise',
      'version': 1,
      'iterations': backupIterations,
      'salt': base64Encode(salt),
      'nonce': base64Encode(box.nonce),
      'mac': base64Encode(box.mac.bytes),
      'ciphertext': base64Encode(box.cipherText),
    }),
  );
}

Future<Map<String, Object?>> decryptBackup(Map<String, Object?> args) async {
  final bytes = args['bytes'] as List<int>;
  if (bytes.length > backupLimit) {
    throw const FormatException('Backup exceeds 32 MB.');
  }
  final envelope = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  if (envelope['format'] != 'SpendWise' ||
      envelope['version'] != 1 ||
      envelope['iterations'] != backupIterations) {
    throw const FormatException('Unsupported backup format.');
  }
  final salt = base64Decode(envelope['salt'] as String);
  final nonce = base64Decode(envelope['nonce'] as String);
  final mac = base64Decode(envelope['mac'] as String);
  if (salt.length != 16 || nonce.length != 12 || mac.length != 16) {
    throw const FormatException('Invalid backup.');
  }
  final key = await passwordKey(args['password'] as String, salt);
  final clear = await AesGcm.with256bits().decrypt(
    SecretBox(
      base64Decode(envelope['ciphertext'] as String),
      nonce: nonce,
      mac: Mac(mac),
    ),
    secretKey: key,
    aad: utf8.encode('SpendWise:1'),
  );
  return Map<String, Object?>.from(jsonDecode(utf8.decode(clear)) as Map);
}

class BackupService {
  BackupService(this.database, {DatabaseFactory? factory})
    : factory = factory ?? databaseFactory;
  final AppDatabase database;
  final DatabaseFactory factory;
  static const tables = [
    'accounts',
    'categories',
    'recurring_rules',
    'transactions',
    'transfers',
  ];
  static const columns = {
    'accounts': {'id', 'name', 'kind', 'opening_sen', 'created_at'},
    'transfers': {
      'id',
      'from_account_id',
      'to_account_id',
      'amount_sen',
      'transaction_date',
      'description',
      'created_at',
    },
    'categories': {'id', 'name', 'type', 'created_at'},
    'recurring_rules': {
      'account_id',
      'id',
      'category_id',
      'type',
      'amount_sen',
      'description',
      'frequency',
      'start_date',
      'end_date',
      'next_due_date',
      'is_active',
      'created_at',
      'updated_at',
    },
    'transactions': {
      'account_id',
      'id',
      'category_id',
      'type',
      'amount_sen',
      'description',
      'transaction_date',
      'created_at',
      'updated_at',
      'recurring_rule_id',
      'recurrence_occurrence_date',
    },
  };

  Future<Map<String, Object?>> snapshot() =>
      database.connection.transaction((txn) async {
        if ((await txn.rawQuery('PRAGMA integrity_check'))
                .single
                .values
                .single !=
            'ok') {
          throw StateError('Database integrity check failed.');
        }
        return {
          'schema': AppDatabase.schemaVersion,
          for (final table in tables) table: await txn.query(table),
        };
      });

  Future<List<int>> export(String password) async {
    if (password.length < 12) {
      throw ArgumentError(
        'Use a backup passphrase with at least 12 characters.',
      );
    }
    final payload = await snapshot();
    final result = await compute(encryptBackup, {
      'password': password,
      'payload': payload,
    });
    if (result.length > backupLimit) throw StateError('Backup exceeds 32 MB.');
    final verified = await compute(decryptBackup, {
      'password': password,
      'bytes': result,
    });
    if (jsonEncode(verified) != jsonEncode(payload)) {
      throw StateError('Backup verification failed.');
    }
    return result;
  }

  Future<Map<String, Object?>> read(List<int> bytes, String password) async {
    final decoded = await compute(decryptBackup, {
      'bytes': bytes,
      'password': password,
    });
    final payload = upgradePayload(decoded);
    await validate(payload);
    return payload;
  }

  Future<void> _replace(
    DatabaseExecutor db,
    Map<String, Object?> payload,
  ) async {
    if (payload['schema'] != AppDatabase.schemaVersion ||
        payload.keys.length != 6) {
      throw const FormatException('Unsupported backup schema.');
    }
    for (final table in tables.reversed) {
      await db.delete(table);
    }
    for (final table in tables) {
      final rows = payload[table];
      if (rows is! List || rows.length > 200000) {
        throw const FormatException('Invalid backup records.');
      }
      for (final raw in rows) {
        final row = Map<String, Object?>.from(raw as Map);
        if (row.keys.length != columns[table]!.length ||
            row.keys.any((key) => !columns[table]!.contains(key))) {
          throw const FormatException('Unexpected backup columns.');
        }
        if (row['id'] is! int || (row['id'] as int) < 1) {
          throw const FormatException('Invalid record ID.');
        }
        for (final name in [
          'transaction_date',
          'start_date',
          'next_due_date',
          'end_date',
          'recurrence_occurrence_date',
        ]) {
          if (row[name] != null) {
            final value = row[name] as String;
            final date = DateTime.tryParse(value);
            if (date == null ||
                !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ||
                date.toIso8601String().substring(0, 10) != value) {
              throw const FormatException('Invalid calendar date.');
            }
          }
        }
        if (table == 'transactions' && row['transaction_date'] == null) {
          throw const FormatException('Missing date.');
        }
        if (table == 'recurring_rules' &&
            (row['next_due_date'] as String).compareTo(
                  row['start_date'] as String,
                ) <
                0) {
          throw const FormatException('Invalid recurrence progress.');
        }
        await db.insert(table, row);
      }
    }
    if ((await db.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
      throw const FormatException('Broken category references.');
    }
    if ((await db.rawQuery('PRAGMA integrity_check')).single.values.single !=
        'ok') {
      throw const FormatException('Backup integrity check failed.');
    }
  }

  Future<void> validate(Map<String, Object?> payload) async {
    // A separate SQLite database enforces the complete schema before touching
    // live records. This also validates foreign keys and occurrence uniqueness.
    final staging = await AppDatabase.open(
      factory: factory,
      path: inMemoryDatabasePath,
      singleInstance: false,
    );
    try {
      await staging.connection.transaction(
        (txn) => _replace(txn, upgradePayload(payload)),
      );
    } finally {
      await staging.close();
    }
  }

  Future<void> restore(Map<String, Object?> payload) async {
    await validate(payload);
    await database.connection.transaction(
      (txn) => _replace(txn, upgradePayload(payload)),
    );
  }

  static Map<String, Object?> upgradePayload(Map<String, Object?> payload) {
    if (payload['schema'] != 1) return payload;
    if (payload.keys.length != 4) {
      throw const FormatException('Invalid legacy backup.');
    }
    return {
      ...payload,
      'schema': 2,
      'accounts': [
        {
          'id': 1,
          'name': 'Main ledger',
          'kind': 'other',
          'opening_sen': 0,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        },
      ],
      'transfers': <Map<String, Object?>>[],
      for (final table in ['transactions', 'recurring_rules'])
        table: [
          for (final row in payload[table] as List)
            {...Map<String, Object?>.from(row as Map), 'account_id': 1},
        ],
    };
  }

  Future<File> writeVerified(
    File target,
    List<int> bytes,
    String password,
  ) async {
    await target.writeAsBytes(bytes, flush: true);
    await read(await target.readAsBytes(), password);
    return target;
  }
}

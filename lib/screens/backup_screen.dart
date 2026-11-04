import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/finance_store.dart';
import '../services/backup_service.dart';
import 'main_shell.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final password = TextEditingController(), repeat = TextEditingController();
  bool busy = false;
  String status = '';
  @override
  void dispose() {
    password.dispose();
    repeat.dispose();
    super.dispose();
  }

  Future<void> run(bool restore) async {
    final store = context.read<FinanceStore>();
    final service = BackupService(store.repository.database);
    final passphrase = password.text;
    if (passphrase.isEmpty ||
        (!restore && (passphrase.length < 12 || passphrase != repeat.text))) {
      message(
        context,
        'For export, enter and confirm a passphrase of at least 12 characters. For import, enter the original passphrase.',
      );
      return;
    }
    setState(() {
      busy = true;
      status = restore
          ? 'Validating backup…'
          : 'Encrypting and verifying backup…';
    });
    try {
      if (restore) {
        final selected = await FilePicker.pickFile();
        if (selected == null) {
          setState(() => status = 'Import cancelled.');
          return;
        }
        if ((await selected.length() ?? backupLimit + 1) > backupLimit) {
          throw const FormatException('Invalid backup file.');
        }
        final bytes = await selected.readAsBytes();
        final payload = await service.read(bytes, passphrase);
        if (!mounted) return;
        if (!await confirm(
          context,
          'Replace all financial data?',
          'Validated backup contains ${(payload['transactions'] as List).length} transactions and ${(payload['recurring_rules'] as List).length} recurring rules. This replaces your current records. Export a backup first if you need to keep them.',
        )) {
          setState(() => status = 'Import cancelled.');
          return;
        }
        await service.restore(payload);
        await store.refresh();
        if (mounted) {
          setState(
            () => status = 'Backup restored and database integrity verified.',
          );
        }
      } else {
        final bytes = await service.export(passphrase);
        final directory = await getTemporaryDirectory();
        final file = await service.writeVerified(
          File(
            '${directory.path}/spendwise-${DateTime.now().millisecondsSinceEpoch}.swbackup',
          ),
          bytes,
          passphrase,
        );
        if (!mounted) return;
        setState(
          () => status = 'Encrypted backup written and validated. Choose where to save it in the share sheet.',
        );
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path)],
            subject: 'SpendWise encrypted backup',
          ),
        );
        // Keep the encrypted cache file so share targets can finish reading it.
      }
      password.clear();
      repeat.clear();
    } catch (_) {
      if (mounted) {
        setState(
          () => status = 'Operation failed. Check the passphrase, file format and available storage. Existing data was not reset.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Backup and restore')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Encrypted backups contain categories, transactions and recurring rules. Your PIN and appearance preferences are excluded. Store the passphrase separately: it cannot be recovered. Supported backup size: up to 32 MB.',
          ),
          const SizedBox(height: 20),
          TextField(
            controller: password,
            obscureText: true,
            enabled: !busy,
            enableSuggestions: false,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Backup passphrase'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: repeat,
            obscureText: true,
            enabled: !busy,
            enableSuggestions: false,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Confirm passphrase for export',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: busy ? null : () => run(false),
            icon: const Icon(Icons.ios_share),
            label: const Text('Create and share encrypted backup'),
          ),
          OutlinedButton.icon(
            onPressed: busy ? null : () => run(true),
            icon: const Icon(Icons.restore),
            label: const Text('Import encrypted backup'),
          ),
          if (busy) const LinearProgressIndicator(),
          const SizedBox(height: 16),
          Text(status),
        ],
      ),
    ),
  );
}

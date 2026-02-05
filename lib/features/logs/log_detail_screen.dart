import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/models/log_entry.dart';
import '../../state/controllers/logs_controller.dart';

class LogDetailScreen extends ConsumerWidget {
  const LogDetailScreen({super.key, required this.logId});

  final String logId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(logsControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Log entry'),
        actions: [
          IconButton(
            tooltip: 'Share',
            onPressed: () async {
              final e = async.value?.firstWhere((x) => x.id == logId, orElse: () => null as dynamic);
              if (e == null) return;
              final text = const JsonEncoder.withIndent('  ').convert(e.toJson());
              await Share.share(text, subject: 'TapDucky log entry');
            },
            icon: const Icon(Icons.ios_share),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Failed to load logs: $e')),
        data: (items) {
          final entry = _byId(items, logId);
          if (entry == null) return const Center(child: Text('Log entry not found.'));
          return _Body(entry: entry);
        },
      ),
    );
  }

  LogEntry? _byId(List<LogEntry> items, String id) {
    for (final e in items) {
      if (e.id == id) return e;
    }
    return null;
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.entry});
  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final meta = entry.meta ?? const <String, String>{};

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_iconFor(entry.level, entry.success), color: entry.success ? cs.primary : cs.error),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        entry.level.toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(entry.timestamp.toLocal().toString()),
                  ],
                ),
                const SizedBox(height: 12),
                Text(entry.message, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                Text('Payload: ${entry.payloadName ?? 'n/a'}', style: TextStyle(color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Metadata', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                if (meta.isEmpty)
                  Text('No metadata', style: TextStyle(color: cs.onSurfaceVariant))
                else
                  ...meta.entries.map((e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(width: 140, child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600))),
                            Expanded(child: Text(e.value)),
                          ],
                        ),
                      )),
              ],
            ),
          ),
        ),
      ],
    );
  }

  IconData _iconFor(String level, bool success) {
    if (!success) return Icons.error_outline;
    switch (level) {
      case 'debug':
        return Icons.bug_report_outlined;
      case 'warn':
        return Icons.warning_amber_outlined;
      case 'error':
        return Icons.error_outline;
      default:
        return Icons.info_outline;
    }
  }
}

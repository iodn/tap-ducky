import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/router.dart';
import '../../data/models/log_entry.dart';
import '../../state/controllers/logs_controller.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/empty_state.dart';

class LogsScreen extends ConsumerStatefulWidget {
  const LogsScreen({super.key});

  @override
  ConsumerState<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends ConsumerState<LogsScreen> {
  String _level = 'all';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(logsControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Logs'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'export') {
                final items = async.value ?? const <LogEntry>[];
                await _export(items);
              } else if (v == 'clear') {
                final ok = await showConfirmDialog(
                  context,
                  title: 'Clear logs',
                  message: 'Delete all stored logs?',
                  confirmLabel: 'Clear',
                  dangerous: true,
                );
                if (!ok) return;
                await ref.read(logsControllerProvider.notifier).clear();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'export', child: Text('Export')),
              PopupMenuItem(value: 'clear', child: Text('Clear all')),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                const Text('Level:'),
                const SizedBox(width: 10),
                DropdownButton<String>(
                  value: _level,
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All')),
                    DropdownMenuItem(value: 'info', child: Text('info')),
                    DropdownMenuItem(value: 'debug', child: Text('debug')),
                    DropdownMenuItem(value: 'warn', child: Text('warn')),
                    DropdownMenuItem(value: 'error', child: Text('error')),
                  ],
                  onChanged: (v) => setState(() => _level = v ?? 'all'),
                ),
              ],
            ),
          ),
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Failed to load logs: $e')),
        data: (items) {
          final filtered = _level == 'all' ? items : items.where((e) => e.level == _level).toList();
          if (filtered.isEmpty) {
            return EmptyState(
              title: items.isEmpty ? 'No logs yet' : 'No matching logs',
              subtitle: items.isEmpty ? 'Run a payload to generate logs.' : 'Change the level filter to see more entries.',
              icon: Icons.list_alt_outlined,
            );
          }

          return ListView.separated(
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final e = filtered[i];
              return ListTile(
                leading: Icon(_iconFor(e.level, e.success)),
                title: Text(e.message, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text('${e.timestamp.toLocal()} • ${e.payloadName ?? 'n/a'}'),
                onTap: () => context.push('${const LogsRoute().location}/${e.id}'),
              );
            },
          );
        },
      ),
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

  Future<void> _export(List<LogEntry> items) async {
    final pack = {
      'format': 'tapducky_log_export',
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'items': items.map((e) => e.toJson()).toList(),
    };
    final data = const JsonEncoder.withIndent('  ').convert(pack);
    await Share.share(data, subject: 'TapDucky logs export');
  }
}

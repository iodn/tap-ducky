import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/execution_group.dart';
import '../../data/models/log_entry.dart';
import '../../state/controllers/logs_controller.dart';
import '../../widgets/empty_state.dart';

class ExecutionHistoryScreen extends ConsumerWidget {
  const ExecutionHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.watch(logsControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Execution History'),
        actions: [
          IconButton(
            tooltip: 'Clear all',
            onPressed: () async {
              final ok = await _showClearConfirmation(context);
              if (ok) {
                await ref.read(logsControllerProvider.notifier).clear();
              }
            },
            icon: const Icon(Icons.delete_sweep),
          ),
        ],
      ),
      body: logsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 64, color: Theme.of(context).colorScheme.error),
                const SizedBox(height: 16),
                Text('Failed to load history', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text('$e', textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
        data: (logs) {
          final groups = ExecutionGroup.fromLogs(logs);

          if (groups.isEmpty) {
            return const EmptyState(
              title: 'No execution history',
              subtitle: 'Run a payload to see execution history here.',
              icon: Icons.history,
            );
          }

          return Column(
            children: [
              _StatisticsBar(groups: groups),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: groups.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
                  itemBuilder: (context, i) => _ExecutionGroupTile(group: groups[i]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<bool> _showClearConfirmation(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear execution history'),
        content: const Text('This will delete all execution logs. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

class _StatisticsBar extends StatelessWidget {
  const _StatisticsBar({required this.groups});

  final List<ExecutionGroup> groups;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final total = groups.length;
    final successful = groups.where((g) => g.success).length;
    final failed = total - successful;
    final last24h = ExecutionGroup.countRecent(groups, const Duration(hours: 24));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          _StatChip(
            icon: Icons.history,
            label: 'Total',
            value: '$total',
            color: cs.primary,
          ),
          const SizedBox(width: 12),
          _StatChip(
            icon: Icons.check_circle,
            label: 'Success',
            value: '$successful',
            color: cs.primary,
          ),
          const SizedBox(width: 12),
          _StatChip(
            icon: Icons.error,
            label: 'Failed',
            value: '$failed',
            color: cs.error,
          ),
          const SizedBox(width: 12),
          _StatChip(
            icon: Icons.access_time,
            label: '24h',
            value: '$last24h',
            color: cs.tertiary,
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExecutionGroupTile extends StatefulWidget {
  const _ExecutionGroupTile({required this.group});

  final ExecutionGroup group;

  @override
  State<_ExecutionGroupTile> createState() => _ExecutionGroupTileState();
}

class _ExecutionGroupTileState extends State<_ExecutionGroupTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final g = widget.group;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: g.success
                          ? cs.primaryContainer
                          : cs.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      g.success ? Icons.check_circle : Icons.error,
                      color: g.success
                          ? cs.onPrimaryContainer
                          : cs.onErrorContainer,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          g.payloadName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatTimestamp(g.startTime),
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.timer, size: 14, color: cs.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Text(
                              g.durationFormatted,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Icon(Icons.article, size: 14, color: cs.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Text(
                              '${g.totalEvents} events',
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            if (g.errorCount > 0) ...[
                              const SizedBox(width: 12),
                              Icon(Icons.error_outline, size: 14, color: cs.error),
                              const SizedBox(width: 4),
                              Text(
                                '${g.errorCount}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.error,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            if (g.warningCount > 0) ...[
                              const SizedBox(width: 12),
                              Icon(Icons.warning_amber, size: 14, color: cs.tertiary),
                              const SizedBox(width: 4),
                              Text(
                                '${g.warningCount}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.tertiary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            Container(
              padding: const EdgeInsets.all(12),
              color: cs.surfaceContainerHighest,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: cs.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Execution Details',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: cs.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _DetailRow(
                    label: 'Execution ID',
                    value: g.executionId.substring(0, 8),
                  ),
                  _DetailRow(
                    label: 'Started',
                    value: _formatFullTimestamp(g.startTime),
                  ),
                  _DetailRow(
                    label: 'Finished',
                    value: _formatFullTimestamp(g.endTime),
                  ),
                  _DetailRow(
                    label: 'Duration',
                    value: g.durationFormatted,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.list, size: 16, color: cs.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Events (${g.events.length})',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: cs.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...g.events.map((e) => _EventRow(event: e)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    return '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _formatFullTimestamp(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final LogEntry event;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    IconData icon;
    Color color;

    if (!event.success) {
      icon = Icons.error;
      color = cs.error;
    } else {
      switch (event.level) {
        case 'error':
          icon = Icons.error_outline;
          color = cs.error;
          break;
        case 'warn':
          icon = Icons.warning_amber;
          color = cs.tertiary;
          break;
        case 'debug':
          icon = Icons.bug_report;
          color = cs.secondary;
          break;
        default:
          icon = Icons.info_outline;
          color = cs.primary;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              event.message,
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurfaceVariant,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

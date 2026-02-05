import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/router.dart';
import '../../data/models/payload.dart';
import '../../data/models/scheduled_task.dart';
import '../../state/controllers/payloads_controller.dart';
import '../../state/controllers/scheduler_controller.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/empty_state.dart';

class ScheduleScreen extends ConsumerWidget {
  const ScheduleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(schedulerControllerProvider);
    final payloadsAsync = ref.watch(payloadsControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Schedule'),
        actions: [
          IconButton(
            tooltip: 'New schedule',
            onPressed: () => context.go('${const ScheduleRoute().location}/new'),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: tasksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 64, color: Theme.of(context).colorScheme.error),
                const SizedBox(height: 16),
                Text('Failed to load schedules', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text('$e', textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
        data: (tasks) {
          if (tasks.isEmpty) {
            return EmptyState(
              title: 'No schedules configured',
              subtitle: 'Create a schedule to automatically run a payload on a timer or trigger.',
              icon: Icons.schedule,
              action: FilledButton.icon(
                onPressed: () => context.go('${const ScheduleRoute().location}/new'),
                icon: const Icon(Icons.add),
                label: const Text('Create schedule'),
              ),
            );
          }

          final payloads = payloadsAsync.value ?? const <Payload>[];

          String payloadName(String id) {
            for (final p in payloads) {
              if (p.id == id) return p.name;
            }
            return 'Unknown payload';
          }

          final activeCount = tasks.where((t) => t.enabled).length;
          final oneTimeCount = tasks.where((t) => t.trigger == 'one_time').length;

          return Column(
            children: [
              _StatisticsBar(
                totalCount: tasks.length,
                activeCount: activeCount,
                oneTimeCount: oneTimeCount,
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: tasks.length,
                  itemBuilder: (context, i) {
                    final t = tasks[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ScheduleCard(
                        task: t,
                        payloadName: payloadName(t.payloadId),
                        onTap: () => context.go('${const ScheduleRoute().location}/${t.id}/edit'),
                        onToggle: (v) => ref.read(schedulerControllerProvider.notifier).setEnabled(t.id, v),
                        onEdit: () => context.go('${const ScheduleRoute().location}/${t.id}/edit'),
                        onDelete: () async {
                          final ok = await showConfirmDialog(
                            context,
                            title: 'Delete schedule',
                            message: 'Delete "${t.name}"?',
                            confirmLabel: 'Delete',
                            dangerous: true,
                          );
                          if (!ok) return;
                          await ref.read(schedulerControllerProvider.notifier).delete(t.id);
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('${const ScheduleRoute().location}/new'),
        icon: const Icon(Icons.add),
        label: const Text('New Schedule'),
      ),
    );
  }
}

class _StatisticsBar extends StatelessWidget {
  const _StatisticsBar({
    required this.totalCount,
    required this.activeCount,
    required this.oneTimeCount,
  });

  final int totalCount;
  final int activeCount;
  final int oneTimeCount;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _StatChip(
              icon: Icons.schedule,
              label: 'Total',
              value: '$totalCount',
              color: cs.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StatChip(
              icon: Icons.check_circle,
              label: 'Active',
              value: '$activeCount',
              color: cs.secondary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StatChip(
              icon: Icons.event,
              label: 'One-time',
              value: '$oneTimeCount',
              color: cs.secondary,
            ),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({
    required this.task,
    required this.payloadName,
    required this.onTap,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  final ScheduledTask task;
  final String payloadName;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: task.enabled ? 2 : 0,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: task.enabled
                    ? LinearGradient(
                        colors: [
                          cs.primaryContainer.withOpacity(0.3),
                          cs.primaryContainer.withOpacity(0.1),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: task.enabled ? cs.primaryContainer : cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: task.enabled
                              ? [
                                  BoxShadow(
                                    color: cs.primary.withOpacity(0.2),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        child: Icon(
                          _iconFor(task.trigger),
                          color: task.enabled ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              task.name,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                color: task.enabled ? cs.onSurface : cs.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _triggerColor(task.trigger, cs).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: _triggerColor(task.trigger, cs).withOpacity(0.3),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _triggerIconSmall(task.trigger),
                                    size: 12,
                                    color: _triggerColor(task.trigger, cs),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _triggerLabel(task.trigger),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: _triggerColor(task.trigger, cs),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: task.enabled,
                        onChanged: onToggle,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.inventory_2, size: 14, color: cs.onSurfaceVariant),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                payloadName,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        if (task.runAt != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.event, size: 14, color: cs.onSurfaceVariant),
                              const SizedBox(width: 6),
                              Text(
                                _formatRunAt(task.runAt!),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (task.windowStart != null && task.windowEnd != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.access_time, size: 14, color: cs.onSurfaceVariant),
                              const SizedBox(width: 6),
                              Text(
                                'Window: ${task.windowStart}–${task.windowEnd}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (task.lastRunAt != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.history, size: 14, color: cs.primary),
                              const SizedBox(width: 6),
                              Text(
                                'Last run: ${_formatLastRun(task.lastRunAt!)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onEdit,
                          icon: const Icon(Icons.edit, size: 16),
                          label: const Text('Edit'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: onDelete,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: cs.error,
                          side: BorderSide(color: cs.error.withOpacity(0.5)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                        child: const Icon(Icons.delete, size: 18),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(String trigger) {
    switch (trigger) {
      case 'device_connected':
        return Icons.usb;
      case 'app_cold_start':
        return Icons.power_settings_new;
      case 'app_foreground':
      case 'app_launch':
        return Icons.open_in_new;
      default:
        return Icons.schedule;
    }
  }

  IconData _triggerIconSmall(String trigger) {
    switch (trigger) {
      case 'device_connected':
        return Icons.usb;
      case 'app_cold_start':
        return Icons.power_settings_new;
      case 'app_foreground':
      case 'app_launch':
        return Icons.open_in_new;
      default:
        return Icons.event;
    }
  }

  Color _triggerColor(String trigger, ColorScheme cs) {
    switch (trigger) {
      case 'device_connected':
        return cs.primary;
      case 'app_cold_start':
        return cs.primary;
      case 'app_foreground':
      case 'app_launch':
        return cs.primary;
      default:
        return cs.primary;
    }
  }

  String _triggerLabel(String trigger) {
    switch (trigger) {
      case 'device_connected':
        return 'SESSION ARMED';
      case 'app_cold_start':
        return 'APP START';
      case 'app_foreground':
      case 'app_launch':
        return 'APP OPEN';
      case 'one_time':
        return 'ONE-TIME';
      default:
        return trigger.toUpperCase();
    }
  }

  String _formatRunAt(DateTime dt) {
    final now = DateTime.now();
    final diff = dt.difference(now);

    if (diff.isNegative) {
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }

    if (diff.inMinutes < 60) {
      return 'In ${diff.inMinutes}m';
    }
    if (diff.inHours < 24) {
      return 'In ${diff.inHours}h ${diff.inMinutes % 60}m';
    }
    if (diff.inDays < 7) {
      return 'In ${diff.inDays}d';
    }

    return '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _formatLastRun(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    return '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

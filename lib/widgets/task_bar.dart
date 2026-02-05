import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../app/router.dart';
import '../state/controllers/execution_controller.dart';
import '../state/controllers/hid_status_controller.dart';

class TaskBarExpandedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
  void setExpanded(bool value) => state = value;
}

final taskBarExpandedProvider = NotifierProvider<TaskBarExpandedNotifier, bool>(TaskBarExpandedNotifier.new);

class TaskBar extends ConsumerWidget {
  const TaskBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expanded = ref.watch(taskBarExpandedProvider);
    final exec = ref.watch(executionControllerProvider);
    final hid = ref.watch(hidStatusControllerProvider);
    final cs = Theme.of(context).colorScheme;
    final bg = cs.surfaceContainerHighest;

    final title = exec.isRunning
        ? 'Executing: ${exec.payloadName ?? 'payload'}'
        : (exec.success == null
            ? 'Ready'
            : (exec.success == true ? 'Last run: success' : 'Last run: error'));

    final subtitle = exec.isRunning
        ? '${(exec.progress * 100).clamp(0, 100).toStringAsFixed(0)}% • ${exec.status}'
        : exec.status;

    return Material(
      color: bg,
      child: InkWell(
        onTap: () => ref.read(taskBarExpandedProvider.notifier).toggle(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          height: expanded ? 120 : 56,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _StatusDot(ok: hid.rootAvailable && hid.hidSupported),
              const SizedBox(width: 10),
              Expanded(
                child: expanded
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _chip(
                                  context,
                                  icon: Icons.list_alt,
                                  label: 'Logs',
                                  onTap: () => context.push(const LogsRoute().location),
                                ),
                                const SizedBox(width: 8),
                                _chip(
                                  context,
                                  icon: Icons.phone_android,
                                  label: 'Device',
                                  onTap: () => context.push(const DeviceRoute().location),
                                ),
                                const SizedBox(width: 8),
                                _chip(
                                  context,
                                  icon: hid.sessionArmed ? Icons.lock_open : Icons.lock_outline,
                                  label: hid.sessionArmed ? 'Armed' : 'Disarmed',
                                  onTap: () => ref.read(hidStatusControllerProvider.notifier).toggleSessionArmed(),
                                ),
                                if (exec.isRunning) ...[
                                  const SizedBox(width: 8),
                                  _chip(
                                    context,
                                    icon: Icons.stop,
                                    label: 'Stop',
                                    onTap: () => ref.read(executionControllerProvider.notifier).stop(),
                                    dangerous: true,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(width: 10),
              Icon(expanded ? Icons.expand_more : Icons.expand_less, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool dangerous = false,
  }) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: dangerous ? cs.errorContainer : cs.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: dangerous ? cs.onErrorContainer : null),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: dangerous ? cs.onErrorContainer : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.ok});

  final bool ok;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = ok ? cs.primary : cs.error;

    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

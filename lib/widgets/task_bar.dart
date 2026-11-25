import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../app/router.dart';
import '../data/models/execution_outcome.dart';
import 'arm_profile_sheet.dart';
import '../state/controllers/execution_controller.dart';
import '../state/controllers/hid_status_controller.dart';
import '../state/controllers/run_observation_controller.dart';
import 'run_status_text.dart';

class TaskBarExpandedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
  void setExpanded(bool value) => state = value;
}

final taskBarExpandedProvider = NotifierProvider<TaskBarExpandedNotifier, bool>(
  TaskBarExpandedNotifier.new,
);

class TaskBar extends ConsumerWidget {
  const TaskBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expanded = ref.watch(taskBarExpandedProvider);
    final exec = ref.watch(executionControllerProvider);
    final live = ref.watch(runObservationProvider);
    final observation = live?.id == exec.executionId ? live : null;
    final hid = ref.watch(hidStatusControllerProvider);
    final cs = Theme.of(context).colorScheme;
    final bg = cs.surfaceContainerHighest;
    final outcome = exec.outcome;
    final outcomeIcon = switch (outcome) {
      ExecutionOutcome.completed => Icons.check_circle_outline,
      ExecutionOutcome.stopped => Icons.stop_circle_outlined,
      ExecutionOutcome.timedOut => Icons.timer_off_outlined,
      ExecutionOutcome.failed => Icons.error_outline,
      ExecutionOutcome.interrupted => Icons.remove_circle_outline,
      null => null,
    };

    final title = exec.isRunning
        ? 'Executing: ${exec.payloadName ?? 'payload'}'
        : outcome == null
        ? 'Execution'
        : 'Last run: ${outcome.label}';

    final subtitle = exec.isRunning
        ? observation?.determinate == true && observation?.waitUntil == null
            ? '${(exec.progress * 100).round()}% · ${exec.status}'
            : exec.status
        : outcome == null || exec.status == outcome.label
        ? null
        : exec.status;
    final buttonPromptId = exec.isRunning && !exec.stopRequested ? exec.buttonPromptId : null;
    final showScriptButton = exec.isRunning && !exec.stopRequested && exec.scriptButtonAvailable;
    final Object? pulseKey;
    if (exec.stopRequested) {
      pulseKey = null;
    } else if (exec.isRunning && exec.activityStep > 0) {
      pulseKey = exec.activityIndicatorEnabled ? (exec.executionId, 'activity', exec.activityStep) : null;
    } else {
      pulseKey = exec.systemIndicatorEnabled && exec.systemIndicatorStep > 0
          ? (exec.executionId, 'system', exec.systemIndicatorStep)
          : null;
    }

    return Material(
      color: bg,
      child: InkWell(
        onTap: () => ref.read(taskBarExpandedProvider.notifier).toggle(),
        child: AnimatedSize(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 220),
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _StatusDot(
                  ok: hid.rootAvailable && hid.hidSupported,
                  pulseKey: pulseKey,
                ),
                if (!exec.isRunning && outcomeIcon != null) ...[
                  const SizedBox(width: 6),
                  Icon(
                    outcomeIcon,
                    size: 16,
                    color: switch (outcome) {
                      ExecutionOutcome.completed => cs.primary,
                      ExecutionOutcome.failed => cs.error,
                      _ => cs.onSurfaceVariant,
                    },
                  ),
                ],
                if (exec.isRunning && exec.scriptIndicator != ScriptIndicator.off) ...[
                  const SizedBox(width: 6),
                  Semantics(
                    label: 'Script indicator: ${exec.scriptIndicator.name}',
                    child: Icon(
                      Icons.circle,
                      size: 10,
                      color: exec.scriptIndicator == ScriptIndicator.red ? cs.error : Colors.green,
                    ),
                  ),
                ],
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        RunStatusText(
                          status: subtitle,
                          observation: observation,
                          maxLines: exec.inputReleaseUnconfirmed ? null : 1,
                          style: const TextStyle(fontSize: 11, height: 1.2),
                        ),
                      ],
                      if (buttonPromptId != null || showScriptButton) ...[
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          children: [
                            FilledButton(
                              onPressed: () {
                                final controller = ref.read(executionControllerProvider.notifier);
                                if (buttonPromptId == null) {
                                  controller.pressScriptButton(exec.executionId);
                                } else {
                                  controller.confirmButtonPrompt(buttonPromptId);
                                }
                              },
                              child: Text(buttonPromptId == null ? 'Press button' : 'Continue'),
                            ),
                            TextButton(
                              onPressed: () => ref
                                  .read(executionControllerProvider.notifier)
                                  .stop(),
                              child: const Text('Stop'),
                            ),
                          ],
                        ),
                      ],
                      if (expanded) ...[
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _chip(
                                context,
                                icon: Icons.list_alt,
                                label: 'Logs',
                                onTap: () =>
                                    context.push(const LogsRoute().location),
                              ),
                              const SizedBox(width: 8),
                              _chip(
                                context,
                                icon: Icons.phone_android,
                                label: 'Device',
                                onTap: () =>
                                    context.push(const DeviceRoute().location),
                              ),
                              const SizedBox(width: 8),
                              _chip(
                                context,
                                icon: hid.sessionArmed
                                    ? Icons.lock_open
                                    : Icons.lock_outline,
                                label: hid.sessionArmed ? 'Disarm' : 'Arm',
                                onTap: () => toggleUsbSession(context, ref),
                              ),
                              if (exec.isRunning && buttonPromptId == null && !showScriptButton) ...[
                                const SizedBox(width: 8),
                                _chip(
                                  context,
                                  icon: Icons.stop,
                                  label: 'Stop',
                                  onTap: () => ref
                                      .read(
                                        executionControllerProvider.notifier,
                                      )
                                      .stop(),
                                  dangerous: true,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  expanded ? Icons.expand_more : Icons.expand_less,
                  size: 20,
                ),
              ],
            ),
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
        constraints: const BoxConstraints(minHeight: 48),
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
  const _StatusDot({required this.ok, required this.pulseKey});

  final bool ok;
  final Object? pulseKey;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = ok ? cs.primary : cs.error;

    final dot = Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    if (!ok || pulseKey == null || MediaQuery.disableAnimationsOf(context)) return dot;
    return TweenAnimationBuilder<double>(
      key: ValueKey(pulseKey),
      tween: Tween<double>(begin: 0.45, end: 1),
      duration: const Duration(milliseconds: 220),
      builder: (context, opacity, child) => Opacity(opacity: opacity, child: child),
      child: dot,
    );
  }
}

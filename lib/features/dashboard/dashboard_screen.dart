import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../data/models/payload.dart';
import '../../data/models/usb_restore_phase.dart';
import '../../state/controllers/app_settings_controller.dart';
import '../../state/controllers/execution_controller.dart';
import '../../state/controllers/run_observation_controller.dart';
import '../../widgets/run_status_text.dart';
import '../../state/controllers/hid_status_controller.dart';
import '../../state/controllers/host_os_controller.dart';
import '../../state/controllers/payloads_controller.dart';
import '../../state/controllers/scheduler_controller.dart';
import '../../widgets/section_header.dart';
import '../../widgets/host_os_label.dart';
import '../../widgets/arm_profile_sheet.dart';
import '../../widgets/root_required_card.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  Future<void> _armIfNeeded(WidgetRef ref) async {
    final hid = ref.read(hidStatusControllerProvider);
    if (hid.sessionArmed || hid.usbRestoring) return;

    final s = ref.read(appSettingsControllerProvider).value;
    final lastType = (s?.lastProfileType ?? 'composite').toLowerCase();

    final controller = ref.read(hidStatusControllerProvider.notifier);
    switch (lastType) {
      case 'keyboard':
        await controller.activateKeyboard();
        break;
      case 'mouse':
        await controller.activateMouse();
        break;
      case 'composite':
      default:
        await controller.activateComposite();
        break;
    }
  }

  Future<void> _runRecentPayload(WidgetRef ref, Payload payload) async {
    final exec = ref.read(executionControllerProvider);
    if (exec.isRunning) return;

    await _armIfNeeded(ref);

    final hidNow = ref.read(hidStatusControllerProvider);
    if (!hidNow.sessionArmed) return;

    await ref.read(executionControllerProvider.notifier).runPayload(
          payload,
          const <String, String>{},
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hid = ref.watch(hidStatusControllerProvider);
    final payloadsAsync = ref.watch(payloadsControllerProvider);
    final exec = ref.watch(executionControllerProvider);

    if (hid.isInitializing) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('TapDucky'),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(height: 20),
              Text(
                'Checking system status...',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      );
    }

    if (!hid.rootAvailable && !hid.usbRestoring) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('TapDucky'),
          actions: [
            IconButton(
              tooltip: 'Device Info',
              onPressed: () => context.push(const DeviceRoute().location),
              icon: const Icon(Icons.phone_android),
            ),
          ],
        ),
        body: const SingleChildScrollView(
          child: RootRequiredCard(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('TapDucky'),
        actions: [
          if (exec.isRunning)
            IconButton(
              tooltip: 'Panic Stop',
              onPressed: () => ref.read(executionControllerProvider.notifier).panicStop(),
              icon: const Icon(Icons.warning_amber_rounded),
              color: Theme.of(context).colorScheme.error,
            ),
          IconButton(
            tooltip: 'Logs',
            onPressed: () => context.push(const LogsRoute().location),
            icon: const Icon(Icons.list_alt),
          ),
          IconButton(
            tooltip: 'Device',
            onPressed: () => context.push(const DeviceRoute().location),
            icon: const Icon(Icons.phone_android),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(payloadsControllerProvider);
          ref.invalidate(schedulerControllerProvider);
          await Future.delayed(const Duration(milliseconds: 500));
        },
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _HeroStatusCard(
                hid: hid,
                exec: exec,
                onArmToggle: () => toggleUsbSession(context, ref),
                onStop: exec.isRunning ? () => ref.read(executionControllerProvider.notifier).stop() : null,
              ),
            ),
            const SizedBox(height: 20),
            SectionHeader(
              title: 'Recent payloads',
              trailing: payloadsAsync.value?.isNotEmpty == true
                  ? TextButton(
                      onPressed: () => context.go(const PayloadsRoute().location),
                      child: const Text('View all'),
                    )
                  : null,
            ),
            payloadsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, st) => Padding(
                padding: const EdgeInsets.all(20),
                child: Text('Failed to load payloads: $e'),
              ),
              data: (payloads) {
                final top = payloads.take(5).toList();
                if (top.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _EmptyPayloadsCard(
                      onCreateTap: () => context.go('${const PayloadsRoute().location}/new'),
                      onOpenStoreTap: () => context.go(const PayloadsStoreRoute().location),
                    ),
                  );
                }

                return Column(
                  children: [
                    for (final p in top)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: _PayloadCard(
                          payload: p,
                          onTap: () => context.go('${const PayloadsRoute().location}/${p.id}/edit'),
                          onRun: exec.isRunning || hid.usbRestoring
                              ? null
                              : () {
                                  unawaited(_runRecentPayload(ref, p));
                                },
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroStatusCard extends ConsumerWidget {
  const _HeroStatusCard({
    required this.hid,
    required this.exec,
    required this.onArmToggle,
    required this.onStop,
  });

  final HidStatus hid;
  final ExecutionState exec;
  final VoidCallback onArmToggle;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final subtitle = _statusDetail();
    final host = ref.watch(hostOsControllerProvider);
    final restorePhase = hid.usbRestoring && hid.usbRestorePhase == UsbRestorePhase.idle
        ? UsbRestorePhase.restoring
        : hid.usbRestorePhase;
    final restoreBlocked = hid.usbRestoring && (!hid.rootAvailable || !hid.hidSupported);
    final showStatusIcon = restorePhase == UsbRestorePhase.idle ||
        MediaQuery.textScalerOf(context).scale(16) <= 24;
    final live = ref.watch(runObservationProvider);
    final observation = live?.id == exec.executionId ? live : null;
    final showProgress = observation?.determinate == true && observation?.waitUntil == null;

    String statusText;
    IconData statusIcon;
    Color statusColor;

    if (restoreBlocked) {
      statusText = 'USB restoration paused';
      statusIcon = Icons.error_outline;
      statusColor = cs.error;
    } else if (restorePhase != UsbRestorePhase.idle) {
      statusText = switch (restorePhase) {
        UsbRestorePhase.verifying => 'Verifying original USB settings...',
        UsbRestorePhase.waitingForUnplug ||
        UsbRestorePhase.verified ||
        UsbRestorePhase.finished =>
          'Session disarmed',
        UsbRestorePhase.failed => 'USB restoration incomplete',
        _ => 'Restoring original USB settings...',
      };
      (statusIcon, statusColor) = switch (restorePhase) {
        UsbRestorePhase.waitingForUnplug ||
        UsbRestorePhase.verified ||
        UsbRestorePhase.finished =>
          (Icons.lock_outline, cs.tertiary),
        UsbRestorePhase.failed => (Icons.error_outline, cs.error),
        _ => (Icons.settings_input_component, cs.tertiary),
      };
    } else if (!hid.rootAvailable || !hid.hidSupported) {
      statusText = 'System Not Ready';
      statusIcon = Icons.error_outline;
      statusColor = cs.error;
    } else if (!hid.sessionArmed) {
      statusText = 'Session disarmed';
      statusIcon = Icons.lock_outline;
      statusColor = cs.tertiary;
    } else if (hid.pcConnected && (!hid.gadgetBound || !hid.deviceConnected)) {
      statusText = 'USB host connected · HID pending';
      statusIcon = Icons.settings_input_component;
      statusColor = cs.tertiary;
    } else if (!hid.gadgetBound || !hid.deviceConnected) {
      statusText = 'Armed · Waiting for host';
      statusIcon = Icons.usb_off;
      statusColor = cs.warning;
    } else if (exec.isRunning) {
      statusText = 'Executing';
      statusIcon = Icons.play_arrow;
      statusColor = cs.primary;
    } else {
      statusText = 'Ready';
      statusIcon = Icons.check_circle;
      statusColor = cs.success;
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                if (showStatusIcon) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(statusIcon, size: 32, color: statusColor),
                  ),
                  const SizedBox(width: 16),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        liveRegion: restorePhase != UsbRestorePhase.idle,
                        child: Text(
                          statusText,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
                      ],
                      if (hid.sessionArmed && hid.pcConnected) ...[
                        const SizedBox(height: 4),
                        HostOsLabel(
                          diagnostic: host,
                          showTitle: true,
                          detecting: hid.isDetectingHostOs,
                          detectionAvailable: hid.hostOsDetectionAvailable,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (exec.isRunning) ...[
              const SizedBox(height: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(
                        child: Text(
                          exec.payloadName ?? 'Running',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (showProgress) ...[
                        const SizedBox(width: 12),
                        Text(
                          '${(exec.progress * 100).round()}%',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: cs.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (showProgress) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: exec.progress),
                  ],
                  const SizedBox(height: 4),
                  RunStatusText(
                    status: exec.status,
                    observation: observation,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ],
            if (restoreBlocked || restorePhase == UsbRestorePhase.failed) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  if (restoreBlocked)
                    FilledButton(
                      onPressed: () => ref.invalidate(hidStatusProvider),
                      child: const Text('Recheck device'),
                    )
                  else if (hid.rootAvailable && hid.hidSupported)
                    FilledButton(
                      onPressed: () => _retryRestoration(context, ref),
                      child: const Text('Retry restoration'),
                    ),
                  TextButton(
                    onPressed: () => _showRestorationDetails(context),
                    child: const Text('Details'),
                  ),
                ],
              ),
            ],
            if (!hid.usbRestoring || exec.isRunning) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  if (!hid.usbRestoring)
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: hid.rootAvailable && hid.hidSupported
                            ? onArmToggle
                            : null,
                        icon: Icon(hid.sessionArmed ? Icons.lock_open : Icons.lock_outline),
                        label: Text(hid.sessionArmed ? 'Disarm' : 'Arm Session'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  if (exec.isRunning) ...[
                    if (!hid.usbRestoring) const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: onStop,
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop'),
                      style: FilledButton.styleFrom(
                        backgroundColor: cs.error,
                        foregroundColor: cs.onError,
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String? _statusDetail() {
    if (hid.usbRestoring && !hid.rootAvailable) {
      return 'Grant TapDucky root access, then recheck the device.';
    }
    if (hid.usbRestoring && !hid.hidSupported) {
      return 'Android cannot access USB gadget support. Recheck once it is available.';
    }
    if (hid.usbRestorePhase == UsbRestorePhase.waitingForUnplug) {
      return 'USB cleanup is deferred while the cable is connected.';
    }
    if (hid.usbRestorePhase == UsbRestorePhase.finished ||
        hid.usbRestorePhase == UsbRestorePhase.verified) {
      return null;
    }
    if (!hid.rootAvailable) return 'Root access required';
    if (!hid.hidSupported) return 'USB gadget support required';
    if (hid.usbRestorePhase == UsbRestorePhase.failed) {
      return hid.pcConnected
          ? 'Unplug the cable, then retry restoration.'
          : 'Retry to restore the saved USB settings.';
    }
    if (hid.usbRestoring) return null;
    final message = hid.message;
    if (message != null && message.isNotEmpty) return message;
    if (!hid.sessionArmed || exec.isRunning) return null;
    final profile = hid.activeProfileType;
    return profile == null ? null : GadgetProfileType.fromName(profile).label;
  }

  Future<void> _retryRestoration(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(hidStatusControllerProvider.notifier).deactivate();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not retry USB restoration')),
      );
    }
  }

  Future<void> _showRestorationDetails(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('USB restoration details'),
      content: SingleChildScrollView(
        child: SelectableText(hid.message ?? 'Android reported no details.'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

class _PayloadCard extends StatelessWidget {
  const _PayloadCard({
    required this.payload,
    required this.onTap,
    required this.onRun,
  });

  final Payload payload;
  final VoidCallback onTap;
  final VoidCallback? onRun;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  payload.isBuiltin ? Icons.lock : Icons.code,
                  color: cs.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      payload.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (payload.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        payload.description,
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (payload.tags.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: payload.tags.take(3).map<Widget>((tag) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: cs.secondaryContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              tag,
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onSecondaryContainer,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              IconButton.filledTonal(
                onPressed: onRun,
                icon: const Icon(Icons.play_arrow),
                tooltip: 'Run',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyPayloadsCard extends StatelessWidget {
  const _EmptyPayloadsCard({required this.onCreateTap, required this.onOpenStoreTap});

  final VoidCallback onCreateTap;
  final VoidCallback onOpenStoreTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.inventory_2_outlined, size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              'No payloads yet',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onCreateTap,
              icon: const Icon(Icons.add),
              label: const Text('Create Payload'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onOpenStoreTap,
              icon: const Icon(Icons.cloud_download),
              label: const Text('Browse store'),
            ),
          ],
        ),
      ),
    );
  }
}

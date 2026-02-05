import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../data/models/payload.dart';
import '../../state/controllers/app_settings_controller.dart';
import '../../state/controllers/execution_controller.dart';
import '../../state/controllers/hid_status_controller.dart';
import '../../state/controllers/payloads_controller.dart';
import '../../state/controllers/scheduler_controller.dart';
import '../../widgets/section_header.dart';
import '../settings/profile_selector_dialog.dart';
import '../../widgets/root_required_card.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  Future<void> _armIfNeeded(WidgetRef ref) async {
    final hid = ref.read(hidStatusControllerProvider);
    if (hid.sessionArmed) return;

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
    final settings = ref.watch(appSettingsControllerProvider).value;
    final payloadsAsync = ref.watch(payloadsControllerProvider);
    final schedulesAsync = ref.watch(schedulerControllerProvider);
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
              const SizedBox(height: 8),
              Text(
                'Verifying root access and USB gadget support',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
                    ),
              ),
            ],
          ),
        ),
      );
    }

    if (!hid.rootAvailable) {
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
                onArmToggle: () async {
                  if (hid.sessionArmed) {
                    await ref.read(hidStatusControllerProvider.notifier).deactivate();
                    return;
                  }

                  final s = ref.read(appSettingsControllerProvider).value;
                  final lastType = s?.lastProfileType ?? 'composite';

                  GadgetProfileType initialSelection;
                  switch (lastType.toLowerCase()) {
                    case 'keyboard':
                      initialSelection = GadgetProfileType.keyboard;
                      break;
                    case 'mouse':
                      initialSelection = GadgetProfileType.mouse;
                      break;
                    default:
                      initialSelection = GadgetProfileType.composite;
                  }

                  final selected = await showProfileSelectorDialog(
                    context,
                    initialSelection: initialSelection,
                  );

                  if (selected == null) return;

                  await ref.read(appSettingsControllerProvider.notifier).setLastProfileType(selected.name);

                  final controller = ref.read(hidStatusControllerProvider.notifier);
                  switch (selected) {
                    case GadgetProfileType.keyboard:
                      await controller.activateKeyboard();
                      break;
                    case GadgetProfileType.mouse:
                      await controller.activateMouse();
                      break;
                    case GadgetProfileType.composite:
                      await controller.activateComposite();
                      break;
                  }
                },
                onStop: exec.isRunning ? () => ref.read(executionControllerProvider.notifier).stop() : null,
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _StatusChipsRow(
                hid: hid,
                loggingEnabled: settings?.enableLogging ?? true,
                scheduleCount: schedulesAsync.value?.length ?? 0,
              ),
            ),
            const SizedBox(height: 20),
            SectionHeader(
              title: 'Recent Payloads',
              trailing: TextButton.icon(
                onPressed: () => context.go('${const PayloadsRoute().location}/new'),
                icon: const Icon(Icons.add),
                label: const Text('New'),
              ),
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
                          onRun: exec.isRunning
                              ? null
                              : () {
                                  unawaited(_runRecentPayload(ref, p));
                                },
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: TextButton(
                        onPressed: () => context.go(const PayloadsRoute().location),
                        child: const Text('View all payloads'),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            SectionHeader(
              title: 'Quick Access',
              trailing: IconButton(
                onPressed: () => _showQuickActionsSheet(context),
                icon: const Icon(Icons.more_horiz),
                tooltip: 'More actions',
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _QuickAccessGrid(
                onScheduleTap: () => context.go(const ScheduleRoute().location),
                onSettingsTap: () => context.go(const SettingsRoute().location),
                onLogsTap: () => context.push(const LogsRoute().location),
                onDeviceTap: () => context.push(const DeviceRoute().location),
              ),
            ),
            if (settings?.showPowerUserHints ?? true) ...[
              const SizedBox(height: 20),
              const SectionHeader(title: 'System Status'),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: _SystemStatusCard(isDebug: !kReleaseMode, hid: hid),
              ),
            ],
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go(const ExecuteRoute().location),
        icon: const Icon(Icons.play_arrow),
        label: const Text('Execute'),
      ),
    );
  }

  void _showQuickActionsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.inventory_2),
              title: const Text('Payload Manager'),
              subtitle: const Text('Create, edit, import, export'),
              onTap: () {
                Navigator.pop(context);
                context.go(const PayloadsRoute().location);
              },
            ),
            ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('Scheduler'),
              subtitle: const Text('Time windows & triggers'),
              onTap: () {
                Navigator.pop(context);
                context.go(const ScheduleRoute().location);
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Settings'),
              subtitle: const Text('Theme, logging, HID config'),
              onTap: () {
                Navigator.pop(context);
                context.go(const SettingsRoute().location);
              },
            ),
            ListTile(
              leading: const Icon(Icons.list_alt),
              title: const Text('Logs'),
              subtitle: const Text('Execution history'),
              onTap: () {
                Navigator.pop(context);
                context.push(const LogsRoute().location);
              },
            ),
            ListTile(
              leading: const Icon(Icons.phone_android),
              title: const Text('Device Info'),
              subtitle: const Text('Diagnostics & compatibility'),
              onTap: () {
                Navigator.pop(context);
                context.push(const DeviceRoute().location);
              },
            ),
            const SizedBox(height: 8),
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

    String statusText;
    IconData statusIcon;
    Color statusColor;

    if (!hid.rootAvailable || !hid.hidSupported) {
      statusText = 'System Not Ready';
      statusIcon = Icons.error_outline;
      statusColor = cs.error;
    } else if (!hid.sessionArmed) {
      statusText = 'Session Disarmed';
      statusIcon = Icons.lock_outline;
      statusColor = cs.tertiary;
    } else if (!hid.deviceConnected) {
      statusText = 'Waiting for Host';
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
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(statusIcon, size: 32, color: statusColor),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        statusText,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _getStatusSubtitle(),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                      ),
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        exec.payloadName ?? 'Running',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${(exec.progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: cs.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: exec.progress),
                  const SizedBox(height: 4),
                  Text(
                    exec.status,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: (hid.rootAvailable && hid.hidSupported) ? onArmToggle : null,
                    icon: Icon(hid.sessionArmed ? Icons.lock_open : Icons.lock_outline),
                    label: Text(hid.sessionArmed ? 'Disarm' : 'Arm Session'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                if (exec.isRunning) ...[
                  const SizedBox(width: 12),
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
        ),
      ),
    );
  }

  String _getStatusSubtitle() {
    if (!hid.rootAvailable) return 'Root access required';
    if (!hid.hidSupported) return 'USB gadget not supported';
    if (!hid.sessionArmed) return 'Tap to activate USB gadget';
    if (!hid.deviceConnected) return 'Connect USB cable to target';
    if (exec.isRunning) return 'Payload in progress';
    return 'System operational';
  }
}

class _StatusChipsRow extends StatelessWidget {
  const _StatusChipsRow({
    required this.hid,
    required this.loggingEnabled,
    required this.scheduleCount,
  });

  final HidStatus hid;
  final bool loggingEnabled;
  final int scheduleCount;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    String profileDisplay = 'None';
    if (hid.activeProfileType != null) {
      switch (hid.activeProfileType!.toLowerCase()) {
        case 'keyboard':
          profileDisplay = 'Keyboard';
          break;
        case 'mouse':
          profileDisplay = 'Mouse';
          break;
        case 'composite':
          profileDisplay = 'Composite';
          break;
        default:
          profileDisplay = hid.activeProfileType!;
      }
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _StatusChip(
          icon: Icons.security,
          label: 'Root',
          value: hid.rootAvailable ? 'OK' : 'N/A',
          ok: hid.rootAvailable,
        ),
        _StatusChip(
          icon: Icons.usb,
          label: 'HID',
          value: hid.hidSupported ? 'OK' : 'N/A',
          ok: hid.hidSupported,
        ),
        _StatusChip(
          icon: Icons.devices,
          label: 'Profile',
          value: profileDisplay,
          ok: hid.sessionArmed,
        ),
        _StatusChip(
          icon: Icons.schedule,
          label: 'Schedules',
          value: '$scheduleCount',
          ok: scheduleCount > 0,
        ),
        _StatusChip(
          icon: Icons.article_outlined,
          label: 'Logging',
          value: loggingEnabled ? 'ON' : 'OFF',
          ok: loggingEnabled,
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.ok,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = ok ? cs.primary : cs.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: ok ? cs.primaryContainer.withOpacity(0.5) : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: ok ? cs.primary.withOpacity(0.3) : cs.outlineVariant,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: color.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }
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
            const SizedBox(height: 8),
            Text(
              'Create your first payload to get started',
              style: TextStyle(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
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
              label: const Text('Import from GitHub Store'),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAccessGrid extends StatelessWidget {
  const _QuickAccessGrid({
    required this.onScheduleTap,
    required this.onSettingsTap,
    required this.onLogsTap,
    required this.onDeviceTap,
  });

  final VoidCallback onScheduleTap;
  final VoidCallback onSettingsTap;
  final VoidCallback onLogsTap;
  final VoidCallback onDeviceTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 600 ? 4 : 2;
        return GridView.count(
          crossAxisCount: crossAxisCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.3,
          children: [
            _QuickAccessTile(
              icon: Icons.schedule,
              label: 'Schedule',
              onTap: onScheduleTap,
            ),
            _QuickAccessTile(
              icon: Icons.settings,
              label: 'Settings',
              onTap: onSettingsTap,
            ),
            _QuickAccessTile(
              icon: Icons.list_alt,
              label: 'Logs',
              onTap: onLogsTap,
            ),
            _QuickAccessTile(
              icon: Icons.phone_android,
              label: 'Device',
              onTap: onDeviceTap,
            ),
          ],
        );
      },
    );
  }
}

class _QuickAccessTile extends StatelessWidget {
  const _QuickAccessTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 32, color: cs.primary),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SystemStatusCard extends StatelessWidget {
  const _SystemStatusCard({required this.isDebug, required this.hid});

  final bool isDebug;
  final HidStatus hid;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                const Text(
                  'Operational Flow',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _FlowStep(
              number: '1',
              text: 'Arm HID session (activates USB gadget)',
              completed: hid.sessionArmed,
            ),
            const SizedBox(height: 8),
            _FlowStep(
              number: '2',
              text: 'Connect USB cable to target device',
              completed: hid.deviceConnected,
            ),
            const SizedBox(height: 8),
            const _FlowStep(
              number: '3',
              text: 'Select payload and configure parameters',
              completed: false,
            ),
            const SizedBox(height: 8),
            const _FlowStep(
              number: '4',
              text: 'Execute and review logs',
              completed: false,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    hid.rootAvailable ? Icons.check_circle : Icons.error_outline,
                    size: 18,
                    color: hid.rootAvailable ? cs.primary : cs.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      hid.rootAvailable
                          ? 'Root available. USB gadget backend is active.'
                          : 'Root not available. Check Device screen for diagnostics.',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
            if (hid.udcList.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'UDC: ${hid.udcList.join(", ")}',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FlowStep extends StatelessWidget {
  const _FlowStep({
    required this.number,
    required this.text,
    required this.completed,
  });

  final String number;
  final String text;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: completed ? cs.primary : cs.surfaceContainerHighest,
            shape: BoxShape.circle,
            border: Border.all(
              color: completed ? cs.primary : cs.outlineVariant,
              width: 2,
            ),
          ),
          child: Center(
            child: completed
                ? Icon(Icons.check, size: 14, color: cs.onPrimary)
                : Text(
                    number,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: completed ? cs.onSurface : cs.onSurfaceVariant,
              fontWeight: completed ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/models/device_snapshot.dart';
import '../../state/controllers/hid_status_controller.dart';
import '../../state/providers.dart';

final deviceSnapshotProvider = FutureProvider<DeviceSnapshot>((ref) async {
  final svc = ref.read(deviceInfoServiceProvider);
  return svc.getSnapshot();
});

final deviceDiagnosticsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final svc = ref.read(platformGadgetServiceProvider);
  return svc.getDiagnostics();
});

class DeviceScreen extends ConsumerWidget {
  const DeviceScreen({super.key});

  void _copyToClipboard(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hid = ref.watch(hidStatusControllerProvider);
    final snapshotAsync = ref.watch(deviceSnapshotProvider);
    final diagnosticsAsync = ref.watch(deviceDiagnosticsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Information'),
        actions: [
          IconButton(
            tooltip: 'Refresh diagnostics',
            onPressed: () => ref.invalidate(deviceDiagnosticsProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: snapshotAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => _ErrorView(error: e.toString()),
        data: (snap) {
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(deviceSnapshotProvider);
              ref.invalidate(deviceDiagnosticsProvider);
              await Future.delayed(const Duration(milliseconds: 500));
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // System Status Hero Card
                _SystemStatusHeroCard(hid: hid, snapshot: snap),
                const SizedBox(height: 16),

                // HID Readiness
                _SectionTitle(
                  icon: Icons.security,
                  title: 'HID Readiness',
                  subtitle: 'USB gadget system status',
                ),
                const SizedBox(height: 12),
                _HidReadinessCard(hid: hid),
                const SizedBox(height: 24),

                // UDC State (if available)
                if (hid.udcState != null) ...[
                  _SectionTitle(
                    icon: Icons.usb,
                    title: 'USB Device Controller',
                    subtitle: 'Real-time connection state',
                  ),
                  const SizedBox(height: 12),
                  _UdcStateCard(hid: hid),
                  const SizedBox(height: 24),
                ],

                // Device Information
                _SectionTitle(
                  icon: Icons.phone_android,
                  title: 'Device Information',
                  subtitle: 'Hardware & software details',
                ),
                const SizedBox(height: 12),
                _DeviceInfoCard(
                  snapshot: snap,
                  onCopy: (text, label) => _copyToClipboard(context, text, label),
                ),
                const SizedBox(height: 24),

                // Backend Diagnostics
                _SectionTitle(
                  icon: Icons.bug_report,
                  title: 'Backend Diagnostics',
                  subtitle: 'Kernel & system configuration',
                ),
                const SizedBox(height: 12),
                diagnosticsAsync.when(
                  loading: () => const Card(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
                  error: (e, st) => _ErrorCard(error: e.toString()),
                  data: (diag) => _DiagnosticsCard(diagnostics: diag),
                ),
                const SizedBox(height: 24),

                // Compatibility Notes
                _SectionTitle(
                  icon: Icons.info_outline,
                  title: 'Compatibility Notes',
                  subtitle: 'Requirements & recommendations',
                ),
                const SizedBox(height: 12),
                _CompatibilityCard(isPhysical: snap.isPhysicalDevice),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SystemStatusHeroCard extends StatelessWidget {
  final HidStatus hid;
  final DeviceSnapshot snapshot;

  const _SystemStatusHeroCard({
    required this.hid,
    required this.snapshot,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isReady = hid.rootAvailable && hid.hidSupported;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isReady
                        ? cs.success.withOpacity(0.1)
                        : cs.error.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isReady ? Icons.check_circle : Icons.error_outline,
                    size: 40,
                    color: isReady ? cs.success : cs.error,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isReady ? 'System Ready' : 'System Not Ready',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isReady
                            ? 'All requirements met for HID operations'
                            : 'Missing required components',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _QuickStat(
                    icon: Icons.phone_android,
                    label: 'Device',
                    value: snapshot.model,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _QuickStat(
                    icon: Icons.android,
                    label: 'Android',
                    value: 'API ${snapshot.sdkInt}',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _QuickStat({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HidReadinessCard extends StatelessWidget {
  final HidStatus hid;

  const _HidReadinessCard({required this.hid});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: Column(
        children: [
          _StatusRow(
            icon: Icons.security,
            label: 'Root Access',
            status: hid.rootAvailable ? 'Available' : 'Unavailable',
            isOk: hid.rootAvailable,
            description: hid.rootAvailable
                ? 'Superuser permissions granted'
                : 'Root access required for USB gadget control',
          ),
          const Divider(height: 1),
          _StatusRow(
            icon: Icons.usb,
            label: 'USB Gadget Support',
            status: hid.hidSupported ? 'Supported' : 'Unsupported',
            isOk: hid.hidSupported,
            description: hid.hidSupported
                ? 'Kernel supports ConfigFS USB gadgets'
                : 'Kernel missing USB gadget/ConfigFS support',
          ),
          const Divider(height: 1),
          _StatusRow(
            icon: hid.sessionArmed ? Icons.lock_open : Icons.lock_outline,
            label: 'Session State',
            status: hid.sessionArmed ? 'Armed' : 'Disarmed',
            isOk: hid.sessionArmed,
            description: hid.sessionArmed
                ? 'USB gadget is active and ready'
                : 'Activate session to enable HID operations',
          ),
          const Divider(height: 1),
          _StatusRow(
            icon: hid.deviceConnected ? Icons.usb : Icons.usb_off,
            label: 'Target Connection',
            status: hid.deviceConnected ? 'Connected' : 'Disconnected',
            isOk: hid.deviceConnected,
            description: hid.deviceConnected
                ? 'USB cable connected to target host'
                : 'Connect USB cable to target device',
          ),
          if (hid.udcList.isNotEmpty) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.developer_board, size: 18, color: cs.primary),
                      const SizedBox(width: 8),
                      const Text(
                        'Available UDC Controllers',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...hid.udcList.map((udc) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: cs.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                udc,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String status;
  final bool isOk;
  final String description;

  const _StatusRow({
    required this.icon,
    required this.label,
    required this.status,
    required this.isOk,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final statusColor = isOk ? cs.success : cs.error;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: statusColor),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: statusColor.withOpacity(0.3),
                        ),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UdcStateCard extends StatelessWidget {
  final HidStatus hid;

  const _UdcStateCard({required this.hid});

  IconData _getStateIcon(String state) {
    switch (state.toLowerCase()) {
      case 'configured':
        return Icons.check_circle;
      case 'not attached':
        return Icons.usb_off;
      case 'attached':
      case 'powered':
      case 'default':
      case 'addressed':
        return Icons.sync;
      default:
        return Icons.help_outline;
    }
  }

  Color _getStateColor(BuildContext context, String state) {
    final cs = Theme.of(context).colorScheme;
    switch (state.toLowerCase()) {
      case 'configured':
        return cs.success;
      case 'not attached':
        return cs.error;
      case 'attached':
      case 'powered':
      case 'default':
      case 'addressed':
        return cs.warning;
      default:
        return cs.onSurfaceVariant;
    }
  }

  String _getStateDescription(String state) {
    switch (state.toLowerCase()) {
      case 'configured':
        return 'Host has enumerated the device. Ready for HID communication.';
      case 'not attached':
        return 'No USB cable connected or host is powered off.';
      case 'attached':
        return 'USB cable connected, waiting for power negotiation.';
      case 'powered':
        return 'Device is powered, waiting for enumeration.';
      case 'default':
        return 'Enumeration started, device is being configured.';
      case 'addressed':
        return 'Device has been addressed by host, configuration in progress.';
      default:
        return 'Unknown UDC state: $state';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final state = hid.udcState!;
    final stateColor = _getStateColor(context, state);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: stateColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: stateColor.withOpacity(0.3),
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _getStateIcon(state),
                    size: 32,
                    color: stateColor,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          state.toUpperCase(),
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            color: stateColor,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _getStateDescription(state),
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'UDC state is polled every 2 seconds when session is active',
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceInfoCard extends StatelessWidget {
  final DeviceSnapshot snapshot;
  final Function(String, String) onCopy;

  const _DeviceInfoCard({
    required this.snapshot,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final info = snapshot.asMap();
    final entries = info.entries.toList();

    return Card(
      child: Column(
        children: [
          for (int i = 0; i < entries.length; i++) ...[
            _InfoRow(
              label: entries[i].key,
              value: entries[i].value ?? 'N/A',
              onCopy: () => onCopy(entries[i].value ?? '', entries[i].key),
            ),
            if (i != entries.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onCopy;

  const _InfoRow({
    required this.label,
    required this.value,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onCopy,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      value,
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                        fontFamily: value.length > 20 ? 'monospace' : null,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.copy, size: 14, color: cs.onSurfaceVariant),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiagnosticsCard extends StatefulWidget {
  final Map<String, dynamic> diagnostics;

  const _DiagnosticsCard({required this.diagnostics});

  @override
  State<_DiagnosticsCard> createState() => _DiagnosticsCardState();
}

class _DiagnosticsCardState extends State<_DiagnosticsCard> {
  bool _kernelExpanded = false;
  bool _pathsExpanded = false;
  bool _rawExpanded = false;

  Map<String, dynamic>? _castMap(dynamic value) {
    if (value == null) return null;
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final kernelConfig = _castMap(widget.diagnostics['kernelConfig']);
    final paths = _castMap(widget.diagnostics['paths']);
    final rootId = widget.diagnostics['rootId']?.toString();
    final udcList =
        (widget.diagnostics['udcList'] as List<dynamic>?)?.cast<String>() ?? [];
    final configfsBases =
        (widget.diagnostics['configfsBases'] as List<dynamic>?)?.cast<String>() ??
            [];
    final existingGadgets =
        (widget.diagnostics['existingGadgetsInConfig'] as List<dynamic>?)
                ?.cast<String>() ??
            [];
    final rawLines =
        (widget.diagnostics['kernelConfigRawFirstLines'] as List<dynamic>?)
                ?.cast<String>() ??
            [];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (rootId != null) ...[
              _DiagnosticItem(
                icon: Icons.admin_panel_settings,
                label: 'Root Shell ID',
                value: rootId,
                isMonospace: true,
              ),
              const SizedBox(height: 16),
            ],
            if (udcList.isNotEmpty) ...[
              _DiagnosticList(
                icon: Icons.developer_board,
                label: 'UDC Controllers',
                items: udcList,
              ),
              const SizedBox(height: 16),
            ],
            if (configfsBases.isNotEmpty) ...[
              _DiagnosticList(
                icon: Icons.folder_open,
                label: 'ConfigFS Mount Points',
                items: configfsBases,
              ),
              const SizedBox(height: 16),
            ],
            if (existingGadgets.isNotEmpty) ...[
              _DiagnosticList(
                icon: Icons.usb,
                label: 'Active Gadget Directories',
                items: existingGadgets,
              ),
              const SizedBox(height: 16),
            ],
            if (kernelConfig != null && kernelConfig.isNotEmpty) ...[
              _ExpandableSection(
                title: 'Kernel Config Flags (${kernelConfig.length})',
                icon: Icons.settings_system_daydream,
                isExpanded: _kernelExpanded,
                onToggle: () => setState(() => _kernelExpanded = !_kernelExpanded),
                child: Column(
                  children: kernelConfig.entries.map((entry) {
                    return _KernelConfigRow(
                      configKey: entry.key,
                      value: entry.value.toString(),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (paths != null && paths.isNotEmpty) ...[
              _ExpandableSection(
                title: 'System Paths',
                icon: Icons.folder_special,
                isExpanded: _pathsExpanded,
                onToggle: () => setState(() => _pathsExpanded = !_pathsExpanded),
                child: Column(
                  children: paths.entries.map((entry) {
                    return _PathRow(
                      label: entry.key,
                      path: entry.value.toString(),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (rawLines.isNotEmpty) ...[
              _ExpandableSection(
                title: 'Raw Kernel Config (${rawLines.length} lines)',
                icon: Icons.code,
                isExpanded: _rawExpanded,
                onToggle: () => setState(() => _rawExpanded = !_rawExpanded),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: rawLines.map((line) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          line,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DiagnosticItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isMonospace;

  const _DiagnosticItem({
    required this.icon,
    required this.label,
    required this.value,
    this.isMonospace = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: cs.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontFamily: isMonospace ? 'monospace' : null,
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DiagnosticList extends StatelessWidget {
  final IconData icon;
  final String label;
  final List<String> items;

  const _DiagnosticList({
    required this.icon,
    required this.label,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: cs.primary),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...items.map((item) => Padding(
              padding: const EdgeInsets.only(left: 30, bottom: 4),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            )),
      ],
    );
  }
}

class _ExpandableSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool isExpanded;
  final VoidCallback onToggle;
  final Widget child;

  const _ExpandableSection({
    required this.title,
    required this.icon,
    required this.isExpanded,
    required this.onToggle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(icon, size: 18, color: cs.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                Icon(
                  isExpanded ? Icons.expand_less : Icons.expand_more,
                  color: cs.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        if (isExpanded) ...[
          const SizedBox(height: 12),
          Container(
            constraints: const BoxConstraints(maxHeight: 300),
            child: SingleChildScrollView(
              child: child,
            ),
          ),
        ],
      ],
    );
  }
}

class _KernelConfigRow extends StatelessWidget {
  final String configKey;
  final String value;

  const _KernelConfigRow({
    required this.configKey,
    required this.value,
  });

  Color _getValueColor(BuildContext context, String value) {
    final cs = Theme.of(context).colorScheme;
    final lower = value.toLowerCase();
    if (lower == 'yes' || lower == 'y' || lower == 'module' || lower == 'm') {
      return cs.success;
    }
    if (lower == 'not set' || lower == 'no' || lower == 'n') {
      return cs.error;
    }
    return cs.onSurfaceVariant;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final valueColor = _getValueColor(context, value);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Text(
                configKey,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: Text(
                value,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: valueColor,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PathRow extends StatelessWidget {
  final String label;
  final String path;

  const _PathRow({
    required this.label,
    required this.path,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(Icons.folder, size: 14, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    path,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompatibilityCard extends StatelessWidget {
  final bool isPhysical;

  const _CompatibilityCard({required this.isPhysical});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      color: isPhysical
          ? cs.primaryContainer.withOpacity(0.3)
          : cs.errorContainer.withOpacity(0.3),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isPhysical ? Icons.check_circle : Icons.warning_amber_rounded,
                  color: isPhysical ? cs.primary : cs.error,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isPhysical ? 'Physical Device Detected' : 'Emulator Detected',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: isPhysical ? cs.onPrimaryContainer : cs.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              isPhysical
                  ? 'This is a physical device - the recommended environment for USB gadget operations. All HID features should work as expected.'
                  : 'This appears to be an emulator. Emulators typically cannot validate USB gadget/ConfigFS behavior. Use a physical rooted device for real HID operations.',
              style: TextStyle(
                fontSize: 13,
                color: isPhysical
                    ? cs.onPrimaryContainer.withOpacity(0.9)
                    : cs.onErrorContainer.withOpacity(0.9),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surface.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.checklist, size: 16, color: cs.primary),
                      const SizedBox(width: 8),
                      const Text(
                        'Requirements for Real HID',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _RequirementBullet(
                    icon: Icons.security,
                    text: 'Root access (Magisk, KernelSU, or SuperSU)',
                  ),
                  const SizedBox(height: 6),
                  _RequirementBullet(
                    icon: Icons.usb,
                    text: 'USB gadget / ConfigFS kernel support',
                  ),
                  const SizedBox(height: 6),
                  _RequirementBullet(
                    icon: Icons.cable,
                    text: 'USB OTG cable or USB-C data cable',
                  ),
                  const SizedBox(height: 6),
                  _RequirementBullet(
                    icon: Icons.computer,
                    text: 'Target host with USB HID support',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequirementBullet extends StatelessWidget {
  final IconData icon;
  final String text;

  const _RequirementBullet({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: cs.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurfaceVariant,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: cs.primaryContainer.withOpacity(0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: cs.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;

  const _ErrorView({required this.error});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 64, color: cs.error),
            const SizedBox(height: 16),
            Text(
              'Failed to Load Device Info',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String error;

  const _ErrorCard({required this.error});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      color: cs.errorContainer.withOpacity(0.3),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: cs.error),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Failed to Load Diagnostics',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: cs.onErrorContainer,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    error,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onErrorContainer.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/host_os.dart';
import '../../../state/controllers/hid_status_controller.dart';
import '../../../state/controllers/host_os_controller.dart';

/// Diagnostics-only view of the USB host.
///
/// Connection state and OS labeling are deliberately separate: a connected
/// host is an observed condition, while the OS may be Unknown in the absence
/// of evidence.
class HostDiagnosticsCard extends ConsumerWidget {
  const HostDiagnosticsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hid = ref.watch(hidStatusControllerProvider);
    final hostOs = ref.watch(hostOsControllerProvider);
    final cs = Theme.of(context).colorScheme;
    final selected = hostOs.source == HostOsSource.manual
        ? hostOs.os
        : HostOs.unknown;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: Icon(
              hid.deviceConnected ? Icons.usb : Icons.usb_off,
              color: cs.primary,
            ),
            title: const Text(
              'Host connected',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              hid.deviceConnected
                  ? 'USB host enumeration observed'
                  : 'No USB host connection observed',
            ),
            trailing: _ConnectionChip(connected: hid.deviceConnected),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.computer_outlined, color: cs.primary),
            title: const Text(
              'Host OS',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  hostOs.label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: hostOs.isKnown ? cs.primary : cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(hostOs.explanation),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Manual selection',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<HostOs>(
                      value: selected,
                      isExpanded: true,
                      items: HostOs.values
                          .map(
                            (os) => DropdownMenuItem(
                              value: os,
                              child: Text(
                                os == HostOs.unknown
                                    ? 'Unknown (no manual label)'
                                    : os.displayName,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        ref.read(hostOsControllerProvider.notifier).setManual(
                              value == null || value == HostOs.unknown
                                  ? null
                                  : value,
                            );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Automatic identification is unavailable: the USB gadget stack '
                        'reports connection state but no host OS identity. Host OS is '
                        'diagnostic only and never selects, starts, or changes a script.',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionChip extends StatelessWidget {
  const _ConnectionChip({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = connected ? cs.primary : cs.error;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        connected ? 'Connected' : 'Disconnected',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

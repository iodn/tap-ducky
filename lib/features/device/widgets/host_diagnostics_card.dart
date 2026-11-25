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
            leading: Icon(hid.pcConnected ? Icons.usb : Icons.usb_off, color: cs.primary),
            title: const Text('USB connection'),
            subtitle: Text(
              hid.pcConnected
                  ? (hid.deviceConnected ? 'Connected · HID ready' : 'Connected')
                  : 'Disconnected',
            ),
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
                                    ? 'No manual label'
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
                        'Automatic identification is unavailable over USB. The OS label is for diagnostics.',
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

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/host_os.dart';
import '../../../state/controllers/app_settings_controller.dart';
import '../../../state/controllers/hid_status_controller.dart';
import '../../../state/controllers/host_os_controller.dart';
import '../../../widgets/host_os_label.dart';

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
    final selected = ref.watch(appSettingsControllerProvider).value?.manualHostOs ??
        HostOs.unknown;
    final explanation = hostOs.isKnown
        ? hostOs.explanation
        : !hid.sessionArmed
            ? 'Arm a session to identify a USB host.'
            : !hid.hostOsDetectionAvailable
                ? 'Automatic identification is unavailable on this USB controller.'
                : hid.pcConnected
                    ? 'No recognizable USB signature for this connection.'
                    : 'Waiting for a USB host.';

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
                HostOsLabel(
                  diagnostic: hostOs,
                  detecting: hid.isDetectingHostOs,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: hostOs.isKnown ? cs.primary : cs.onSurfaceVariant,
                  ),
                ),
                if (!hid.isDetectingHostOs && hostOs.source != HostOsSource.inferred) ...[
                  const SizedBox(height: 4),
                  Text(explanation),
                ],
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/models/app_settings.dart';
import '../state/controllers/app_settings_controller.dart';
import '../state/controllers/hid_status_controller.dart';

enum GadgetProfileType {
  keyboard('Keyboard', Icons.keyboard_outlined),
  mouse('Mouse', Icons.mouse_outlined),
  composite('Keyboard + mouse', Icons.devices_outlined);

  const GadgetProfileType(this.label, this.icon);

  final String label;
  final IconData icon;

  static GadgetProfileType fromName(String? name) {
    return switch (name?.toLowerCase()) {
      'keyboard' => keyboard,
      'mouse' => mouse,
      _ => composite,
    };
  }
}

Future<void> toggleUsbSession(BuildContext context, WidgetRef ref) async {
  final status = ref.read(hidStatusControllerProvider);
  if (!status.rootAvailable || !status.hidSupported || status.usbRestoring) {
    return;
  }
  final controller = ref.read(hidStatusControllerProvider.notifier);
  if (status.sessionArmed) {
    await controller.deactivate();
    return;
  }

  final settings = await ref
      .read(appSettingsControllerProvider.future)
      .then<AppSettings?>((value) => value, onError: (Object _) => null);
  if (!context.mounted) return;
  final selected = await showArmProfileSheet(
    context,
    initialSelection: GadgetProfileType.fromName(settings?.lastProfileType),
  );
  if (!context.mounted || selected == null) return;
  final current = ref.read(hidStatusControllerProvider);
  if (current.sessionArmed || current.usbRestoring) return;

  await ref
      .read(appSettingsControllerProvider.notifier)
      .setLastProfileType(selected.name);
  if (!context.mounted) return;
  switch (selected) {
    case GadgetProfileType.keyboard:
      await controller.activateKeyboard();
    case GadgetProfileType.mouse:
      await controller.activateMouse();
    case GadgetProfileType.composite:
      await controller.activateComposite();
  }
}

Future<GadgetProfileType?> showArmProfileSheet(
  BuildContext context, {
  required GadgetProfileType initialSelection,
}) {
  return showModalBottomSheet<GadgetProfileType>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (context) => _ArmProfileSheet(initialSelection: initialSelection),
  );
}

class _ArmProfileSheet extends StatefulWidget {
  const _ArmProfileSheet({required this.initialSelection});

  final GadgetProfileType initialSelection;

  @override
  State<_ArmProfileSheet> createState() => _ArmProfileSheetState();
}

class _ArmProfileSheetState extends State<_ArmProfileSheet> {
  late GadgetProfileType _selected = widget.initialSelection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      'Arm session',
                      style: theme.textTheme.headlineSmall,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: RadioGroup<GadgetProfileType>(
                  groupValue: _selected,
                  onChanged: (value) {
                    if (value != null) setState(() => _selected = value);
                  },
                  child: Column(
                    children: [
                      for (final type in GadgetProfileType.values)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Material(
                            color: type == _selected
                                ? colors.primaryContainer
                                : colors.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(16),
                            clipBehavior: Clip.antiAlias,
                            child: RadioListTile<GadgetProfileType>(
                              value: type,
                              controlAffinity: ListTileControlAffinity.trailing,
                              secondary: Icon(type.icon),
                              title: Text(type.label),
                              selected: type == _selected,
                              activeColor: colors.onPrimaryContainer,
                              minTileHeight: 72,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, _selected),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
              icon: const Icon(Icons.lock_open),
              label: const Text('Arm'),
            ),
          ],
        ),
      ),
    );
  }
}

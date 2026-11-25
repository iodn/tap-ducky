import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/advanced_settings.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/payload.dart';
import '../../state/controllers/advanced_settings_controller.dart';
import '../../state/controllers/app_settings_controller.dart';
import '../../state/controllers/payloads_controller.dart';
import '../../state/providers.dart';
import '../../widgets/ducky_script_text.dart';
import '../../widgets/configuration_page.dart';
import '../../widgets/payload_picker.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/section_header.dart';
import 'usb_id_reference_screen.dart';

class AdvancedSettingsScreen extends ConsumerWidget {
  const AdvancedSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(advancedSettingsControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Advanced settings'),
        actions: [
          IconButton(
            tooltip: 'Reset',
            onPressed: async.hasValue
                ? () async {
                    final ok = await showConfirmDialog(
                      context,
                      title: 'Reset advanced settings',
                      message:
                          'Reset keyboard layout, USB controller, command presets, and hotkeys?',
                      confirmLabel: 'Reset',
                      dangerous: true,
                    );
                    if (!ok || !context.mounted) return;
                    await _applyAdvancedSetting(
                      context,
                      ref.read(advancedSettingsControllerProvider.notifier).resetToDefaults,
                    );
                  }
                : null,
            icon: const Icon(Icons.restart_alt),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) =>
            Center(child: Text('Failed to load advanced settings: $e')),
        data: (s) => _Body(settings: s),
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.settings});

  final AdvancedSettings settings;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  late Future<List<String>> _udcsFuture;

  static const Map<String, String> _hotkeyTitles = <String, String>{
    'arm_toggle': 'Arm / Disarm session',
    'stop_execution': 'Stop execution',
    'execute_recent': 'Execute most recent',
    'execute_selected': 'Execute selected payload',
  };
  static const List<String> _dialCodes = <String>[
    '38250',
    '38251',
    '38252',
    '38253',
  ];

  @override
  void initState() {
    super.initState();
    _udcsFuture = ref.read(platformGadgetServiceProvider).listUdcs();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hotkeys = widget.settings.hotkeys;
    final selectedLayout = widget.settings.keyboardLayoutOption;
    final layouts = AdvancedSettings.supportedKeyboardLayouts.toList()
      ..sort((a, b) => a.label.compareTo(b.label));
    final appSettingsAsync = ref.watch(appSettingsControllerProvider);
    final payloads =
        ref.watch(payloadsControllerProvider).value ?? const <Payload>[];

    return ListView(
      children: [
        const SizedBox(height: 10),
        const SectionHeader(title: 'Keyboard & USB controller'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _UsbReferenceTile(),
                  const Divider(),
                  InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Keyboard layout',
                      helperText: selectedLayout == null
                          ? 'Saved layout unavailable. Using US.'
                          : null,
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedLayout?.id ?? 'us',
                        isExpanded: true,
                        items: [
                          for (final layout in layouts)
                            DropdownMenuItem(
                              value: layout.id,
                              child: Text(layout.label, overflow: TextOverflow.ellipsis),
                            ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          _applyAdvancedSetting(
                            context,
                            () => ref.read(advancedSettingsControllerProvider.notifier).setKeyboardLayout(value),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  FutureBuilder<List<String>>(
                    future: _udcsFuture,
                    builder: (context, snap) {
                      final udcs = snap.data ?? const <String>[];
                      final currentRaw = widget.settings.preferredUdc.trim();
                      final current = currentRaw.isEmpty ? 'auto' : currentRaw;
                      final items = <DropdownMenuItem<String>>[
                        const DropdownMenuItem(
                          value: 'auto',
                          child: Text('Automatic'),
                        ),
                        ...udcs.map(
                          (u) => DropdownMenuItem(value: u, child: Text(u)),
                        ),
                      ];

                      final hasCurrent = items.any((e) => e.value == current);
                      final mergedItems = <DropdownMenuItem<String>>[
                        if (!hasCurrent && current != 'auto')
                          DropdownMenuItem(
                            value: current,
                            child: Text('Current ($current)'),
                          ),
                        ...items,
                      ];

                      return DropdownButtonFormField<String>(
                        key: ValueKey(current),
                        initialValue: hasCurrent ? current : mergedItems.first.value,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'USB controller',
                          helperText:
                              snap.connectionState == ConnectionState.waiting
                              ? 'Loading available controllers…'
                              : null,
                        ),
                        items: mergedItems,
                        onChanged: (v) async {
                          if (v == null) return;
                          await ref
                              .read(advancedSettingsControllerProvider.notifier)
                              .setPreferredUdc(v);
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        const SectionHeader(title: 'Command presets'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            child: Column(
              children: [
                for (
                  int i = 0;
                  i < widget.settings.commandPresets.length;
                  i++
                ) ...[
                  _PresetTile(
                    index: i,
                    preset: widget.settings.commandPresets[i],
                  ),
                  if (i != widget.settings.commandPresets.length - 1)
                    const Divider(height: 1),
                ],
                ListTile(
                  leading: const Icon(Icons.add),
                  title: const Text('Add preset'),
                  subtitle: const Text(
                    'Adds a reusable script fragment for the Execute console',
                  ),
                  onTap: () => _addPresetDialog(context, ref),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        const SectionHeader(title: 'Hotkeys'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            child: Column(
              children: [
                _HotkeyTile(
                  action: 'arm_toggle',
                  title: _hotkeyTitles['arm_toggle']!,
                  allHotkeys: hotkeys,
                  actionTitles: _hotkeyTitles,
                ),
                const Divider(height: 1),
                _HotkeyTile(
                  action: 'stop_execution',
                  title: _hotkeyTitles['stop_execution']!,
                  allHotkeys: hotkeys,
                  actionTitles: _hotkeyTitles,
                ),
                const Divider(height: 1),
                _HotkeyTile(
                  action: 'execute_recent',
                  title: _hotkeyTitles['execute_recent']!,
                  allHotkeys: hotkeys,
                  actionTitles: _hotkeyTitles,
                ),
                const Divider(height: 1),
                _HotkeyTile(
                  action: 'execute_selected',
                  title: _hotkeyTitles['execute_selected']!,
                  allHotkeys: hotkeys,
                  actionTitles: _hotkeyTitles,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Text(
                    'Choose a hardware gesture to trigger an action. A gesture can only be assigned to one action.',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        const SectionHeader(title: 'Dial shortcuts'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            child: appSettingsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, st) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Failed to load dial shortcuts: $e'),
              ),
              data: (settings) {
                final bindings = _normalizeDialShortcuts(
                  settings.dialShortcuts,
                );
                return Column(
                  children: [
                    for (int i = 0; i < bindings.length; i++) ...[
                      _DialShortcutTile(
                        binding: bindings[i],
                        payloads: payloads,
                        onChanged: (next) =>
                            _updateDialShortcut(ref, bindings, next),
                      ),
                      if (i != bindings.length - 1) const Divider(height: 1),
                    ],
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Text(
                        'Dial *#*#CODE#*#* in the phone app. Only the listed codes are supported.',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 18),
      ],
    );
  }

  Future<void> _addPresetDialog(BuildContext context, WidgetRef ref) async {
    final res = await showConfigurationPage<String>(
      context,
      (_) => const TextConfigurationPage(
        title: 'New preset',
        fieldLabel: 'Command',
        highlightScript: true,
        actionLabel: 'Add',
        hint: 'STRING hello',
      ),
    );
    if (!context.mounted) return;
    if (res == null || res.trim().isEmpty) return;
    await ref
        .read(advancedSettingsControllerProvider.notifier)
        .addCommandPreset(res.trim());
  }

  List<DialShortcutBinding> _normalizeDialShortcuts(
    List<DialShortcutBinding> existing,
  ) {
    final map = <String, DialShortcutBinding>{};
    for (final b in existing) {
      if (b.code.isEmpty) continue;
      map[b.code] = b;
    }
    final out = <DialShortcutBinding>[];
    for (final code in _dialCodes) {
      final existingBinding = map[code];
      out.add(
        existingBinding ??
            DialShortcutBinding(
              code: code,
              enabled: false,
              mode: 'last',
              payloadId: null,
              script: null,
              name: null,
            ),
      );
    }
    return out;
  }

  Future<void> _updateDialShortcut(
    WidgetRef ref,
    List<DialShortcutBinding> all,
    DialShortcutBinding updated,
  ) async {
    final next = <DialShortcutBinding>[];
    for (final b in all) {
      if (b.code == updated.code) {
        next.add(updated);
      } else {
        next.add(b);
      }
    }
    await ref
        .read(appSettingsControllerProvider.notifier)
        .setDialShortcuts(next);
  }
}

class _DialShortcutTile extends StatelessWidget {
  const _DialShortcutTile({
    required this.binding,
    required this.payloads,
    required this.onChanged,
  });

  final DialShortcutBinding binding;
  final List<Payload> payloads;
  final ValueChanged<DialShortcutBinding> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mode = (binding.mode == 'payload') ? 'payload' : 'last';
    Payload? selectedPayload;
    if (mode == 'payload' && binding.payloadId != null) {
      for (final p in payloads) {
        if (p.id == binding.payloadId) {
          selectedPayload = p;
          break;
        }
      }
    }
    final subtitle = mode == 'payload'
        ? (selectedPayload?.name ?? 'Select a payload')
        : 'Last executed script';

    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      title: Text('*#*#${binding.code}#*#*'),
      subtitle: Tooltip(
        message: subtitle,
        excludeFromSemantics: true,
        child: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      ),
      trailing: Switch(
        value: binding.enabled,
        onChanged: (v) => onChanged(binding.copyWith(enabled: v)),
      ),
      children: [
        DropdownButtonFormField<String>(
          initialValue: mode,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Target', border: OutlineInputBorder()),
          items: const [
            DropdownMenuItem(value: 'last', child: Text('Last executed')),
            DropdownMenuItem(value: 'payload', child: Text('Selected payload')),
          ],
          onChanged: (value) {
            if (value == null) return;
            onChanged(
              binding.copyWith(
                mode: value,
                payloadId: value == 'payload' ? binding.payloadId : null,
                script: value == 'payload' ? binding.script : null,
                name: value == 'payload' ? binding.name : null,
              ),
            );
          },
        ),
        if (mode == 'payload') ...[
          const SizedBox(height: 12),
          PayloadPicker(
            payloads: payloads,
            selected: selectedPayload,
            onChanged: (payload) => onChanged(
              binding.copyWith(payloadId: payload.id, script: payload.script, name: payload.name),
            ),
          ),
          if (payloads.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'No payloads available to bind.',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ),
        ],
      ],
    );
  }
}

class _PresetTile extends ConsumerWidget {
  const _PresetTile({required this.index, required this.preset});

  final int index;
  final String preset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: const Icon(Icons.code),
      title: Text('Preset ${index + 1}'),
      subtitle: DuckyScriptText(preset, maxLines: 2, fontSize: 12),
      trailing: PopupMenuButton<String>(
        onSelected: (v) async {
          switch (v) {
            case 'edit':
              await _edit(context, ref);
              return;
            case 'delete':
              final ok = await showConfirmDialog(
                context,
                title: 'Delete preset',
                message: 'Delete preset ${index + 1}?',
                confirmLabel: 'Delete',
                dangerous: true,
              );
              if (!ok) return;
              await ref
                  .read(advancedSettingsControllerProvider.notifier)
                  .removeCommandPreset(index);
              return;
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'edit', child: Text('Edit')),
          PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
      onTap: () => _edit(context, ref),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final res = await showConfigurationPage<String>(
      context,
      (_) => TextConfigurationPage(
        title: 'Edit preset ${index + 1}',
        fieldLabel: 'Command',
        highlightScript: true,
        actionLabel: 'Save',
        initialValue: preset,
      ),
    );
    if (!context.mounted) return;
    if (res == null) return;
    await ref
        .read(advancedSettingsControllerProvider.notifier)
        .updateCommandPreset(index, res);
  }
}

class _HotkeyOption {
  const _HotkeyOption(this.value, this.title, this.subtitle);
  final String value;
  final String title;
  final String subtitle;
}

class _HotkeyTile extends ConsumerWidget {
  const _HotkeyTile({
    required this.action,
    required this.title,
    required this.allHotkeys,
    required this.actionTitles,
  });

  final String action;
  final String title;
  final Map<String, String> allHotkeys;
  final Map<String, String> actionTitles;

  static const String _none = '—';

  List<_HotkeyOption> _options() {
    return const [
      _HotkeyOption('—', 'None', 'Disable this hotkey'),
      _HotkeyOption('Volume Up (double-tap)', 'Volume Up', 'Double-tap'),
      _HotkeyOption('Volume Up (triple-tap)', 'Volume Up', 'Triple-tap'),
      _HotkeyOption('Volume Up (long-press)', 'Volume Up', 'Long-press'),
      _HotkeyOption('Volume Down (double-tap)', 'Volume Down', 'Double-tap'),
      _HotkeyOption('Volume Down (triple-tap)', 'Volume Down', 'Triple-tap'),
      _HotkeyOption('Volume Down (long-press)', 'Volume Down', 'Long-press'),
    ];
  }

  String _norm(String s) {
    final t = s.trim();
    return t.isEmpty ? _none : t;
  }

  String? _usedByOtherAction(String candidate) {
    final c = _norm(candidate);
    if (c == _none) return null;
    for (final e in allHotkeys.entries) {
      if (e.key == action) continue;
      if (_norm(e.value) == c) return e.key;
    }
    return null;
  }

  Future<String?> _pickBinding(BuildContext context, String current) {
    final opts = _options();
    final groupValue = _norm(current);

    return showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                title: Text(title),
                subtitle: Text(
                  'Select a gesture',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: opts.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final o = opts[i];
                    final selected = o.value == groupValue;
                    final usedBy = _usedByOtherAction(o.value);
                    final disabled =
                        usedBy != null && !selected && o.value != _none;
                    final extra = usedBy == null
                        ? ''
                        : ' (Assigned to ${actionTitles[usedBy] ?? usedBy})';

                    return ListTile(
                      enabled: !disabled,
                      leading: Radio<String>(
                        value: o.value,
                        groupValue: groupValue,
                        onChanged: disabled
                            ? null
                            : (v) => Navigator.of(context).pop(v),
                      ),
                      title: Text(o.title),
                      subtitle: Text('${o.subtitle}$extra'),
                      trailing: selected
                          ? const Icon(Icons.check)
                          : (disabled
                                ? Icon(Icons.lock, color: cs.onSurfaceVariant)
                                : null),
                      onTap: disabled
                          ? null
                          : () => Navigator.of(context).pop(o.value),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final binding = allHotkeys[action] ?? _none;
    return ListTile(
      leading: const Icon(Icons.keyboard),
      title: Text(title),
      subtitle: Text(binding.trim().isEmpty ? _none : binding),
      trailing: const Icon(Icons.edit),
      onTap: () async {
        final picked = await _pickBinding(context, binding);
        if (picked == null) return;

        final normalized = _norm(picked);
        await ref
            .read(advancedSettingsControllerProvider.notifier)
            .setHotkey(action, normalized);

        final after = ref.read(advancedSettingsControllerProvider).value;
        final stored = _norm(after?.hotkeys[action] ?? _none);

        if (stored != normalized && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'This gesture is already assigned to another action.',
              ),
              duration: Duration(seconds: 2),
            ),
          );
        }
      },
    );
  }
}

class _UsbReferenceTile extends StatelessWidget {
  const _UsbReferenceTile();

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.manage_search),
      title: const Text('USB ID reference'),
      subtitle: const Text('Look up vendor and product IDs. Sessions use Android’s USB identity.'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => showConfigurationPage<void>(context, (_) => const UsbIdReferenceScreen()),
    );
  }
}

Future<void> _applyAdvancedSetting(
  BuildContext context,
  Future<void> Function() update,
) async {
  try {
    await update();
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not apply the change. Try again.')),
      );
    }
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/db/usb_ids_db.dart';
import '../../data/models/advanced_settings.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/payload.dart';
import '../../data/services/platform_gadget_service.dart';
import '../../state/controllers/advanced_settings_controller.dart';
import '../../state/controllers/app_settings_controller.dart';
import '../../state/controllers/payloads_controller.dart';
import '../../state/providers.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/section_header.dart';
import 'usb_id_selector_dialog.dart';

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
                          'Reset command presets, hotkeys, and default VID/PID to defaults?',
                      confirmLabel: 'Reset',
                      dangerous: true,
                    );
                    if (!ok) return;
                    await ref
                        .read(advancedSettingsControllerProvider.notifier)
                        .resetToDefaults();
                  }
                : null,
            icon: const Icon(Icons.restart_alt),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Failed to load advanced settings: $e')),
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
  late TextEditingController _vidCtrl;
  late TextEditingController _pidCtrl;

  String? _vidError;
  String? _pidError;
  int? _vidParsed;
  int? _pidParsed;

  Future<({String? vendor, String? product})>? _resolvedNames;
  late Future<List<KeyboardLayoutInfo>> _keyboardLayoutsFuture;

  static const Map<String, String> _hotkeyTitles = <String, String>{
    'arm_toggle': 'Arm / Disarm session',
    'stop_execution': 'Stop execution',
    'execute_recent': 'Execute most recent',
    'execute_selected': 'Execute selected payload',
  };
  static const List<String> _dialCodes = <String>['38250', '38251', '38252', '38253'];

  @override
  void initState() {
    super.initState();
    _vidCtrl = TextEditingController(text: widget.settings.defaultVid);
    _pidCtrl = TextEditingController(text: widget.settings.defaultPid);
    _keyboardLayoutsFuture =
        ref.read(platformGadgetServiceProvider).getKeyboardLayouts();
    _syncParsedAndResolved();
  }

  @override
  void didUpdateWidget(_Body oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.defaultVid != widget.settings.defaultVid) {
      _vidCtrl.text = widget.settings.defaultVid;
    }
    if (oldWidget.settings.defaultPid != widget.settings.defaultPid) {
      _pidCtrl.text = widget.settings.defaultPid;
    }
    _syncParsedAndResolved();
  }

  @override
  void dispose() {
    _vidCtrl.dispose();
    _pidCtrl.dispose();
    super.dispose();
  }

  void _syncParsedAndResolved() {
    final vidRes = _parseHexId(_vidCtrl.text);
    final pidRes = _parseHexId(_pidCtrl.text);
    final vid = vidRes.value;
    final pid = pidRes.value;

    setState(() {
      _vidError = vidRes.error;
      _pidError = pidRes.error;
      _vidParsed = vid;
      _pidParsed = pid;
      _resolvedNames = _buildResolvedFuture(vid, pid, vidRes.error, pidRes.error);
    });
  }

  Future<({String? vendor, String? product})>? _buildResolvedFuture(
    int? vid,
    int? pid,
    String? vidErr,
    String? pidErr,
  ) {
    if (vid == null || pid == null) return null;
    if (vidErr != null || pidErr != null) return null;
    return ref.read(usbIdsDbProvider.future).then((db) => db.resolveNames(vid, pid));
  }

  void _validateVid(String value) {
    final res = _parseHexId(value);
    final nextVid = res.value;
    setState(() {
      _vidError = res.error;
      _vidParsed = nextVid;
      _resolvedNames = _buildResolvedFuture(nextVid, _pidParsed, res.error, _pidError);
    });
  }

  void _validatePid(String value) {
    final res = _parseHexId(value);
    final nextPid = res.value;
    setState(() {
      _pidError = res.error;
      _pidParsed = nextPid;
      _resolvedNames = _buildResolvedFuture(_vidParsed, nextPid, _vidError, res.error);
    });
  }

  ({int? value, String? error}) _parseHexId(String hex) {
    try {
      final trimmed = hex.trim();
      if (trimmed.isEmpty) {
        return (value: null, error: 'Cannot be empty');
      }
      final normalized = trimmed.toLowerCase();
      int parsed;
      if (normalized.startsWith('0x')) {
        parsed = int.parse(normalized.substring(2), radix: 16);
      } else {
        parsed = int.parse(normalized, radix: 16);
      }
      if (parsed < 0 || parsed > 0xFFFF) {
        return (value: null, error: 'Must be 0x0000–0xFFFF');
      }
      return (value: parsed, error: null);
    } catch (_) {
      return (value: null, error: 'Invalid hex format');
    }
  }

  String _hex16(int value) {
    final v = value & 0xFFFF;
    return '0x${v.toRadixString(16).toUpperCase().padLeft(4, '0')}';
  }

  Future<void> _pickFromDb(BuildContext context) async {
    final picked = await showUsbIdSelectorDialog(context, ref);
    if (picked == null) return;

    final vidText = _hex16(picked.vid);
    final pidText = _hex16(picked.pid);

    setState(() {
      _vidCtrl.text = vidText;
      _pidCtrl.text = pidText;
    });

    _validateVid(vidText);
    _validatePid(pidText);

    if (_vidError == null) {
      await ref
          .read(advancedSettingsControllerProvider.notifier)
          .setDefaultVid(vidText);
    }
    if (_pidError == null) {
      await ref
          .read(advancedSettingsControllerProvider.notifier)
          .setDefaultPid(pidText);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'Selected ${picked.vendorName} • ${picked.productName} ($vidText:$pidText)'),
      ),
    );
  }

  List<DropdownMenuItem<String>> _fallbackKeyboardItems() {
    return const [
      DropdownMenuItem(value: 'us', child: Text('US (QWERTY)')),
      DropdownMenuItem(value: 'fr', child: Text('FR (AZERTY)')),
      DropdownMenuItem(value: 'jp', child: Text('JP (JIS)')),
    ];
  }

  List<DropdownMenuItem<String>> _itemsFromLayouts(List<KeyboardLayoutInfo> layouts) {
    final filtered = layouts.where((l) => l.code.trim().isNotEmpty).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return filtered.map((l) => DropdownMenuItem(value: l.code, child: Text(l.name))).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hotkeys = widget.settings.hotkeys;
    final appSettingsAsync = ref.watch(appSettingsControllerProvider);
    final payloads = ref.watch(payloadsControllerProvider).value ?? const <Payload>[];

    return ListView(
      children: [
        const SizedBox(height: 10),
        const SectionHeader(title: 'USB gadget defaults'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.manage_search),
                    title: const Text('Pick VID/PID from USB IDs database'),
                    subtitle: _resolvedNames == null
                        ? Text(
                            'Search by vendor or product name. Recommended to match a real device fingerprint.',
                            style: TextStyle(color: cs.onSurfaceVariant),
                          )
                        : FutureBuilder<({String? vendor, String? product})>(
                            future: _resolvedNames,
                            builder: (context, snap) {
                              final v = snap.data?.vendor;
                              final p = snap.data?.product;
                              if (snap.connectionState == ConnectionState.waiting) {
                                return Text(
                                  'Looking up vendor/product…',
                                  style: TextStyle(color: cs.onSurfaceVariant),
                                );
                              }
                              if (snap.hasError) {
                                return Text(
                                  'Lookup failed. You can still enter VID/PID manually.',
                                  style: TextStyle(color: cs.onSurfaceVariant),
                                );
                              }
                              if (v == null && p == null) {
                                return Text(
                                  'No match found in database for current VID/PID.',
                                  style: TextStyle(color: cs.onSurfaceVariant),
                                );
                              }
                              final parts = <String>[];
                              if (v != null) parts.add(v);
                              if (p != null) parts.add(p);
                              return Text(
                                parts.join(' • '),
                                style: TextStyle(color: cs.onSurfaceVariant),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              );
                            },
                          ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _pickFromDb(context),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _vidCtrl,
                          decoration: InputDecoration(
                            labelText: 'Default VID (hex)',
                            hintText: '0x1D6B',
                            errorText: _vidError,
                            helperText: _vidParsed != null
                                ? '→ ${_vidParsed!} (${_hex16(_vidParsed!)})'
                                : null,
                          ),
                          onChanged: (v) async {
                            _validateVid(v);
                            if (_vidError == null) {
                              await ref
                                  .read(advancedSettingsControllerProvider.notifier)
                                  .setDefaultVid(v.trim());
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _pidCtrl,
                          decoration: InputDecoration(
                            labelText: 'Default PID (hex)',
                            hintText: '0x0104',
                            errorText: _pidError,
                            helperText: _pidParsed != null
                                ? '→ ${_pidParsed!} (${_hex16(_pidParsed!)})'
                                : null,
                          ),
                          onChanged: (v) async {
                            _validatePid(v);
                            if (_pidError == null) {
                              await ref
                                  .read(advancedSettingsControllerProvider.notifier)
                                  .setDefaultPid(v.trim());
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  FutureBuilder<List<KeyboardLayoutInfo>>(
                    future: _keyboardLayoutsFuture,
                    builder: (context, snap) {
                      final layouts = snap.data ?? const <KeyboardLayoutInfo>[];
                      final dynamicItems = layouts.isEmpty
                          ? <DropdownMenuItem<String>>[]
                          : _itemsFromLayouts(layouts);
                      final baseItems =
                          dynamicItems.isNotEmpty ? dynamicItems : _fallbackKeyboardItems();

                      final current = widget.settings.keyboardLayout.trim();
                      final hasCurrent = baseItems.any((e) => e.value == current);

                      final items = <DropdownMenuItem<String>>[
                        if (!hasCurrent && current.isNotEmpty)
                          DropdownMenuItem(
                              value: current, child: Text('Current (${current.toUpperCase()})')),
                        ...baseItems,
                      ];

                      final value = current.isNotEmpty
                          ? current
                          : (items.isNotEmpty ? items.first.value : null);

                      return DropdownButtonFormField<String>(
                        value: value,
                        decoration: InputDecoration(
                          labelText: 'Keyboard layout',
                          helperText: snap.connectionState == ConnectionState.waiting
                              ? 'Loading supported layouts…'
                              : (dynamicItems.isNotEmpty ? 'From backend' : 'Fallback list'),
                        ),
                        items: items,
                        onChanged: (v) async {
                          if (v == null) return;
                          await ref
                              .read(advancedSettingsControllerProvider.notifier)
                              .setKeyboardLayout(v);
                          try {
                            await ref
                                .read(platformGadgetServiceProvider)
                                .setKeyboardLayoutByCode(v);
                          } catch (_) {}
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'These values are used when activating USB gadget profiles. Choosing a VID/PID that matches a real device improves operator realism and reduces UI mistakes.',
                    style: TextStyle(color: cs.onSurfaceVariant),
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
                for (int i = 0; i < widget.settings.commandPresets.length; i++) ...[
                  _PresetTile(index: i, preset: widget.settings.commandPresets[i]),
                  if (i != widget.settings.commandPresets.length - 1) const Divider(height: 1),
                ],
                ListTile(
                  leading: const Icon(Icons.add),
                  title: const Text('Add preset'),
                  subtitle: const Text('Adds a reusable script fragment for the Execute console'),
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
                final bindings = _normalizeDialShortcuts(settings.dialShortcuts);
                return Column(
                  children: [
                    for (int i = 0; i < bindings.length; i++) ...[
                      _DialShortcutTile(
                        binding: bindings[i],
                        payloads: payloads,
                        onChanged: (next) => _updateDialShortcut(ref, bindings, next),
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
    final ctrl = TextEditingController();
    final res = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New preset'),
        content: TextField(
          controller: ctrl,
          maxLines: 8,
          decoration:
              const InputDecoration(hintText: 'Example:\nDELAY 250\nSTRING hello\nENTER'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(null), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(ctrl.text), child: const Text('Add')),
        ],
      ),
    );
    if (res == null || res.trim().isEmpty) return;
    await ref
        .read(advancedSettingsControllerProvider.notifier)
        .addCommandPreset(res.trim());
  }

  List<DialShortcutBinding> _normalizeDialShortcuts(List<DialShortcutBinding> existing) {
    final map = <String, DialShortcutBinding>{};
    for (final b in existing) {
      if (b.code.isEmpty) continue;
      map[b.code] = b;
    }
    final out = <DialShortcutBinding>[];
    for (final code in _dialCodes) {
      final existingBinding = map[code];
      out.add(existingBinding ??
          DialShortcutBinding(
            code: code,
            enabled: false,
            mode: 'last',
            payloadId: null,
            script: null,
            name: null,
          ));
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
    await ref.read(appSettingsControllerProvider.notifier).setDialShortcuts(next);
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
    final hasSelected = selectedPayload != null;
    final subtitle = mode == 'payload'
        ? (hasSelected ? selectedPayload!.name : 'Select a payload')
        : 'Last executed script';

    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      title: Text('*#*#${binding.code}#*#*'),
      subtitle: Text(subtitle, style: TextStyle(color: cs.onSurfaceVariant)),
      trailing: Switch(
        value: binding.enabled,
        onChanged: (v) => onChanged(binding.copyWith(enabled: v)),
      ),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Target', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: cs.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: mode,
                  style: TextStyle(color: cs.onSurface),
                  items: const [
                    DropdownMenuItem(value: 'last', child: Text('Last executed')),
                    DropdownMenuItem(value: 'payload', child: Text('Selected payload')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    onChanged(binding.copyWith(
                      mode: v,
                      payloadId: v == 'payload' ? binding.payloadId : null,
                      script: v == 'payload' ? binding.script : null,
                      name: v == 'payload' ? binding.name : null,
                    ));
                  },
                ),
              ),
            ),
          ],
        ),
        if (mode == 'payload') ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const Expanded(
                child: Text('Payload', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: hasSelected ? selectedPayload!.id : null,
                    hint: const Text('Select payload'),
                    style: TextStyle(color: cs.onSurface),
                    items: payloads
                        .map((p) => DropdownMenuItem(
                              value: p.id,
                              child: Text(p.name, overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      final p = payloads.firstWhere((e) => e.id == v);
                      onChanged(binding.copyWith(
                        payloadId: p.id,
                        script: p.script,
                        name: p.name,
                      ));
                    },
                  ),
                ),
              ),
            ],
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
      subtitle: Text(preset, maxLines: 2, overflow: TextOverflow.ellipsis),
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
    final ctrl = TextEditingController(text: preset);
    final res = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit preset ${index + 1}'),
        content: TextField(
          controller: ctrl,
          maxLines: 10,
          decoration: const InputDecoration(),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(null), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(ctrl.text), child: const Text('Save')),
        ],
      ),
    );
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
                subtitle: Text('Select a gesture', style: TextStyle(color: cs.onSurfaceVariant)),
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
                    final disabled = usedBy != null && !selected && o.value != _none;
                    final extra =
                        usedBy == null ? '' : ' (Assigned to ${actionTitles[usedBy] ?? usedBy})';

                    return ListTile(
                      enabled: !disabled,
                      leading: Radio<String>(
                        value: o.value,
                        groupValue: groupValue,
                        onChanged: disabled ? null : (v) => Navigator.of(context).pop(v),
                      ),
                      title: Text(o.title),
                      subtitle: Text('${o.subtitle}$extra'),
                      trailing: selected
                          ? const Icon(Icons.check)
                          : (disabled ? Icon(Icons.lock, color: cs.onSurfaceVariant) : null),
                      onTap: disabled ? null : () => Navigator.of(context).pop(o.value),
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
              content: Text('This gesture is already assigned to another action.'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      },
    );
  }
}

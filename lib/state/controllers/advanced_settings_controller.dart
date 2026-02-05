import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/advanced_settings.dart';
import '../providers.dart';

final advancedSettingsControllerProvider = AsyncNotifierProvider<AdvancedSettingsController, AdvancedSettings>(
  AdvancedSettingsController.new,
);

class AdvancedSettingsController extends AsyncNotifier<AdvancedSettings> {
  static const String _none = '—';
  static const List<String> _knownHotkeyActions = <String>[
    'stop_execution',
    'arm_toggle',
    'execute_recent',
    'execute_selected',
  ];

  @override
  Future<AdvancedSettings> build() async {
    final repo = await ref.watch(advancedSettingsRepositoryProvider.future);
    final loaded = repo.load();
    final sanitized = _sanitizeHotkeys(loaded);
    if (!_hotkeysEqual(loaded.hotkeys, sanitized.hotkeys)) {
      await repo.save(sanitized);
    }
    return sanitized;
  }

  Future<void> setKeyboardLayout(String layout) async {
    final current = state.value ?? AdvancedSettings.defaults();
    await _save(current.copyWith(keyboardLayout: layout));
  }

  Future<void> setDefaultVid(String vid) async {
    final current = state.value ?? AdvancedSettings.defaults();
    await _save(current.copyWith(defaultVid: vid));
  }

  Future<void> setDefaultPid(String pid) async {
    final current = state.value ?? AdvancedSettings.defaults();
    await _save(current.copyWith(defaultPid: pid));
  }

  Future<void> addCommandPreset(String preset) async {
    final current = state.value ?? AdvancedSettings.defaults();
    final next = [...current.commandPresets, preset].where((s) => s.trim().isNotEmpty).toList();
    await _save(current.copyWith(commandPresets: next));
  }

  Future<void> updateCommandPreset(int index, String preset) async {
    final current = state.value ?? AdvancedSettings.defaults();
    if (index < 0 || index >= current.commandPresets.length) return;
    final next = [...current.commandPresets];
    next[index] = preset;
    await _save(current.copyWith(commandPresets: next.where((s) => s.trim().isNotEmpty).toList()));
  }

  Future<void> removeCommandPreset(int index) async {
    final current = state.value ?? AdvancedSettings.defaults();
    if (index < 0 || index >= current.commandPresets.length) return;
    final next = [...current.commandPresets]..removeAt(index);
    await _save(current.copyWith(commandPresets: next));
  }

  Future<void> setHotkey(String action, String binding) async {
    final currentRaw = state.value ?? AdvancedSettings.defaults();
    final current = _sanitizeHotkeys(currentRaw);

    final normalized = _normalizeBinding(binding);
    if (normalized != _none) {
      for (final e in current.hotkeys.entries) {
        if (e.key == action) continue;
        if (_normalizeBinding(e.value) == normalized) {
          state = AsyncData(current);
          return;
        }
      }
    }

    final existing = _normalizeBinding(current.hotkeys[action] ?? _none);
    if (existing == normalized) {
      state = AsyncData(current);
      return;
    }

    final next = <String, String>{...current.hotkeys, action: normalized};
    await _save(_sanitizeHotkeys(current.copyWith(hotkeys: next)));
  }

  Future<void> resetToDefaults() async {
    await _save(AdvancedSettings.defaults());
  }

  Future<void> _save(AdvancedSettings s) async {
    state = AsyncData(s);
    final repo = await ref.read(advancedSettingsRepositoryProvider.future);
    await repo.save(s);
  }

  String _normalizeBinding(String raw) {
    final t = raw.trim();
    return t.isEmpty ? _none : t;
  }

  bool _hotkeysEqual(Map<String, String> a, Map<String, String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  AdvancedSettings _sanitizeHotkeys(AdvancedSettings s) {
    final base = <String, String>{
      ...AdvancedSettings.defaults().hotkeys,
      ...s.hotkeys,
    };

    final seen = <String>{};
    final out = <String, String>{...base};

    for (final action in _knownHotkeyActions) {
      final v = _normalizeBinding(base[action] ?? _none);
      if (v == _none) {
        out[action] = _none;
        continue;
      }
      if (seen.contains(v)) {
        out[action] = _none;
        continue;
      }
      seen.add(v);
      out[action] = v;
    }

    return s.copyWith(hotkeys: out);
  }
}

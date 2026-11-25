import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../data/models/app_settings.dart';
import '../../data/models/host_os.dart';
import '../providers.dart';

final appSettingsControllerProvider = AsyncNotifierProvider<AppSettingsController, AppSettings>(
  AppSettingsController.new,
);

class AppSettingsController extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() async {
    final repo = await ref.watch(settingsRepositoryProvider.future);
    final loaded = repo.load();

    await _applyExecutionSettings(loaded);
    await _applyDialShortcutBindings(loaded.dialShortcuts);
    return loaded;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final s = (state.value ?? AppSettings.defaults()).copyWith(themeMode: mode);
    await _save(s);
  }

  Future<void> setEnableLogging(bool v) async {
    final s = (state.value ?? AppSettings.defaults()).copyWith(enableLogging: v);
    await _save(s);
  }

  Future<void> setDelayMultiplier(double v) async {
    final s = (state.value ?? AppSettings.defaults()).copyWith(delayMultiplier: v.clamp(0.1, 4.0));
    await _save(s);
  }

  Future<void> setTypingSpeedFactor(double v) async {
    final clamped = v.clamp(0.1, 10.0);
    await _applyTypingSpeedFactor(clamped);
    await _save((state.value ?? AppSettings.defaults()).copyWith(typingSpeedFactor: clamped));
  }

  Future<void> setRandomizeTiming(bool v) async {
    final s = (state.value ?? AppSettings.defaults()).copyWith(randomizeTiming: v);
    await _save(s);
  }

  Future<void> setKeepScreenOn(bool v) async {
    await _applyWakelockState(v);
    await _save((state.value ?? AppSettings.defaults()).copyWith(keepScreenOn: v));
  }

  Future<void> setHiddenExecution(bool v) async {
    final s = (state.value ?? AppSettings.defaults()).copyWith(hiddenExecution: v);
    await _save(s);
  }

  Future<void> setManualHostOs(HostOs? os) async {
    final s = (state.value ?? AppSettings.defaults()).copyWith(manualHostOs: os);
    await _save(s);
  }

  Future<void> setShowPowerUserHints(bool v) async {
    final s = (state.value ?? AppSettings.defaults()).copyWith(showPowerUserHints: v);
    await _save(s);
  }

  Future<void> setLastProfileType(String profileType) async {
    final s = (state.value ?? AppSettings.defaults()).copyWith(lastProfileType: profileType);
    await _save(s);
  }

  Future<void> setHidGraceWindowMs(int ms) async {
    final clamped = ms.clamp(0, 5000);
    await _applyHidGraceWindow(clamped);
    await _save((state.value ?? AppSettings.defaults()).copyWith(hidGraceWindowMs: clamped));
  }

  Future<void> setUnicodeFallbackMode(String mode) async {
    final normalized = mode.trim().toLowerCase();
    final safe = (normalized == 'skip' || normalized == 'warn' || normalized == 'ascii') ? normalized : 'warn';
    await _applyUnicodeFallbackMode(safe);
    await _save((state.value ?? AppSettings.defaults()).copyWith(unicodeFallbackMode: safe));
  }

  Future<void> setRiskyFastMode(bool v) async {
    await _applyRiskyFastMode(v);
    await _save((state.value ?? AppSettings.defaults()).copyWith(riskyFastMode: v));
  }

  Future<void> resetExecutionDefaults() async {
    final defaults = AppSettings.defaults();
    await _applyExecutionSettings(defaults);
    await _save((state.value ?? defaults).copyWith(
      enableLogging: defaults.enableLogging,
      delayMultiplier: defaults.delayMultiplier,
      typingSpeedFactor: defaults.typingSpeedFactor,
      hidGraceWindowMs: defaults.hidGraceWindowMs,
      unicodeFallbackMode: defaults.unicodeFallbackMode,
      riskyFastMode: defaults.riskyFastMode,
      keepScreenOn: defaults.keepScreenOn,
    ));
  }

  Future<void> resetAllToDefaults() async {
    final defaults = AppSettings.defaults();
    await _applyExecutionSettings(defaults);
    await _applyDialShortcutBindings(defaults.dialShortcuts);
    await _save(defaults);
  }

  Future<void> setDialShortcuts(List<DialShortcutBinding> bindings) async {
    final s = (state.value ?? AppSettings.defaults()).copyWith(dialShortcuts: bindings);
    await _applyDialShortcutBindings(bindings);
    await _save(s);
  }

  Future<void> _applyExecutionSettings(AppSettings settings) async {
    await _applyWakelockState(settings.keepScreenOn);
    await _applyHidGraceWindow(settings.hidGraceWindowMs);
    await _applyUnicodeFallbackMode(settings.unicodeFallbackMode);
    await _applyTypingSpeedFactor(settings.typingSpeedFactor);
    await _applyRiskyFastMode(settings.riskyFastMode);
  }

  Future<void> _applyWakelockState(bool enable) async {
    try {
      if (enable) {
        await WakelockPlus.enable();
        if (kDebugMode) {
          print('[Wakelock] Enabled');
        }
      } else {
        await WakelockPlus.disable();
        if (kDebugMode) {
          print('[Wakelock] Disabled');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('[Wakelock] Failed to ${enable ? 'enable' : 'disable'}: $e');
      }
    }
  }

  Future<void> _applyHidGraceWindow(int ms) async {
    try {
      final service = ref.read(platformGadgetServiceProvider);
      await service.setHidGraceWindowMs(ms);
    } catch (_) {}
  }

  Future<void> _applyUnicodeFallbackMode(String mode) async {
    try {
      final service = ref.read(platformGadgetServiceProvider);
      await service.setUnicodeFallbackMode(mode);
    } catch (_) {}
  }

  Future<void> _applyTypingSpeedFactor(double delayMultiplier) async {
    try {
      final service = ref.read(platformGadgetServiceProvider);
      await service.setTypingSpeedFactor(delayMultiplier);
    } catch (_) {}
  }

  Future<void> _applyRiskyFastMode(bool enabled) async {
    try {
      final service = ref.read(platformGadgetServiceProvider);
      await service.setRiskyFastMode(enabled);
    } catch (_) {}
  }

  Future<void> _applyDialShortcutBindings(List<DialShortcutBinding> bindings) async {
    try {
      final service = ref.read(platformGadgetServiceProvider);
      await service.setDialShortcutBindings(bindings: bindings);
    } catch (_) {}
  }

  Future<void> _save(AppSettings s) async {
    state = AsyncData(s);
    final repo = await ref.read(settingsRepositoryProvider.future);
    await repo.save(s);
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../data/models/app_settings.dart';
import '../providers.dart';

final appSettingsControllerProvider = AsyncNotifierProvider<AppSettingsController, AppSettings>(
  AppSettingsController.new,
);

class AppSettingsController extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() async {
    final repo = await ref.watch(settingsRepositoryProvider.future);
    final loaded = repo.load();

    await _applyWakelockState(loaded.keepScreenOn);
    await _applyHidGraceWindow(loaded.hidGraceWindowMs);
    await _applyUnicodeFallbackMode(loaded.unicodeFallbackMode);
    await _applyTypingSpeedFactor(loaded.typingSpeedFactor);
    await _applyRiskyFastMode(loaded.riskyFastMode);
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
    final s = (state.value ?? AppSettings.defaults()).copyWith(typingSpeedFactor: clamped);
    await _applyTypingSpeedFactor(clamped);
    await _save(s);
  }

  Future<void> setRandomizeTiming(bool v) async {
    final s = (state.value ?? AppSettings.defaults()).copyWith(randomizeTiming: v);
    await _save(s);
  }

  Future<void> setKeepScreenOn(bool v) async {
    final s = (state.value ?? AppSettings.defaults()).copyWith(keepScreenOn: v);
    await _applyWakelockState(v);
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
    final s = (state.value ?? AppSettings.defaults()).copyWith(hidGraceWindowMs: clamped);
    await _applyHidGraceWindow(clamped);
    await _save(s);
  }

  Future<void> setUnicodeFallbackMode(String mode) async {
    final normalized = mode.trim().toLowerCase();
    final safe = (normalized == 'skip' || normalized == 'warn' || normalized == 'ascii') ? normalized : 'warn';
    final s = (state.value ?? AppSettings.defaults()).copyWith(unicodeFallbackMode: safe);
    await _applyUnicodeFallbackMode(safe);
    await _save(s);
  }

  Future<void> setRiskyFastMode(bool v) async {
    final s = (state.value ?? AppSettings.defaults()).copyWith(riskyFastMode: v);
    await _applyRiskyFastMode(v);
    await _save(s);
  }

  Future<void> resetAllToDefaults() async {
    final defaults = AppSettings.defaults();
    await _applyWakelockState(defaults.keepScreenOn);
    await _applyHidGraceWindow(defaults.hidGraceWindowMs);
    await _applyUnicodeFallbackMode(defaults.unicodeFallbackMode);
    await _applyTypingSpeedFactor(defaults.typingSpeedFactor);
    await _applyRiskyFastMode(defaults.riskyFastMode);
    await _applyDialShortcutBindings(defaults.dialShortcuts);
    await _save(defaults);
  }

  Future<void> setDialShortcuts(List<DialShortcutBinding> bindings) async {
    final s = (state.value ?? AppSettings.defaults()).copyWith(dialShortcuts: bindings);
    await _applyDialShortcutBindings(bindings);
    await _save(s);
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

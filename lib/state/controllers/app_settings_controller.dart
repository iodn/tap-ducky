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
  Future<void> _executionUpdates = Future.value();

  @override
  Future<AppSettings> build() async {
    final repo = await ref.watch(settingsRepositoryProvider.future);
    final loaded = repo.load();

    await _applyExecutionSettings(loaded, bestEffort: true);
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
    await _updateExecutionSetting(
      () => ref.read(platformGadgetServiceProvider).setTypingSpeedFactor(clamped),
      (settings) => settings.copyWith(typingSpeedFactor: clamped),
    );
  }

  Future<void> setRandomizeTiming(bool v) async {
    final s = (state.value ?? AppSettings.defaults()).copyWith(randomizeTiming: v);
    await _save(s);
  }

  Future<void> setKeepScreenOn(bool v) async {
    await _updateExecutionSetting(
      () => WakelockPlus.toggle(enable: v),
      (settings) => settings.copyWith(keepScreenOn: v),
    );
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
    await _updateExecutionSetting(
      () => ref.read(platformGadgetServiceProvider).setHidGraceWindowMs(clamped),
      (settings) => settings.copyWith(hidGraceWindowMs: clamped),
    );
  }

  Future<void> setUnicodeFallbackMode(String mode) async {
    final normalized = mode.trim().toLowerCase();
    final safe = (normalized == 'skip' || normalized == 'warn' || normalized == 'ascii') ? normalized : 'warn';
    await _updateExecutionSetting(
      () => ref.read(platformGadgetServiceProvider).setUnicodeFallbackMode(safe),
      (settings) => settings.copyWith(unicodeFallbackMode: safe),
    );
  }

  Future<void> setRiskyFastMode(bool v) async {
    await _updateExecutionSetting(
      () => ref.read(platformGadgetServiceProvider).setRiskyFastMode(v),
      (settings) => settings.copyWith(riskyFastMode: v),
    );
  }

  Future<void> resetExecutionDefaults() => _queueExecutionUpdate(() async {
    final defaults = AppSettings.defaults();
    await _resetExecutionSettings(defaults);
    await _save((state.value ?? defaults).copyWith(
      enableLogging: defaults.enableLogging,
      delayMultiplier: defaults.delayMultiplier,
      typingSpeedFactor: defaults.typingSpeedFactor,
      hidGraceWindowMs: defaults.hidGraceWindowMs,
      unicodeFallbackMode: defaults.unicodeFallbackMode,
      riskyFastMode: defaults.riskyFastMode,
      keepScreenOn: defaults.keepScreenOn,
    ));
  });

  Future<void> resetAllToDefaults() => _queueExecutionUpdate(() async {
    final defaults = AppSettings.defaults();
    await _resetExecutionSettings(defaults);
    await _applyDialShortcutBindings(defaults.dialShortcuts);
    await _save(defaults);
  });

  Future<void> setDialShortcuts(List<DialShortcutBinding> bindings) async {
    final s = (state.value ?? AppSettings.defaults()).copyWith(dialShortcuts: bindings);
    await _applyDialShortcutBindings(bindings);
    await _save(s);
  }

  Future<void> _queueExecutionUpdate(Future<void> Function() update) {
    final pending = _executionUpdates.then((_) => update());
    _executionUpdates = pending.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return pending;
  }

  Future<void> _updateExecutionSetting(
    Future<void> Function() apply,
    AppSettings Function(AppSettings) update,
  ) => _queueExecutionUpdate(() async {
    await apply();
    await _save(update(state.value ?? AppSettings.defaults()));
  });

  Future<void> _resetExecutionSettings(AppSettings defaults) async {
    final previous = state.value ?? defaults;
    try {
      await _applyExecutionSettings(defaults);
    } catch (_) {
      await _applyExecutionSettings(previous, bestEffort: true);
      rethrow;
    }
  }

  Future<void> _applyExecutionSettings(
    AppSettings settings, {
    bool bestEffort = false,
  }) async {
    final service = ref.read(platformGadgetServiceProvider);
    final operations = <Future<void> Function()>[
      () => WakelockPlus.toggle(enable: settings.keepScreenOn),
      () => service.setHidGraceWindowMs(settings.hidGraceWindowMs),
      () => service.setUnicodeFallbackMode(settings.unicodeFallbackMode),
      () => service.setTypingSpeedFactor(settings.typingSpeedFactor),
      () => service.setRiskyFastMode(settings.riskyFastMode),
    ];
    for (final apply in operations) {
      try {
        await apply();
      } catch (error) {
        if (!bestEffort) rethrow;
        if (kDebugMode) debugPrint('Could not sync an execution setting: $error');
      }
    }
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

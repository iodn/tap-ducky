import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/app_settings.dart';
import '../../../data/models/host_os.dart';
import '../../../state/controllers/app_settings_controller.dart';
import '../../../state/controllers/hid_status_controller.dart';

/// Session-scoped host OS diagnostics.
///
/// Native inference follows the current USB connection. The saved manual
/// label is the fallback when no session result is available.
final hostOsControllerProvider =
    NotifierProvider<HostOsController, HostOsDiagnostic>(HostOsController.new);

class HostOsController extends Notifier<HostOsDiagnostic> {
  @override
  HostOsDiagnostic build() {
    ref.listen<HidStatus>(hidStatusControllerProvider, (previous, next) {
      final inference = _fromUsb(next);
      if (inference != null) {
        state = inference;
        return;
      }
      if (previous == null) return;
      final sessionEnded = previous.sessionArmed && !next.sessionArmed;
      final hostLost = previous.deviceConnected && !next.deviceConnected;
      final newHostPresent = next.hostConfigurationRequestCount >
          previous.hostConfigurationRequestCount;
      final evidenceLost = _fromUsb(previous) != null;
      if (sessionEnded || hostLost || newHostPresent || evidenceLost) {
        clearSessionOs();
      }
    });

    ref.listen<AsyncValue<AppSettings>>(appSettingsControllerProvider, (
      previous,
      next,
    ) {
      if (state.isSessionScoped) return;
      final manual = next.value?.manualHostOs;
      state = _fromManual(manual);
    });

    return _fromUsb(ref.read(hidStatusControllerProvider)) ??
        _fromManual(ref.read(appSettingsControllerProvider).value?.manualHostOs);
  }

  /// Stores a diagnostic label chosen by the user. Passing null returns the
  /// diagnostic to Unknown. This never touches execution state.
  Future<void> setManual(HostOs? os) async {
    state = _fromUsb(ref.read(hidStatusControllerProvider)) ?? _fromManual(os);
    await ref.read(appSettingsControllerProvider.notifier).setManualHostOs(os);
  }

  /// Drops an inferred or verified value when the USB host/session ends.
  /// A manually selected label is a persistent user preference and survives.
  void clearSessionOs() {
    if (!state.isSessionScoped) return;
    state = _fromManual(
      ref.read(appSettingsControllerProvider).value?.manualHostOs,
    );
  }

  /// Test seam for session-scoped diagnostics supplied outside USB status.
  @visibleForTesting
  void applySessionOs(HostOs os, HostOsSource source) {
    assert(os != HostOs.unknown, 'A session OS must be known');
    assert(
      source == HostOsSource.inferred || source == HostOsSource.verified,
      'Only inferred or verified values are session-scoped',
    );
    state = HostOsDiagnostic(os: os, source: source);
  }

  static HostOsDiagnostic _fromManual(HostOs? os) {
    if (os == null || os == HostOs.unknown) return HostOsDiagnostic.unknown;
    return HostOsDiagnostic(os: os, source: HostOsSource.manual);
  }

  static HostOsDiagnostic? _fromUsb(HidStatus status) {
    if (!status.sessionArmed || !status.deviceConnected ||
        status.inferredHostOs == HostOs.unknown) {
      return null;
    }
    return HostOsDiagnostic(
      os: status.inferredHostOs,
      source: HostOsSource.inferred,
    );
  }
}

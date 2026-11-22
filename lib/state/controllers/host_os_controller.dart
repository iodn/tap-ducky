import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/app_settings.dart';
import '../../../data/models/host_os.dart';
import '../../../state/controllers/app_settings_controller.dart';
import '../../../state/controllers/hid_status_controller.dart';

/// Session-scoped host OS diagnostics.
///
/// The USB backend exposes connection state only; it has no signal that
/// identifies the host OS. Manual labels are therefore the only shipped
/// source. Inferred and verified values can be supplied by future, separately
/// validated producers; they are discarded whenever the USB session ends.
final hostOsControllerProvider =
    NotifierProvider<HostOsController, HostOsDiagnostic>(HostOsController.new);

class HostOsController extends Notifier<HostOsDiagnostic> {
  @override
  HostOsDiagnostic build() {
    ref.listen<HidStatus>(hidStatusControllerProvider, (previous, next) {
      if (previous == null) return;
      final sessionEnded = previous.sessionArmed && !next.sessionArmed;
      final hostLost = previous.deviceConnected && !next.deviceConnected;
      final newHostPresent = next.hostConfigurationRequestCount >
          previous.hostConfigurationRequestCount;
      if (sessionEnded || hostLost || newHostPresent) clearSessionOs();
    });

    ref.listen<AsyncValue<AppSettings>>(appSettingsControllerProvider, (
      previous,
      next,
    ) {
      if (state.isSessionScoped) return;
      final manual = next.value?.manualHostOs;
      state = _fromManual(manual);
    });

    return _fromManual(ref.read(appSettingsControllerProvider).value?.manualHostOs);
  }

  /// Stores a diagnostic label chosen by the user. Passing null returns the
  /// diagnostic to Unknown. This never touches execution state.
  Future<void> setManual(HostOs? os) async {
    state = _fromManual(os);
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

  /// Test seam for the disconnect behavior and for a future, evidence-backed
  /// producer. No classifier or companion calls this today.
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
}

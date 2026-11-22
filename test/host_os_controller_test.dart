import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tap_ducky/data/models/app_settings.dart';
import 'package:tap_ducky/data/models/host_os.dart';
import 'package:tap_ducky/state/controllers/app_settings_controller.dart';
import 'package:tap_ducky/state/controllers/hid_status_controller.dart';
import 'package:tap_ducky/state/controllers/host_os_controller.dart';

class _TestSettingsController extends AppSettingsController {
  _TestSettingsController(this.initial);

  final AppSettings initial;

  @override
  Future<AppSettings> build() async => initial;

  @override
  Future<void> setManualHostOs(HostOs? os) async {
    state = AsyncData((state.value ?? initial).copyWith(manualHostOs: os));
  }
}

class _TestHidController extends HidStatusController {
  @override
  HidStatus build() => _status();

  void emit(HidStatus value) {
    state = value;
  }
}

HidStatus _status({
  bool armed = true,
  bool connected = true,
  int hostPresentTransitions = 0,
}) {
  return HidStatus(
    rootAvailable: true,
    hidSupported: true,
    deviceConnected: connected,
    sessionArmed: armed,
    hostConfigurationRequestCount: hostPresentTransitions,
  );
}

Future<ProviderContainer> _createContainer({HostOs? manual}) async {
  final settings = AppSettings.defaults().copyWith(manualHostOs: manual);
  final container = ProviderContainer.test(
    overrides: [
      appSettingsControllerProvider.overrideWith(
        () => _TestSettingsController(settings),
      ),
      hidStatusControllerProvider.overrideWith(_TestHidController.new),
    ],
  );
  await container.read(appSettingsControllerProvider.future);
  container.read(hostOsControllerProvider);
  return container;
}

void main() {
  test('defaults to Unknown when no manual label exists', () async {
    final container = await _createContainer();

    expect(container.read(hostOsControllerProvider), HostOsDiagnostic.unknown);
  });

  test('persisted manual selection is restored as manual', () async {
    final container = await _createContainer(manual: HostOs.windows);
    final diagnostic = container.read(hostOsControllerProvider);

    expect(diagnostic.os, HostOs.windows);
    expect(diagnostic.source, HostOsSource.manual);
    expect(diagnostic.label, 'Windows (Manually selected)');
  });

  test('manual selection is stored and clearing it returns Unknown', () async {
    final container = await _createContainer();
    final controller = container.read(hostOsControllerProvider.notifier);

    await controller.setManual(HostOs.linux);
    expect(
      container.read(hostOsControllerProvider).label,
      'Linux (Manually selected)',
    );
    expect(
      (await container.read(appSettingsControllerProvider.future)).manualHostOs,
      HostOs.linux,
    );

    await controller.setManual(null);
    expect(container.read(hostOsControllerProvider), HostOsDiagnostic.unknown);
    expect(
      (await container.read(appSettingsControllerProvider.future)).manualHostOs,
      isNull,
    );
  });

  test('inferred OS is discarded on disconnect and falls back to manual',
      () async {
    final container = await _createContainer(manual: HostOs.windows);
    final controller = container.read(hostOsControllerProvider.notifier);
    final hid = container.read(hidStatusControllerProvider.notifier)
        as _TestHidController;

    controller.applySessionOs(HostOs.linux, HostOsSource.inferred);
    expect(container.read(hostOsControllerProvider).label, 'Likely Linux');

    hid.emit(_status(connected: false));

    final after = container.read(hostOsControllerProvider);
    expect(after.os, HostOs.windows);
    expect(after.source, HostOsSource.manual);
  });

  test('verified OS without a manual fallback returns Unknown on session end',
      () async {
    final container = await _createContainer();
    final controller = container.read(hostOsControllerProvider.notifier);
    final hid = container.read(hidStatusControllerProvider.notifier)
        as _TestHidController;

    controller.applySessionOs(HostOs.macos, HostOsSource.verified);
    expect(
      container.read(hostOsControllerProvider).label,
      'macOS (Verified by companion)',
    );

    hid.emit(_status(armed: false));

    expect(container.read(hostOsControllerProvider), HostOsDiagnostic.unknown);
  });

  test('a new host-present transition clears a session OS', () async {
    final container = await _createContainer();
    final controller = container.read(hostOsControllerProvider.notifier);
    final hid = container.read(hidStatusControllerProvider.notifier)
        as _TestHidController;

    controller.applySessionOs(HostOs.linux, HostOsSource.inferred);
    expect(container.read(hostOsControllerProvider).label, 'Likely Linux');

    hid.emit(_status(hostPresentTransitions: 2));

    expect(container.read(hostOsControllerProvider), HostOsDiagnostic.unknown);
  });

  test('manual labels survive host disconnects', () async {
    final container = await _createContainer(manual: HostOs.android);
    final hid = container.read(hidStatusControllerProvider.notifier)
        as _TestHidController;

    hid.emit(_status(connected: false));

    final after = container.read(hostOsControllerProvider);
    expect(after.os, HostOs.android);
    expect(after.source, HostOsSource.manual);
  });
}

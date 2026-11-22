import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tap_ducky/data/models/app_settings.dart';
import 'package:tap_ducky/data/services/platform_gadget_service.dart';
import 'package:tap_ducky/state/controllers/app_settings_controller.dart';
import 'package:tap_ducky/state/controllers/execution_controller.dart';
import 'package:tap_ducky/state/controllers/hid_status_controller.dart';
import 'package:tap_ducky/state/providers.dart';

class _TestSettings extends AppSettingsController {
  @override
  Future<AppSettings> build() async =>
      AppSettings.defaults().copyWith(enableLogging: false);
}

class _ArmedHid extends HidStatusController {
  @override
  HidStatus build() => const HidStatus(
    rootAvailable: true,
    hidSupported: true,
    deviceConnected: true,
    sessionArmed: true,
  );
}

class _SilentGadget extends PlatformGadgetService {
  @override
  late final execStream = const Stream<Map<String, dynamic>>.empty();

  String? startedId;
  final cancelledIds = <String>[];
  int panicCount = 0;

  @override
  Future<void> setKeyboardLayout(int layoutId) async {}

  @override
  Future<void> executeDuckyScript({
    required String script,
    required double delayMultiplier,
    String? executionId,
  }) async {
    startedId = executionId;
  }

  @override
  Future<void> cancelExecution(String executionId) async {
    cancelledIds.add(executionId);
  }

  @override
  Future<void> panicStop() async {
    panicCount++;
  }
}

void main() {
  testWidgets('timeout keeps execution busy until stop escalates', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = _SilentGadget();
    final container = ProviderContainer.test(overrides: [
      platformGadgetServiceProvider.overrideWithValue(service),
      appSettingsControllerProvider.overrideWith(_TestSettings.new),
      hidStatusControllerProvider.overrideWith(_ArmedHid.new),
    ]);
    await container.read(appSettingsControllerProvider.future);
    final controller = container.read(executionControllerProvider.notifier);

    await controller.sendRawCommand('DELAY 100');
    final id = service.startedId;
    expect(id, isNotNull);

    await tester.pump(const Duration(seconds: 91));
    expect(service.cancelledIds, [id]);
    expect(container.read(executionControllerProvider).isRunning, isTrue);
    expect(container.read(executionControllerProvider).stopRequested, isTrue);

    await controller.stop();
    expect(service.cancelledIds, [id]);

    await tester.pump(const Duration(seconds: 6));
    expect(service.cancelledIds, [id, '*']);
    expect(service.panicCount, 1);
    expect(container.read(executionControllerProvider).isRunning, isFalse);
  });
}

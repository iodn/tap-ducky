import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tap_ducky/data/models/app_settings.dart';
import 'package:tap_ducky/data/models/payload.dart';
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
  Stream<Map<String, dynamic>> get execStream => const Stream.empty();

  String? startedId;
  final startedScripts = <String>[];
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
    startedScripts.add(script);
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

Future<ProviderContainer> _createContainer(_SilentGadget service) async {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer.test(overrides: [
    platformGadgetServiceProvider.overrideWithValue(service),
    appSettingsControllerProvider.overrideWith(_TestSettings.new),
    hidStatusControllerProvider.overrideWith(_ArmedHid.new),
  ]);
  await container.read(appSettingsControllerProvider.future);
  return container;
}

void main() {
  testWidgets('timeout keeps execution busy until stop escalates', (tester) async {
    final service = _SilentGadget();
    final container = await _createContainer(service);
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

  test('a payload reserves execution before saving preferences', () async {
    final service = _SilentGadget();
    final container = await _createContainer(service);
    final controller = container.read(executionControllerProvider.notifier);

    final run = controller.runPayload(const Payload(
      id: 'first',
      name: 'First',
      description: '',
      script: 'DELAY 100',
      tags: [],
      parameters: [],
      isBuiltin: false,
    ), {});
    final competing = controller.sendRawCommand('DELAY 200');
    await Future.wait([run, competing]);
    await controller.panicStop();

    expect(service.startedScripts, ['DELAY 100']);
  });
}

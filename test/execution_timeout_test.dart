import 'dart:async';

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
    gadgetBound: true,
  );
}

class _SilentGadget extends PlatformGadgetService {
  _SilentGadget({this.events});

  final StreamController<Map<String, dynamic>>? events;

  @override
  Stream<Map<String, dynamic>> get execStream =>
      events?.stream ?? const Stream.empty();

  String? startedId;
  final startedScripts = <String>[];
  final cancelledIds = <String>[];
  final acceptedPrompts = <(String, String)>[];
  final buttonPresses = <String>[];
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
  Future<bool> confirmButtonPrompt(String executionId, String promptId) async {
    acceptedPrompts.add((executionId, promptId));
    return true;
  }

  @override
  Future<bool> pressScriptButton(String executionId) async {
    buttonPresses.add(executionId);
    return true;
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
  testWidgets('activity indicator updates leave execution progress active', (tester) async {
    final events = StreamController<Map<String, dynamic>>.broadcast();
    addTearDown(events.close);
    final service = _SilentGadget(events: events);
    final container = await _createContainer(service);
    final controller = container.read(executionControllerProvider.notifier);
    await controller.sendRawCommand('DELAY 20');
    final id = service.startedId!;
    events.add({'type': 'activity_indicator', 'executionId': id, 'enabled': false});
    events.add({'type': 'step', 'executionId': id, 'progress': 0.5});
    await tester.pump();
    final active = container.read(executionControllerProvider);
    expect(active.activityIndicatorEnabled, isFalse);
    expect(active.activityStep, 1);
    expect(active.isRunning, isTrue);
    expect(active.progress, 0.5);
    await controller.stop();
    expect(service.cancelledIds, [id]);
    events.add({'type': 'done', 'executionId': id, 'cancelled': true});
    await tester.pump();
  });

  testWidgets('polling scripts receive presses only for the active run', (tester) async {
    final events = StreamController<Map<String, dynamic>>.broadcast();
    addTearDown(events.close);
    final service = _SilentGadget(events: events);
    final container = await _createContainer(service);
    final controller = container.read(executionControllerProvider.notifier);
    await controller.sendRawCommand(r'DELAY $_BUTTON_PUSH_RECEIVED');
    final id = service.startedId!;

    await controller.pressScriptButton(id);
    events.add({'type': 'button_available', 'executionId': id});
    await tester.pump();
    await controller.pressScriptButton('other-run');
    await controller.pressScriptButton(id);
    expect(service.buttonPresses, [id]);

    events.add({'type': 'button_available', 'executionId': id, 'available': false});
    await tester.pump();
    await controller.pressScriptButton(id);
    expect(service.buttonPresses, [id]);
    events.add({'type': 'done', 'executionId': id, 'success': true});
    await tester.pump();
  });

  testWidgets('button wait accepts the active prompt and clears it on stop', (tester) async {
    final events = StreamController<Map<String, dynamic>>.broadcast();
    addTearDown(events.close);
    final service = _SilentGadget(events: events);
    final container = await _createContainer(service);
    final controller = container.read(executionControllerProvider.notifier);
    await controller.sendRawCommand('WAIT_FOR_BUTTON_PRESS');
    final id = service.startedId!;

    void waitForPress(String prompt) => events.add({
      'type': 'wait', 'executionId': id, 'waitMs': 60000, 'promptId': prompt,
    });

    waitForPress('first');
    await tester.pump();
    expect(container.read(executionControllerProvider).buttonPromptId, 'first');
    await controller.confirmButtonPrompt('stale');
    await controller.confirmButtonPrompt('first');
    expect(service.acceptedPrompts, [(id, 'first')]);
    expect(container.read(executionControllerProvider).buttonPromptId, isNull);

    waitForPress('second');
    await tester.pump();
    await controller.stop();
    await controller.confirmButtonPrompt('second');
    expect(service.acceptedPrompts, [(id, 'first')]);
    expect(container.read(executionControllerProvider).buttonPromptId, isNull);
    events.add({'type': 'done', 'executionId': id, 'cancelled': true});
    await tester.pump();
  });

  testWidgets('native failure ends execution without reporting 100%', (tester) async {
    final events = StreamController<Map<String, dynamic>>.broadcast();
    addTearDown(events.close);
    final service = _SilentGadget(events: events);
    final container = await _createContainer(service);
    final controller = container.read(executionControllerProvider.notifier);

    await controller.sendRawCommand('STRING hello');
    final id = service.startedId;
    expect(container.read(executionControllerProvider).isRunning, isTrue);

    events.add({
      'type': 'error',
      'executionId': id,
      'message': 'Host disconnected',
      'error_code': 'HOST_DISCONNECTED',
      'elapsedMs': 125,
    });
    await tester.pump();

    final failed = container.read(executionControllerProvider);
    expect(failed.isRunning, isFalse);
    expect(failed.success, isFalse);
    expect(failed.progress, lessThan(1));
    expect(failed.tail.last.message, contains('Host disconnected'));
    expect(failed.tail.last.meta?['durationMs'], '125');
    expect(failed.tail.last.meta?['error_code'], 'HOST_DISCONNECTED');

    await tester.pump(const Duration(seconds: 100));
    expect(service.cancelledIds, isEmpty);
    await controller.sendRawCommand('DELAY 100');
    expect(container.read(executionControllerProvider).success, isNull);
    events.add({
      'type': 'done',
      'executionId': service.startedId,
      'success': true,
      'elapsedMs': 101,
    });
    await tester.pump();
    final completed = container.read(executionControllerProvider);
    expect(completed.success, isTrue);
    expect(completed.progress, 1);
    expect(completed.tail.last.meta?['durationMs'], '101');
  });

  testWidgets('watchdog allows the wait announced by Android', (tester) async {
    final events = StreamController<Map<String, dynamic>>.broadcast();
    addTearDown(events.close);
    final service = _SilentGadget(events: events);
    final container = await _createContainer(service);
    final controller = container.read(executionControllerProvider.notifier);

    await controller.sendRawCommand('WAIT_FOR HOST_CONNECTED 300000');
    events.add({
      'type': 'wait',
      'executionId': service.startedId,
      'lineNumber': 1,
      'message': 'Waiting for HOST_CONNECTED',
      'waitMs': 300000,
    });
    await tester.pump();
    await tester.pump(const Duration(seconds: 100));

    expect(service.cancelledIds, isEmpty);
    final running = container.read(executionControllerProvider);
    expect(running.status, 'Waiting for HOST_CONNECTED');
    expect(running.tail.last.message, contains('Line 1'));
    await tester.pump(const Duration(seconds: 291));
    expect(service.cancelledIds, [service.startedId]);
    events.add({
      'type': 'done',
      'executionId': service.startedId,
      'cancelled': true,
    });
    await tester.pump();
    expect(container.read(executionControllerProvider).isRunning, isFalse);
  });

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

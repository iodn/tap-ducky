import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tap_ducky/data/models/app_settings.dart';
import 'package:tap_ducky/data/models/execution_outcome.dart';
import 'package:tap_ducky/data/models/payload.dart';
import 'package:tap_ducky/data/models/run_recording.dart';
import 'package:tap_ducky/data/services/platform_gadget_service.dart';
import 'package:tap_ducky/state/controllers/app_settings_controller.dart';
import 'package:tap_ducky/state/controllers/execution_controller.dart';
import 'package:tap_ducky/state/controllers/hid_status_controller.dart';
import 'package:tap_ducky/state/controllers/logs_controller.dart';
import 'package:tap_ducky/state/controllers/run_observation_controller.dart';
import 'package:tap_ducky/state/providers.dart';
import 'package:tap_ducky/widgets/task_bar.dart';

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

  @override
  Stream<Map<String, dynamic>> get logsStream => const Stream.empty();

  String? startedId;
  final startedScripts = <String>[];
  final cancelledIds = <String>[];
  final acceptedPrompts = <(String, String)>[];
  final buttonPresses = <String>[];
  bool rejectLayout = false;
  Completer<void>? layoutStarted;
  Completer<void>? layoutPending;
  int panicCount = 0;
  String? panicExecutionId;
  bool panicInputReleased = true;
  bool panicThrows = false;

  @override
  Future<void> setKeyboardLayout(int layoutId) async {
    if (rejectLayout) throw StateError('Android rejected the layout');
    layoutStarted?.complete();
    await layoutPending?.future;
  }

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
  Future<bool> panicStop({String? executionId}) async {
    panicCount++;
    panicExecutionId = executionId;
    if (panicThrows) throw StateError('Panic stop unavailable');
    return panicInputReleased;
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
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a rejected keyboard layout stops the run before Android receives the script', () async {
    final events = StreamController<Map<String, dynamic>>.broadcast();
    addTearDown(events.close);
    final service = _SilentGadget(events: events)..rejectLayout = true;
    final container = await _createContainer(service);
    final controller = container.read(executionControllerProvider.notifier);
    await controller.sendRawCommand('DELAY 100');

    expect(service.startedScripts, isEmpty);
    final execution = container.read(executionControllerProvider);
    expect(execution.isRunning, isFalse);
    expect(execution.status, contains('Could not apply the selected keyboard layout'));
  });

  test('a stop while Android applies the layout prevents execution', () async {
    final events = StreamController<Map<String, dynamic>>.broadcast();
    addTearDown(events.close);
    final service = _SilentGadget(events: events)
      ..layoutStarted = Completer<void>()
      ..layoutPending = Completer<void>();
    final container = await _createContainer(service);
    final controller = container.read(executionControllerProvider.notifier);
    final start = controller.sendRawCommand('DELAY 100');
    await service.layoutStarted!.future;
    await controller.stop();
    service.layoutPending!.complete();
    await start;

    expect(service.startedScripts, isEmpty);
    final stopped = container.read(executionControllerProvider);
    expect(stopped.outcome, ExecutionOutcome.stopped);
    expect(stopped.status, 'Stopped');
  });

  testWidgets('activity indicator updates leave execution progress active', (tester) async {
    final events = StreamController<Map<String, dynamic>>.broadcast();
    addTearDown(events.close);
    final service = _SilentGadget(events: events);
    final container = await _createContainer(service);
    final controller = container.read(executionControllerProvider.notifier);
    await controller.sendRawCommand('DELAY 20');
    final id = service.startedId!;
    events.add({'type': 'start', 'executionId': id});
    events.add({'type': 'activity_indicator', 'executionId': id, 'enabled': false});
    events.add({'type': 'system_indicator', 'executionId': id, 'enabled': true});
    events.add({'type': 'script_indicator', 'executionId': id, 'color': 'red'});
    events.add({'type': 'step', 'executionId': id, 'progress': 0.5});
    await tester.pump();
    final active = container.read(executionControllerProvider);
    expect(active.activityIndicatorEnabled, isFalse);
    expect(active.activityStep, 1);
    expect(active.systemIndicatorEnabled, isTrue);
    expect(active.scriptIndicator, ScriptIndicator.red);
    expect(active.systemIndicatorStep, 1);
    expect(active.isRunning, isTrue);
    expect(active.progress, 0.5);
    events.add({'type': 'system_indicator', 'executionId': id, 'enabled': false});
    events.add({'type': 'script_indicator', 'executionId': id, 'color': 'off'});
    await tester.pump();
    expect(container.read(executionControllerProvider).systemIndicatorEnabled, isFalse);
    expect(container.read(executionControllerProvider).scriptIndicator, ScriptIndicator.off);
    await controller.stop();
    expect(service.cancelledIds, [id]);
    events.add({'type': 'done', 'executionId': id, 'cancelled': true});
    await tester.pump();
    expect(container.read(executionControllerProvider).systemIndicatorStep, 2);
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
    events.add({'type': 'done', 'executionId': id, 'success': true, 'inputReleased': true});
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
      'type': 'wait', 'executionId': id, 'promptId': prompt,
    });

    waitForPress('first');
    await tester.pump();
    await tester.pump(const Duration(minutes: 3));
    expect(service.cancelledIds, isEmpty);
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

  testWidgets('the execution watchdog resumes after a confirmed button wait', (tester) async {
    final events = StreamController<Map<String, dynamic>>.broadcast();
    addTearDown(events.close);
    final service = _SilentGadget(events: events);
    final container = await _createContainer(service);
    final controller = container.read(executionControllerProvider.notifier);
    await controller.sendRawCommand('WAIT_FOR_BUTTON_PRESS');
    final id = service.startedId!;

    events.add({'type': 'wait', 'executionId': id, 'promptId': 'current'});
    events.add({'type': 'button_resumed', 'executionId': id, 'promptId': 'stale'});
    await tester.pump();
    await tester.pump(const Duration(minutes: 3));
    expect(service.cancelledIds, isEmpty);

    await controller.confirmButtonPrompt('current');
    events.add({'type': 'button_resumed', 'executionId': id, 'promptId': 'current'});
    await tester.pump();
    await tester.pump(const Duration(seconds: 95));
    expect(service.cancelledIds, [id]);
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
      'inputReleased': true,
      'elapsedMs': 101,
    });
    await tester.pump();
    final completed = container.read(executionControllerProvider);
    expect(completed.success, isTrue);
    expect(completed.outcome, ExecutionOutcome.completed);
    expect(completed.progress, 1);
    expect(completed.tail.last.meta?['durationMs'], '101');
  });

  testWidgets('finishing without confirmed release flags cleanup and withholds completion', (tester) async {
    final events = StreamController<Map<String, dynamic>>.broadcast();
    addTearDown(events.close);
    final service = _SilentGadget(events: events);
    final container = await _createContainer(service);
    final controller = container.read(executionControllerProvider.notifier);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(bottomNavigationBar: TaskBar())),
    ));
    await controller.sendRawCommand('DELAY 20');

    events.add({
      'type': 'done',
      'executionId': service.startedId,
      'success': false,
      'inputReleased': false,
      'error_code': 'INPUT_RELEASE_UNCONFIRMED',
    });
    await tester.pump();
    final state = container.read(executionControllerProvider);
    expect(state.outcome, ExecutionOutcome.failed);
    expect(state.success, isFalse);
    expect(state.inputReleaseUnconfirmed, isTrue);
    expect(state.status, contains('Input release could not be confirmed'));
    expect(state.tail.last.meta?['inputReleased'], 'false');
    expect(state.tail.last.meta?['outcome'], 'failed');
    expect(state.panicAvailable, isTrue);

    final retry = find.text('Retry input release');
    expect(retry, findsOneWidget);
    service.panicInputReleased = false;
    await tester.tap(retry);
    await tester.pump();
    expect(container.read(executionControllerProvider).panicAvailable, isTrue);
    expect(container.read(executionControllerProvider).inputReleaseUnconfirmed, isTrue);

    service.panicInputReleased = true;
    await tester.tap(retry);
    await tester.pump();
    final recovered = container.read(executionControllerProvider);
    expect(service.panicExecutionId, service.startedId);
    expect(service.panicCount, 2);
    expect(recovered.inputReleaseUnconfirmed, isFalse);
    expect(recovered.status, 'Script finished');
    expect(recovered.outcome, ExecutionOutcome.failed);
    expect(recovered.tail.last.meta?['inputReleased'], 'false');
    expect(service.startedScripts, ['DELAY 20']);
    expect(retry, findsNothing);
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
      'waitId': 1,
    });
    await tester.pump();
    await tester.pump(const Duration(seconds: 100));

    expect(service.cancelledIds, isEmpty);
    final running = container.read(executionControllerProvider);
    expect(running.status, 'Waiting for HOST_CONNECTED');
    expect(running.tail.last.message, contains('Line 1'));
    events.add({
      'type': 'wait_end',
      'executionId': service.startedId,
      'waitId': 1,
      'lineNumber': 1,
      'resumed': true,
    });
    await tester.pump();
    expect(container.read(runObservationProvider)?.waitUntil, isNull);
    expect(container.read(executionControllerProvider).status, 'Running…');
    await tester.pump(const Duration(seconds: 291));
    expect(service.cancelledIds, [service.startedId]);
    events.add({
      'type': 'done',
      'executionId': service.startedId,
      'cancelled': true,
    });
    await tester.pump();
    expect(container.read(executionControllerProvider).isRunning, isFalse);
    expect(container.read(executionControllerProvider).outcome, ExecutionOutcome.timedOut);
  });

  testWidgets('timeout keeps execution busy until stop escalates', (tester) async {
    final service = _SilentGadget()..panicInputReleased = false;
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
    expect(service.cancelledIds, [id]);
    expect(service.panicCount, 1);
    expect(service.panicExecutionId, id);
    expect(container.read(executionControllerProvider).isRunning, isFalse);
    expect(container.read(executionControllerProvider).outcome, ExecutionOutcome.timedOut);
    expect(container.read(executionControllerProvider).inputReleaseUnconfirmed, isTrue);
    expect(container.read(executionControllerProvider).panicAvailable, isTrue);
    service.panicInputReleased = true;
    await controller.retryInputRelease();
    expect(service.panicCount, 2);
    expect(service.panicExecutionId, id);
    expect(container.read(executionControllerProvider).inputReleaseUnconfirmed, isFalse);
    expect(container.read(executionControllerProvider).outcome, ExecutionOutcome.timedOut);
  });

  test('failed panic transport leaves the same run stoppable', () async {
    final service = _SilentGadget()..panicThrows = true;
    final container = await _createContainer(service);
    final controller = container.read(executionControllerProvider.notifier);

    await controller.sendRawCommand('DELAY 100');
    final id = service.startedId!;
    await controller.panicStop();
    final pending = container.read(executionControllerProvider);
    expect(pending.isRunning, isTrue);
    expect(pending.outcome, isNull);
    expect(pending.panicAvailable, isTrue);
    expect(service.cancelledIds, [id]);

    service.panicThrows = false;
    await controller.panicStop();
    expect(container.read(executionControllerProvider).outcome, ExecutionOutcome.stopped);
    expect(service.panicExecutionId, id);
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

  test('a recorded payload keeps a redacted history entry when normal history is off', () async {
    final events = StreamController<Map<String, dynamic>>.broadcast();
    addTearDown(events.close);
    final service = _SilentGadget(events: events);
    final container = await _createContainer(service);
    await container.read(logsControllerProvider.future);
    final saved = Completer<void>();
    final logs = container.listen(logsControllerProvider, (_, next) {
      if (!saved.isCompleted && next.value?.any((log) => log.meta?['hasRecording'] == 'true') == true) {
        saved.complete();
      }
    });
    addTearDown(logs.close);
    final controller = container.read(executionControllerProvider.notifier);
    await controller.runPayload(const Payload(
      id: 'private-payload',
      name: 'Private title',
      description: '',
      script: 'DELAY 2000',
      tags: [],
      parameters: [],
      isBuiltin: false,
    ), {}, recordTimeline: true);
    final id = service.startedId!;
    events.add({
      'type': 'wait', 'executionId': id, 'waitMs': 2000, 'lineNumber': 1,
      'message': 'Private runtime text',
    });
    events.add({'type': 'done', 'executionId': id, 'success': true, 'inputReleased': true});
    await saved.future.timeout(const Duration(seconds: 5));

    final record = (await container.read(runRecordingProvider(id).future))!;
    expect(record.events.map((event) => event.kind), containsAllInOrder([
      RunEventKind.started, RunEventKind.timedWait, RunEventKind.completed,
    ]));
    final history = container.read(logsControllerProvider).requireValue;
    expect(history.single.payloadName, 'Recorded run');
    expect(history.single.payloadId, isNull);
    expect(history.single.message, 'Completed');
  });
}

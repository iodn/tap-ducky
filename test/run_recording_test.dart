import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tap_ducky/data/models/run_recording.dart';
import 'package:tap_ducky/state/controllers/hid_status_controller.dart';
import 'package:tap_ducky/state/controllers/run_observation_controller.dart';

class _Usb extends HidStatusController {
  @override
  HidStatus build() => const HidStatus(
    rootAvailable: true,
    hidSupported: true,
    deviceConnected: true,
    sessionArmed: true,
    gadgetBound: true,
  );

  void unplug() => state = state.copyWith(deviceConnected: false);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'only opt-in runs are retained and the recording omits private event fields',
    () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [hidStatusControllerProvider.overrideWith(_Usb.new)],
      );
      addTearDown(container.dispose);
      final observer = container.read(runObservationProvider.notifier);

      observer.start('normal');
      await observer.finish('normal', RunEventKind.completed);
      expect(
        await container.read(runRecordingProvider('normal').future),
        isNull,
      );

      const id = 'private-execution-id';
      observer.start(id, record: true);
      observer.observe(id, {
        'type': 'wait',
        'waitKind': 'condition',
        'lineNumber': 7,
        'waitMs': 3000,
        'message': 'private text or parameter',
        'serial': 'private-device-serial',
      });
      final wait = container.read(runObservationProvider)!;
      expect(wait.waitUntil, isNotNull);
      expect(wait.conditionTimeout, isTrue);
      observer.observe(id, {
        'type': 'step',
        'lineNumber': 7,
        'message': 'private script text',
      });
      expect(container.read(runObservationProvider)?.waitUntil, isNull);
      observer.observe(id, {
        'type': 'warning',
        'code': 'KEY_ROLLOVER',
        'message': 'private keys',
      });
      (container.read(hidStatusControllerProvider.notifier) as _Usb).unplug();
      observer.stopRequested(id);
      await observer.finish(id, RunEventKind.stopped, releaseUnconfirmed: true);

      final recording = (await container.read(
        runRecordingProvider(id).future,
      ))!;
      expect(recording.events.map((event) => event.kind), [
        RunEventKind.started,
        RunEventKind.usbConnected,
        RunEventKind.conditionWait,
        RunEventKind.resumed,
        RunEventKind.keyRollover,
        RunEventKind.usbDisconnected,
        RunEventKind.stopRequested,
        RunEventKind.inputReleaseUnconfirmed,
        RunEventKind.stopped,
      ]);
      final exported = jsonEncode(recording.toShareJson());
      expect(exported, isNot(contains('private')));
      expect(exported, contains('"waitMs":3000'));
      expect(exported, contains('"line":7'));
      await observer.clearRecordings();
      expect(await container.read(runRecordingProvider(id).future), isNull);
    },
  );

  test(
    'long recordings retain the final outcome and count omitted events',
    () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [hidStatusControllerProvider.overrideWith(_Usb.new)],
      );
      addTearDown(container.dispose);
      final observer = container.read(runObservationProvider.notifier);
      observer.start('long', record: true);
      for (var i = 0; i < 200; i++) {
        observer.observe('long', {
          'type': 'wait',
          'waitMs': 1000,
          'lineNumber': i + 1,
        });
      }
      await observer.finish('long', RunEventKind.timedOut);
      final recording = (await container.read(
        runRecordingProvider('long').future,
      ))!;
      expect(recording.events.last.kind, RunEventKind.timedOut);
      expect(recording.omittedEvents, greaterThan(0));
    },
  );

  test('recording availability updates when the oldest run is evicted', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(
      overrides: [hidStatusControllerProvider.overrideWith(_Usb.new)],
    );
    addTearDown(container.dispose);
    final observer = container.read(runObservationProvider.notifier);
    final recordings = container.listen(runRecordingsProvider, (_, _) {});
    addTearDown(recordings.close);
    for (var i = 0; i < 30; i++) {
      observer.start('run-$i', record: true);
      await observer.finish('run-$i', RunEventKind.completed);
    }
    final beforeEviction = await container.read(runRecordingsProvider.future);
    expect(beforeEviction.containsKey('run-0'), isTrue);

    observer.start('run-30', record: true);
    await observer.finish('run-30', RunEventKind.completed);
    final retained = await container.read(runRecordingsProvider.future);
    expect(retained, hasLength(30));
    expect(retained.containsKey('run-0'), isFalse);
    expect(retained.containsKey('run-30'), isTrue);
    expect(await container.read(runRecordingProvider('run-0').future), isNull);
    expect(await container.read(runRecordingProvider('run-30').future), isNotNull);
  });

  test('uses determinate progress only when the current run reports it', () {
    final container = ProviderContainer(
      overrides: [hidStatusControllerProvider.overrideWith(_Usb.new)],
    );
    addTearDown(container.dispose);
    final observer = container.read(runObservationProvider.notifier);
    observer.start('current');
    observer.observe('previous', {
      'type': 'start',
      'progressDeterminate': true,
    });
    expect(container.read(runObservationProvider)?.determinate, isFalse);
    observer.observe('current', {'type': 'phase', 'lineNumber': 11});
    expect(container.read(runObservationProvider)?.line, 11);
    observer.observe('current', {'type': 'start', 'progressDeterminate': true});
    expect(container.read(runObservationProvider)?.determinate, isTrue);
  });
}

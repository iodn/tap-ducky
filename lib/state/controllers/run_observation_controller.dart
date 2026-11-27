import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/run_recording.dart';
import '../providers.dart';
import 'hid_status_controller.dart';

final runObservationProvider =
    NotifierProvider<RunObservationController, RunObservation?>(
      RunObservationController.new,
    );

const _recordingsKey = 'tapducky.runRecordings.v1';

final runRecordingsProvider = FutureProvider.autoDispose((ref) async {
  final storage = await ref.watch(prefsStorageProvider.future);
  final recordings = storage.getJsonList(_recordingsKey).reversed
      .map(RunRecording.fromJson).nonNulls;
  return {for (final recording in recordings) recording.executionId: recording};
});

final runRecordingProvider = FutureProvider.autoDispose
    .family<RunRecording?, String>((ref, id) async {
      final recordings = await ref.watch(runRecordingsProvider.future);
      return recordings[id];
    });

class RunObservation {
  const RunObservation(
    this.id, {
    this.determinate = false,
    this.line,
    this.waitUntil,
    this.conditionTimeout = false,
  });

  final String id;
  final bool determinate;
  final int? line;
  final DateTime? waitUntil;
  final bool conditionTimeout;
}

class RunObservationController extends Notifier<RunObservation?> {
  static const _maxEvents = 120;
  static const _maxRecordings = 30;
  final _clock = Stopwatch();
  final _events = <RunEvent>[];
  RunEventKind? _lastUsb;
  int _omittedEvents = 0;
  bool _record = false;
  Future<void> _writes = Future.value();

  @override
  RunObservation? build() {
    ref.listen(hidStatusControllerProvider, (_, next) => _usb(next));
    return null;
  }

  void start(String id, {bool record = false}) {
    _record = record;
    _clock
      ..reset()
      ..start();
    _events.clear();
    _omittedEvents = 0;
    _lastUsb = null;
    state = RunObservation(id);
    _add(RunEventKind.started);
    _usb(ref.read(hidStatusControllerProvider));
  }

  bool isRecording(String id) => state?.id == id && _record;

  Future<void> clearRecordings() {
    final clear = _writes.then((_) async {
      final storage = await ref.read(prefsStorageProvider.future);
      await storage.remove(_recordingsKey);
      if (ref.mounted) ref.invalidate(runRecordingsProvider);
    });
    _writes = clear.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return clear;
  }

  void observe(String id, Map<String, dynamic> event) {
    final current = state;
    if (current == null || current.id != id) return;
    final nativeLine = event['lineNumber'];
    final line = nativeLine is int && nativeLine > 0
        ? nativeLine
        : current.line;
    switch (event['type']) {
      case 'start':
        state = RunObservation(
          id,
          determinate: event['progressDeterminate'] == true,
        );
      case 'phase':
        if (current.line == line) return;
        state = RunObservation(
          id,
          determinate: current.determinate,
          line: line,
          waitUntil: current.waitUntil,
          conditionTimeout: current.conditionTimeout,
        );
      case 'step':
      case 'button_resumed':
        if (current.waitUntil != null || event['type'] == 'button_resumed') {
          _add(RunEventKind.resumed, line: line);
        }
        if (current.line == line && current.waitUntil == null) return;
        state = RunObservation(
          id,
          determinate: current.determinate,
          line: line,
        );
      case 'warning':
        if (event['code'] == 'KEY_ROLLOVER') {
          _add(RunEventKind.keyRollover, line: line);
        }
      case 'wait':
        final rawMs = event['waitMs'];
        final ms = rawMs is int && rawMs > 0 ? rawMs : null;
        final condition = event['waitKind'] == 'condition';
        final kind = switch ((event['promptId'] is String, condition)) {
          (true, _) => RunEventKind.confirmationWait,
          (_, true) => RunEventKind.conditionWait,
          _ => RunEventKind.timedWait,
        };
        _add(kind, line: line, waitMs: ms);
        state = RunObservation(
          id,
          determinate: current.determinate,
          line: line,
          waitUntil: ms == null
              ? null
              : DateTime.now().add(Duration(milliseconds: ms)),
          conditionTimeout: condition,
        );
    }
  }

  void stopRequested(String id) {
    final current = state;
    if (current == null || current.id != id) return;
    _add(RunEventKind.stopRequested, line: current.line);
    state = RunObservation(id, line: current.line);
  }

  void stopEscalated(String id) {
    final current = state;
    if (current == null || current.id != id) return;
    _add(RunEventKind.stopEscalated, line: current.line);
    state = RunObservation(id, line: current.line);
  }

  void stopFailed(String id) {
    if (state?.id == id) _add(RunEventKind.stopFailed, line: state?.line);
  }

  Future<void> finish(
    String id,
    RunEventKind result, {
    bool releaseUnconfirmed = false,
  }) {
    if (state?.id != id) return Future.value();
    final record = _record;
    if (releaseUnconfirmed)
      _add(RunEventKind.inputReleaseUnconfirmed, terminal: true);
    _add(result, line: state?.line, terminal: true);
    final recording = RunRecording(id, List.of(_events), _omittedEvents);
    _clock.stop();
    _record = false;
    state = null;
    if (!record) return Future.value();

    final write = _writes.then((_) async {
      final storage = await ref.read(prefsStorageProvider.future);
      final saved = storage
          .getJsonList(_recordingsKey)
          .where((item) => item['executionId'] != id)
          .take(_maxRecordings - 1);
      if (!await storage.setJsonList(_recordingsKey, [recording.toJson(), ...saved])) {
        throw StateError('Preferences rejected the run recording');
      }
      if (ref.mounted) ref.invalidate(runRecordingsProvider);
    });
    _writes = write.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return write;
  }

  void _usb(HidStatus status) {
    if (!_record) return;
    final kind =
        !status.gadgetBound || !status.sessionArmed || status.usbRestoring
        ? RunEventKind.usbUnavailable
        : status.deviceConnected
        ? RunEventKind.usbConnected
        : _lastUsb == RunEventKind.usbConnected ||
              _lastUsb == RunEventKind.usbDisconnected
        ? RunEventKind.usbDisconnected
        : RunEventKind.usbWaiting;
    if (kind == _lastUsb) return;
    _lastUsb = kind;
    _add(kind);
  }

  void _add(
    RunEventKind kind, {
    int? line,
    int? waitMs,
    bool terminal = false,
  }) {
    if (!_record) return;
    if (!terminal && _events.length >= _maxEvents) {
      _omittedEvents++;
      return;
    }
    _events.add(
      RunEvent(kind, _clock.elapsedMilliseconds, line: line, waitMs: waitMs),
    );
  }
}

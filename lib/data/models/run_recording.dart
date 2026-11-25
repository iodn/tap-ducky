import 'execution_outcome.dart';

enum RunEventKind {
  started('Run started'),
  usbWaiting('Waiting for USB host'),
  usbConnected('USB host connected'),
  usbDisconnected('USB host disconnected'),
  usbUnavailable('USB session unavailable'),
  timedWait('Timed wait'),
  conditionWait('Waiting for a condition'),
  confirmationWait('Waiting for confirmation'),
  resumed('Run resumed'),
  stopRequested('Stop requested'),
  stopEscalated('Panic Stop requested'),
  stopFailed('Graceful stop could not be requested'),
  keyRollover('A hold was skipped because all keyboard slots were in use'),
  inputReleaseUnconfirmed('Input release could not be confirmed'),
  completed('Completed'),
  stopped('Stopped'),
  timedOut('Timed out'),
  failed('Failed'),
  interrupted('Interrupted');

  const RunEventKind(this.label);
  final String label;

  static RunEventKind forOutcome(ExecutionOutcome outcome) => switch (outcome) {
    ExecutionOutcome.completed => completed,
    ExecutionOutcome.stopped => stopped,
    ExecutionOutcome.timedOut => timedOut,
    ExecutionOutcome.failed => failed,
    ExecutionOutcome.interrupted => interrupted,
  };
}

class RunEvent {
  const RunEvent(this.kind, this.elapsedMs, {this.line, this.waitMs});

  final RunEventKind kind;
  final int elapsedMs;
  final int? line;
  final int? waitMs;

  Map<String, dynamic> toJson() => {
    'event': kind.name,
    'elapsedMs': elapsedMs,
    if (line != null) 'line': line,
    if (waitMs != null) 'waitMs': waitMs,
  };

  static RunEvent? fromJson(Map<String, dynamic> json) {
    final kind = RunEventKind.values
        .where((kind) => kind.name == json['event'])
        .firstOrNull;
    final elapsed = json['elapsedMs'];
    if (kind == null || elapsed is! int || elapsed < 0) return null;
    return RunEvent(
      kind,
      elapsed,
      line: _positiveInt(json['line']),
      waitMs: _positiveInt(json['waitMs']),
    );
  }

  static int? _positiveInt(Object? value) =>
      value is int && value > 0 ? value : null;
}

class RunRecording {
  const RunRecording(this.executionId, this.events, this.omittedEvents);

  final String executionId;
  final List<RunEvent> events;
  final int omittedEvents;

  Map<String, dynamic> toJson() => {
    'executionId': executionId,
    ...toShareJson(),
  };

  Map<String, dynamic> toShareJson() => {
    'format': 'tapducky_run_recording',
    'version': 1,
    'events': events.map((event) => event.toJson()).toList(),
    if (omittedEvents > 0) 'omittedEvents': omittedEvents,
  };

  static RunRecording? fromJson(Map<String, dynamic> json) {
    final id = json['executionId'];
    final rawEvents = json['events'];
    final omitted = json['omittedEvents'];
    if (id is! String || rawEvents is! List) return null;
    return RunRecording(
      id,
      rawEvents
          .whereType<Map<String, dynamic>>()
          .map(RunEvent.fromJson)
          .nonNulls
          .toList(),
      omitted is int && omitted > 0 ? omitted : 0,
    );
  }
}

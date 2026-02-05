import 'dart:async';
import '../models/log_entry.dart';
import '../models/payload.dart';
import 'ducky_script.dart';

class ExecutionUpdate {
  const ExecutionUpdate({
    required this.progress,
    required this.status,
    required this.event,
  });

  final double progress;
  final String status;
  final LogEntry? event;
}

class ExecutionResult {
  const ExecutionResult({required this.success, required this.events});

  final bool success;
  final List<LogEntry> events;
}

class ExecutionService {
  Future<ExecutionResult> run({
    required Payload payload,
    required Map<String, String> params,
    required String deviceLabel,
    required double delayMultiplier,
    required bool randomizeTiming,
    required String executionId,
    required bool enableLogging,
    required StreamController<ExecutionUpdate> updates,
    required bool Function() isCancelled,
  }) async {
    final resolved = DuckyScript.resolvePlaceholders(payload.script, params);
    final steps = DuckyScript.parse(
      resolved,
      delayMultiplier: delayMultiplier,
      randomizeTiming: randomizeTiming,
    );

    final events = <LogEntry>[];
    final started = DateTime.now();

    void emit(double p, String status, {LogEntry? event}) {
      updates.add(ExecutionUpdate(progress: p.clamp(0, 1), status: status, event: event));
    }

    LogEntry mk(String level, String msg, {bool success = true, Map<String, String>? meta}) {
      return LogEntry(
        id: '${executionId}-${events.length + 1}',
        timestamp: DateTime.now(),
        level: level,
        message: msg,
        success: success,
        payloadId: payload.id,
        payloadName: payload.name,
        meta: {
          'device': deviceLabel,
          if (meta != null) ...meta,
        },
      );
    }

    emit(0, 'Starting…', event: enableLogging ? mk('info', 'Execution started') : null);
    if (enableLogging) {
      events.add(mk('info', 'Execution started', meta: {'startedAt': started.toIso8601String()}));
    }

    for (var i = 0; i < steps.length; i++) {
      if (isCancelled()) {
        final ev = mk('warn', 'Execution cancelled by user', success: false);
        if (enableLogging) events.add(ev);
        emit(i / steps.length, 'Cancelled', event: enableLogging ? ev : null);
        return ExecutionResult(success: false, events: events);
      }

      final step = steps[i];
      final p = (i / (steps.isEmpty ? 1 : steps.length));
      emit(p, step.display);

      if (enableLogging && !step.isDelayOnly) {
        final ev = mk('debug', step.display);
        events.add(ev);
        emit(p, step.display, event: ev);
      }

      await Future.delayed(Duration(milliseconds: step.delayMs));
    }

    final finished = DateTime.now();
    final ok = true;

    if (enableLogging) {
      events.add(mk('info', 'Execution completed',
          meta: {'durationMs': '${finished.difference(started).inMilliseconds}'}));
    }

    emit(1, ok ? 'Completed' : 'Failed',
        event: enableLogging ? mk('info', 'Execution completed') : null);
    return ExecutionResult(success: ok, events: events);
  }
}

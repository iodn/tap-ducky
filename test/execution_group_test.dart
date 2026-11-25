import 'package:flutter_test/flutter_test.dart';
import 'package:tap_ducky/data/models/execution_group.dart';
import 'package:tap_ducky/data/models/execution_outcome.dart';
import 'package:tap_ducky/data/models/log_entry.dart';

final _start = DateTime(2026, 11, 26, 8);

LogEntry _event(
  String suffix, {
  int seconds = 0,
  bool success = true,
  String level = 'info',
  Map<String, String> meta = const {},
}) {
  return LogEntry(
    id: 'run-$suffix',
    timestamp: _start.add(Duration(seconds: seconds)),
    level: level,
    message: suffix,
    success: success,
    meta: {'executionId': 'run', ...meta},
  );
}

void main() {
  test('terminal result wins over earlier diagnostic warnings', () {
    final result = ExecutionGroup.fromLogs([
      _event('start'),
      _event('warning', seconds: 1, success: false, level: 'warn'),
      _event(
        'end',
        seconds: 2,
        meta: {'outcome': 'completed', 'durationMs': '1750'},
      ),
      _event('late-diagnostic', seconds: 3),
    ]).single;
    expect(result.outcome, ExecutionOutcome.completed);
    expect(result.warningCount, 1);
    expect(result.duration, const Duration(milliseconds: 1750));
  });

  test('legacy cancelled and timed-out runs remain distinguishable', () {
    final cancelled = _event(
      'end',
      seconds: 2,
      success: false,
      meta: {'cancelled': 'true'},
    );
    expect(
      ExecutionGroup.fromLogs([_event('start'), cancelled]).single.outcome,
      ExecutionOutcome.stopped,
    );
    expect(
      ExecutionGroup.fromLogs([
        _event('start'),
        _event('timeout', seconds: 1, success: false),
        cancelled,
      ]).single.outcome,
      ExecutionOutcome.timedOut,
    );
  });

  test('missing terminal records do not appear completed', () {
    final incomplete = ExecutionGroup.fromLogs([_event('start')]).single;
    expect(incomplete.outcome, ExecutionOutcome.interrupted);
    expect(incomplete.success, isFalse);
  });

  test(
    'history preserves an unconfirmed cleanup warning independently of the outcome',
    () {
      final result = ExecutionGroup.fromLogs([
        _event(
          'end',
          success: false,
          level: 'warn',
          meta: {'outcome': 'stopped', 'inputReleased': 'false'},
        ),
      ]).single;
      expect(result.outcome, ExecutionOutcome.stopped);
      expect(result.inputReleaseUnconfirmed, isTrue);
    },
  );
}

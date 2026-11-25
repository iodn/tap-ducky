import 'execution_outcome.dart';
import 'log_entry.dart';

class ExecutionGroup {
  const ExecutionGroup({
    required this.executionId,
    required this.payloadName,
    required this.startTime,
    required this.endTime,
    required this.outcome,
    required this.inputReleaseUnconfirmed,
    required this.events,
    required this.totalEvents,
    required this.errorCount,
    required this.warningCount,
  });

  final String executionId;
  final String payloadName;
  final DateTime startTime;
  final DateTime endTime;
  final ExecutionOutcome outcome;
  final bool inputReleaseUnconfirmed;
  final List<LogEntry> events;
  final int totalEvents;
  final int errorCount;
  final int warningCount;

  bool get success => outcome == ExecutionOutcome.completed;

  static LogEntry? _terminalEntry(String id, List<LogEntry> events) {
    return events.reversed
        .where(
          (event) => event.id == '$id-end' || event.meta?['finishedAt'] != null,
        )
        .firstOrNull;
  }

  Duration get duration {
    final terminal = _terminalEntry(executionId, events);
    final recorded = int.tryParse(terminal?.meta?['durationMs'] ?? '');
    return recorded != null && recorded >= 0
        ? Duration(milliseconds: recorded)
        : endTime.difference(startTime);
  }

  String get durationFormatted {
    final ms = duration.inMilliseconds;
    if (ms < 1000) return '${ms}ms';
    if (ms < 60000) return '${(ms / 1000).toStringAsFixed(1)}s';
    final minutes = ms ~/ 60000;
    final seconds = (ms % 60000) ~/ 1000;
    return '${minutes}m ${seconds}s';
  }

  static List<ExecutionGroup> fromLogs(List<LogEntry> logs) {
    final groups = <String, List<LogEntry>>{};

    for (final entry in logs) {
      final execId = entry.meta?['executionId'];
      if (execId == null || execId.isEmpty) continue;
      groups.putIfAbsent(execId, () => []).add(entry);
    }

    final result = <ExecutionGroup>[];
    for (final entry in groups.entries) {
      final execId = entry.key;
      final events = entry.value;
      if (events.isEmpty) continue;

      events.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      final first = events.first;
      final last = events.last;
      final terminal = _terminalEntry(execId, events);

      final payloadName =
          events.map((event) => event.payloadName).nonNulls.firstOrNull ??
          'Raw command';

      final startTime =
          DateTime.tryParse(terminal?.meta?['startedAt'] ?? '') ??
          DateTime.tryParse(first.meta?['startedAt'] ?? '') ??
          first.timestamp;

      final endTime =
          DateTime.tryParse(terminal?.meta?['finishedAt'] ?? '') ??
          terminal?.timestamp ??
          last.timestamp;

      final timedOut = events.any((event) => event.id == '$execId-timeout');
      final outcome =
          ExecutionOutcome.fromName(terminal?.meta?['outcome']) ??
          switch (terminal) {
            _ when timedOut => ExecutionOutcome.timedOut,
            null => ExecutionOutcome.interrupted,
            _ when terminal.meta?['cancelled'] == 'true' =>
              ExecutionOutcome.stopped,
            _ when terminal.success => ExecutionOutcome.completed,
            _ => ExecutionOutcome.failed,
          };

      final errorCount = events.where((e) => e.level == 'error').length;
      final warningCount = events.where((e) => e.level == 'warn').length;

      result.add(
        ExecutionGroup(
          executionId: execId,
          payloadName: payloadName,
          startTime: startTime,
          endTime: endTime,
          outcome: outcome,
          inputReleaseUnconfirmed: terminal?.meta?['inputReleased'] == 'false',
          events: events,
          totalEvents: events.length,
          errorCount: errorCount,
          warningCount: warningCount,
        ),
      );
    }

    result.sort((a, b) => b.startTime.compareTo(a.startTime));
    return result;
  }

  static int countRecent(List<ExecutionGroup> groups, Duration window) {
    final cutoff = DateTime.now().subtract(window);
    return groups.where((g) => g.startTime.isAfter(cutoff)).length;
  }
}

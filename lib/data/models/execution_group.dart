import 'log_entry.dart';

class ExecutionGroup {
  const ExecutionGroup({
    required this.executionId,
    required this.payloadName,
    required this.startTime,
    required this.endTime,
    required this.success,
    required this.events,
    required this.totalEvents,
    required this.errorCount,
    required this.warningCount,
  });

  final String executionId;
  final String payloadName;
  final DateTime startTime;
  final DateTime endTime;
  final bool success;
  final List<LogEntry> events;
  final int totalEvents;
  final int errorCount;
  final int warningCount;

  Duration get duration => endTime.difference(startTime);

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

      final payloadName = first.payloadName ?? 'Unknown';

      final startTime = first.meta?['startedAt'] != null
          ? DateTime.parse(first.meta!['startedAt'] as String)
          : first.timestamp;

      final endTime = last.meta?['finishedAt'] != null
          ? DateTime.parse(last.meta!['finishedAt'] as String)
          : last.timestamp;

      final hasErrors = events.any((e) => !e.success || e.level == 'error');
      final success = !hasErrors && last.success;

      final errorCount = events.where((e) => e.level == 'error').length;
      final warningCount = events.where((e) => e.level == 'warn').length;

      result.add(ExecutionGroup(
        executionId: execId,
        payloadName: payloadName,
        startTime: startTime,
        endTime: endTime,
        success: success,
        events: events,
        totalEvents: events.length,
        errorCount: errorCount,
        warningCount: warningCount,
      ));
    }

    result.sort((a, b) => b.startTime.compareTo(a.startTime));
    return result;
  }

  static int countRecent(List<ExecutionGroup> groups, Duration window) {
    final cutoff = DateTime.now().subtract(window);
    return groups.where((g) => g.startTime.isAfter(cutoff)).length;
  }
}

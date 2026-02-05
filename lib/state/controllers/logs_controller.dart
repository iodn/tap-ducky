import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/models/log_entry.dart';
import '../providers.dart';

final logsControllerProvider = AsyncNotifierProvider<LogsController, List<LogEntry>>(
  LogsController.new,
);

class LogsController extends AsyncNotifier<List<LogEntry>> {
  static const _uuid = Uuid();
  StreamSubscription<Map<String, dynamic>>? _logSub;

  @override
  Future<List<LogEntry>> build() async {
    final repo = await ref.watch(logRepositoryProvider.future);
    final items = repo.load();
    _logSub ??= ref.watch(platformGadgetServiceProvider).logsStream.listen(_handleGadgetLog);
    ref.onDispose(() {
      _logSub?.cancel();
      _logSub = null;
    });
    return items;
  }

  LogEntry? byId(String id) {
    final items = state.value ?? const <LogEntry>[];
    for (final e in items) {
      if (e.id == id) return e;
    }
    return null;
  }

  Future<void> append(LogEntry entry) async {
    final repo = await ref.read(logRepositoryProvider.future);
    await repo.append(entry);

    final items = repo.load();
    state = AsyncData(items);
  }

  Future<void> clear() async {
    final repo = await ref.read(logRepositoryProvider.future);
    await repo.clear();
    state = const AsyncData(<LogEntry>[]);
  }

  Future<void> _handleGadgetLog(Map<String, dynamic> evt) async {
    final line = (evt['value'] ?? '').toString();
    if (!line.contains('HOLD ignored (6-key rollover)')) return;

    final entry = LogEntry(
      id: _uuid.v4(),
      timestamp: DateTime.now(),
      level: 'warn',
      message: line,
      success: false,
      meta: const {'source': 'gadget_logs', 'code': 'KEY_ROLLOVER'},
    );
    await append(entry);
  }
}

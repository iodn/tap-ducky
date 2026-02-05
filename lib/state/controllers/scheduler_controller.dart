import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/models/payload.dart';
import '../../data/models/scheduled_task.dart';
import '../../data/services/schedule_rules.dart';
import '../providers.dart';
import 'execution_controller.dart';
import 'hid_status_controller.dart';
import 'payloads_controller.dart';

final schedulerControllerProvider =
    AsyncNotifierProvider<SchedulerController, List<ScheduledTask>>(
  SchedulerController.new,
);

class SchedulerController extends AsyncNotifier<List<ScheduledTask>> {
  static const _uuid = Uuid();

  Timer? _timer;
  bool _initialized = false;
  bool _isTicking = false;

  bool _coldStartAttempted = false;
  DateTime? _lastForegroundFireAt;

  final Map<String, int> _pendingColdStartAttempts = <String, int>{};
  final Map<String, int> _pendingForegroundAttempts = <String, int>{};

  @override
  Future<List<ScheduledTask>> build() async {
    final repo = await ref.watch(schedulerRepositoryProvider.future);
    final items = await Future.sync(repo.loadAll);

    if (!_initialized) {
      _initialized = true;

      ref.onDispose(() {
        _timer?.cancel();
        _timer = null;
      });

      ref.listen<HidStatus>(
        hidStatusControllerProvider,
        (prev, next) {
          final prevArmed = prev?.sessionArmed ?? false;
          if (next.sessionArmed && !prevArmed) {
            _onSessionArmed();
          }
        },
      );

      Timer.run(() async {
        _rearmWith(items);

        await _fireColdStartOnce();
        await _fireForegroundIfDue(source: 'init');

        final hid = ref.read(hidStatusControllerProvider);
        if (hid.sessionArmed) {
          await _onSessionArmed();
        }

        await _tickSafely();
      });
    } else {
      Timer.run(_tickSafely);
    }

    return items;
  }

  Future<void> onAppResumed() async {
    await _fireForegroundIfDue(source: 'resume');
    await _retryPendingIfAny();
    await _tickSafely();
  }

  Future<void> upsert(ScheduledTask task) async {
    final items = [...(state.value ?? const <ScheduledTask>[])];
    final idx = items.indexWhere((t) => t.id == task.id);

    if (idx < 0) {
      items.insert(0, task);
    } else {
      final prev = items[idx];
      var next = task;

      if (_isOneTimeTrigger(next.trigger)) {
        final prevRunAt = prev.runAt?.toLocal();
        final nextRunAt = next.runAt?.toLocal();

        final prevMs = prevRunAt?.millisecondsSinceEpoch;
        final nextMs = nextRunAt?.millisecondsSinceEpoch;

        if (nextMs != null && nextMs != prevMs) {
          next = next.copyWith(lastRunAt: null, enabled: true);
        }
      }

      items[idx] = next;
    }

    await _persist(items);
  }

  Future<String> createNew({
    required String payloadId,
    required String name,
    required String trigger,
    DateTime? runAt,
    String? windowStart,
    String? windowEnd,
    Map<String, String>? params,
  }) async {
    final task = ScheduledTask(
      id: _uuid.v4(),
      payloadId: payloadId,
      name: name,
      enabled: true,
      trigger: trigger,
      runAt: runAt,
      windowStart: windowStart,
      windowEnd: windowEnd,
      params: params ?? const <String, String>{},
      createdAt: DateTime.now(),
    );
    await upsert(task);
    return task.id;
  }

  Future<void> delete(String id) async {
    final items = [...(state.value ?? const <ScheduledTask>[])];
    items.removeWhere((t) => t.id == id);
    await _persist(items);
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final items = [...(state.value ?? const <ScheduledTask>[])];
    final idx = items.indexWhere((t) => t.id == id);
    if (idx < 0) return;

    var next = items[idx].copyWith(enabled: enabled);

    if (enabled && _isOneTimeTrigger(next.trigger)) {
      next = next.copyWith(lastRunAt: null);
    }

    items[idx] = next;
    await _persist(items);
  }

  ScheduledTask? byId(String id) {
    final items = state.value ?? const <ScheduledTask>[];
    for (final t in items) {
      if (t.id == id) return t;
    }
    return null;
  }

  Future<void> _persist(List<ScheduledTask> items) async {
    state = AsyncData(items);
    final repo = await ref.read(schedulerRepositoryProvider.future);
    await repo.saveAll(items);
    _rearmWith(items);
    await _tickSafely();
  }

  void _rearmWith(List<ScheduledTask> items) {
    _timer?.cancel();
    _timer = null;

    final now = DateTime.now();

    bool hasDue = false;
    DateTime? nextAt;

    for (final t in items) {
      if (!t.enabled) continue;
      if (!_isOneTimeTrigger(t.trigger)) continue;

      final runAt = t.runAt?.toLocal();
      if (runAt == null) continue;

      if (t.lastRunAt != null) continue;

      if (!runAt.isAfter(now)) {
        hasDue = true;
        continue;
      }

      if (nextAt == null || runAt.isBefore(nextAt)) {
        nextAt = runAt;
      }
    }

    if (hasDue) {
      _timer = Timer(Duration.zero, _tickSafely);
      return;
    }

    if (nextAt == null) return;

    final delay = nextAt.difference(now);
    _timer = Timer(delay.isNegative ? Duration.zero : delay, _tickSafely);
  }

  Future<void> _tickSafely() async {
    if (_isTicking) return;
    _isTicking = true;
    try {
      await _tickOnce();
    } finally {
      _isTicking = false;
      _rearmWith(state.value ?? const <ScheduledTask>[]);
    }
  }

  Future<void> _tickOnce() async {
    final items = state.value;
    if (items == null || items.isEmpty) return;

    final now = DateTime.now();

    final due = <ScheduledTask>[];
    for (final t in items) {
      if (!t.enabled) continue;
      if (!_isOneTimeTrigger(t.trigger)) continue;

      final runAt = t.runAt?.toLocal();
      if (runAt == null) continue;

      if (t.lastRunAt != null) continue;

      if (runAt.isAfter(now)) continue;

      due.add(t);
    }

    if (due.isEmpty) return;

    due.sort((a, b) {
      final ar = a.runAt?.toLocal().millisecondsSinceEpoch ?? 0;
      final br = b.runAt?.toLocal().millisecondsSinceEpoch ?? 0;
      return ar.compareTo(br);
    });

    final t = due.first;

    if (!isWithinWindow(now, t.windowStart, t.windowEnd)) {
      await _markMissed(t);
      return;
    }

    final ok = await _executeAndConfirm(t, autoDisable: true);
    if (!ok) {
      _timer?.cancel();
      _timer = Timer(const Duration(seconds: 10), _tickSafely);
    }
  }

  Future<void> _fireColdStartOnce() async {
    if (_coldStartAttempted) return;
    _coldStartAttempted = true;

    await _triggerForAny(
      const {'app_cold_start'},
      queueOnFailure: true,
      pending: _pendingColdStartAttempts,
      maxAttempts: 3,
    );
  }

  Future<void> _fireForegroundIfDue({required String source}) async {
    final now = DateTime.now();
    if (_lastForegroundFireAt != null) {
      final elapsed = now.difference(_lastForegroundFireAt!);
      if (elapsed.inMilliseconds < 1200) return;
    }
    _lastForegroundFireAt = now;

    await _triggerForAny(
      const {'app_foreground', 'app_launch'},
      queueOnFailure: true,
      pending: _pendingForegroundAttempts,
      maxAttempts: 3,
    );
  }

  Future<void> _onSessionArmed() async {
    await _triggerForAny(
      const {'device_connected'},
      queueOnFailure: false,
      pending: null,
      maxAttempts: 0,
    );
    await _retryPendingIfAny();
  }

  Future<void> _retryPendingIfAny() async {
    if (_pendingColdStartAttempts.isEmpty && _pendingForegroundAttempts.isEmpty) {
      return;
    }

    await _retryPending(
      triggers: const {'app_cold_start'},
      pending: _pendingColdStartAttempts,
      maxAttempts: 3,
    );

    await _retryPending(
      triggers: const {'app_foreground', 'app_launch'},
      pending: _pendingForegroundAttempts,
      maxAttempts: 3,
    );
  }

  Future<void> _retryPending({
    required Set<String> triggers,
    required Map<String, int> pending,
    required int maxAttempts,
  }) async {
    if (pending.isEmpty) return;

    final items = await _getTasksSnapshot();
    final now = DateTime.now();

    final ids = pending.keys.toList(growable: false);
    for (final id in ids) {
      final attempts = pending[id] ?? 0;
      if (attempts >= maxAttempts) {
        pending.remove(id);
        continue;
      }

      ScheduledTask? t;
      for (final x in items) {
        if (x.id == id) {
          t = x;
          break;
        }
      }

      if (t == null || !t.enabled || !triggers.contains(t.trigger)) {
        pending.remove(id);
        continue;
      }

      if (!isWithinWindow(now, t.windowStart, t.windowEnd)) {
        pending.remove(id);
        continue;
      }

      if (t.lastRunAt != null) {
        final elapsed = now.difference(t.lastRunAt!);
        if (elapsed.inSeconds < 5) {
          pending.remove(id);
          continue;
        }
      }

      final ok = await _executeAndConfirm(t, autoDisable: false);
      if (ok) {
        pending.remove(id);
      } else {
        pending[id] = attempts + 1;
      }
    }
  }

  Future<void> _triggerForAny(
    Set<String> triggers, {
    required bool queueOnFailure,
    required Map<String, int>? pending,
    required int maxAttempts,
  }) async {
    final items = await _getTasksSnapshot();
    if (items.isEmpty) return;

    final now = DateTime.now();

    for (final t in items) {
      if (!t.enabled) continue;
      if (!triggers.contains(t.trigger)) continue;

      if (!isWithinWindow(now, t.windowStart, t.windowEnd)) continue;

      if (t.lastRunAt != null) {
        final elapsed = now.difference(t.lastRunAt!);
        if (elapsed.inSeconds < 5) continue;
      }

      final ok = await _executeAndConfirm(t, autoDisable: false);

      if (!ok && queueOnFailure && pending != null) {
        final current = pending[t.id] ?? 0;
        if (current < maxAttempts) {
          pending[t.id] = current;
        }
      }

      if (ok) break;
    }
  }

  Future<List<ScheduledTask>> _getTasksSnapshot() async {
    final inMem = state.value;
    if (inMem != null) return inMem;
    final repo = await ref.read(schedulerRepositoryProvider.future);
    return repo.loadAll();
  }

  Future<void> _markMissed(ScheduledTask t) async {
    final items = [...(state.value ?? const <ScheduledTask>[])];
    final idx = items.indexWhere((x) => x.id == t.id);
    if (idx < 0) return;

    items[idx] = items[idx].copyWith(
      enabled: false,
      lastRunAt: DateTime.now(),
    );

    state = AsyncData(items);
    final repo = await ref.read(schedulerRepositoryProvider.future);
    await repo.saveAll(items);
  }

  Future<bool> _executeAndConfirm(ScheduledTask t, {required bool autoDisable}) async {
    final execCtrl = ref.read(executionControllerProvider.notifier);
    if (execCtrl.isBusy) return false;

    final payload = await _getPayload(t.payloadId);
    if (payload == null) return false;

    final before = ref.read(executionControllerProvider).executionId;
    await execCtrl.runPayload(payload, t.params);
    final after = ref.read(executionControllerProvider).executionId;

    final started = after != before;
    if (!started) return false;

    final items = [...(state.value ?? const <ScheduledTask>[])];
    final idx = items.indexWhere((x) => x.id == t.id);
    if (idx >= 0) {
      items[idx] = items[idx].copyWith(
        lastRunAt: DateTime.now(),
        enabled: autoDisable ? false : items[idx].enabled,
      );
      state = AsyncData(items);
      final repo = await ref.read(schedulerRepositoryProvider.future);
      await repo.saveAll(items);
    }

    return true;
  }

  Future<Payload?> _getPayload(String id) async {
    final loaded = ref.read(payloadsControllerProvider).value ?? const <Payload>[];
    for (final p in loaded) {
      if (p.id == id) return p;
    }

    final repo = await ref.read(payloadRepositoryProvider.future);
    final items = await repo.loadAll();
    for (final p in items) {
      if (p.id == id) return p;
    }

    return null;
  }

  bool _isOneTimeTrigger(String trigger) {
    return trigger == 'one_time' || trigger == 'date_time' || trigger == 'at_time';
  }
}

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../data/models/log_entry.dart';
import '../../data/models/payload.dart';
import '../../data/services/ducky_script.dart';
import '../../data/models/app_settings.dart';
import '../providers.dart';
import 'advanced_settings_controller.dart';
import 'app_settings_controller.dart';
import 'hid_status_controller.dart';
import 'logs_controller.dart';

class ExecutionState {
  const ExecutionState({
    required this.isRunning,
    required this.progress,
    required this.status,
    required this.executionId,
    this.payloadId,
    this.payloadName,
    this.startedAt,
    this.finishedAt,
    this.success,
    this.tail = const <LogEntry>[],
  });

  final bool isRunning;
  final double progress;
  final String status;
  final String executionId;
  final String? payloadId;
  final String? payloadName;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final bool? success;
  final List<LogEntry> tail;

  ExecutionState copyWith({
    bool? isRunning,
    double? progress,
    String? status,
    String? executionId,
    String? payloadId,
    String? payloadName,
    DateTime? startedAt,
    DateTime? finishedAt,
    bool? success,
    List<LogEntry>? tail,
  }) {
    return ExecutionState(
      isRunning: isRunning ?? this.isRunning,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      executionId: executionId ?? this.executionId,
      payloadId: payloadId ?? this.payloadId,
      payloadName: payloadName ?? this.payloadName,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      success: success ?? this.success,
      tail: tail ?? this.tail,
    );
  }

  static ExecutionState idle() => const ExecutionState(
        isRunning: false,
        progress: 0,
        status: 'Idle',
        executionId: 'none',
      );
}

final executionControllerProvider =
    NotifierProvider<ExecutionController, ExecutionState>(ExecutionController.new);

class ExecutionController extends Notifier<ExecutionState> {
  static const _uuid = Uuid();

  StreamSubscription<Map<String, dynamic>>? _execSub;
  String? _activeExecutionId;
  Timer? _timeoutTimer;

  int _tailSeq = 0;
  DateTime? _lastStepTailAt;
  String? _lastStepTailMsg;

  bool get isBusy => state.isRunning;

  @override
  ExecutionState build() {
    ref.onDispose(() {
      _timeoutTimer?.cancel();
      _timeoutTimer = null;
      _execSub?.cancel();
      _execSub = null;
      _activeExecutionId = null;
    });
    return ExecutionState.idle();
  }

  bool _effectiveRootAvailable(AppSettings settings, HidStatus hid) {
    if (hid.rootAvailable) return true;
    if (kReleaseMode) return false;
    return settings.simulateRootAvailable;
  }

  bool _effectiveHidSupported(AppSettings settings, HidStatus hid) {
    if (hid.hidSupported) return true;
    if (kReleaseMode) return false;
    return settings.simulateHidSupported;
  }

  Future<void> _applySelectedKeyboardLayout() async {
    final adv = ref.read(advancedSettingsControllerProvider).value;
    if (adv == null) return;
    final layoutId = adv.keyboardLayoutBackendId;
    try {
      final service = ref.read(platformGadgetServiceProvider);
      await service.setKeyboardLayout(layoutId);
    } catch (_) {}
  }

  void _pushTail(LogEntry entry) {
    final next = <LogEntry>[...state.tail, entry];
    final trimmed = next.length <= 50 ? next : next.sublist(next.length - 50);
    state = state.copyWith(tail: trimmed);
  }

  LogEntry _mkTail({
    required String executionId,
    required String level,
    required String message,
    required bool success,
    String? payloadId,
    String? payloadName,
    Map<String, String>? meta,
  }) {
    _tailSeq += 1;
    return LogEntry(
      id: '$executionId-tail-$_tailSeq',
      timestamp: DateTime.now(),
      level: level,
      message: message,
      success: success,
      payloadId: payloadId,
      payloadName: payloadName,
      meta: <String, String>{
        'executionId': executionId,
        if (meta != null) ...meta,
      },
    );
  }

  int _estimateTypingOverheadMs(String script, double delayMultiplier) {
    final mult = delayMultiplier <= 0 ? 1.0 : delayMultiplier;
    final lines = script.split(RegExp(r'\r?\n'));
    var chars = 0;
    var commands = 0;

    for (final raw in lines) {
      final t = raw.trim();
      if (t.isEmpty) continue;

      final upper = t.toUpperCase();
      if (upper == 'REM' || upper.startsWith('REM ')) continue;
      if (upper.startsWith('#')) continue;

      if (upper.startsWith('STRINGLN ')) {
        final text = t.substring(8).trimLeft();
        chars += text.length + 1;
        continue;
      }

      if (upper.startsWith('STRING ')) {
        final text = t.substring(6).trimLeft();
        chars += text.length;
        continue;
      }

      if (upper == 'STRING' || upper == 'STRINGLN') {
        continue;
      }

      if (upper.startsWith('DELAY ')) {
        continue;
      }

      commands += 1;
    }

    final perCharMs = (28.0 * mult).round();
    final perCmdMs = (140.0 * mult).round();
    final total = (chars * perCharMs) + (commands * perCmdMs);
    return total < 0 ? 0 : total;
  }

  Duration _estimateTimeoutForScript(String script, double delayMultiplier) {
    final mult = delayMultiplier <= 0 ? 1.0 : delayMultiplier;
    final multForTimeout = mult < 1.0 ? 1.0 : mult;
    List<dynamic> steps = const <dynamic>[];
    try {
      steps = DuckyScript.parse(
        script,
        delayMultiplier: multForTimeout,
        randomizeTiming: false,
      );
    } catch (_) {}

    var ms = 0;
    var activeSteps = 0;

    for (final s in steps) {
      final d = (s.delayMs as int?) ?? 0;
      ms += d;
      final isDelayOnly = (s.isDelayOnly as bool?) ?? false;
      if (!isDelayOnly) activeSteps += 1;
    }

    final perActiveStepMs = (55.0 * multForTimeout).round();
    ms += activeSteps * perActiveStepMs;

    ms += _estimateTypingOverheadMs(script, multForTimeout);

    ms += 90_000;

    final lower = script.toLowerCase();
    var hostBufferMs = 0;
    if (lower.contains('http://') || lower.contains('https://')) hostBufferMs += 120_000;
    if (lower.contains('powershell') ||
        lower.contains('wscript') ||
        lower.contains('cmd ') ||
        lower.contains('curl ') ||
        lower.contains('wget ') ||
        lower.contains('bitsadmin ') ||
        lower.contains('certutil ')) {
      hostBufferMs += 60_000;
    }
    if (lower.contains('taskschd') || lower.contains('schtasks')) hostBufferMs += 60_000;
    if (lower.contains('zipfile') || lower.contains('extracttodirectory')) hostBufferMs += 60_000;
    if (hostBufferMs > 0) {
      final capMs = 10 * 60 * 1000;
      ms += hostBufferMs > capMs ? capMs : hostBufferMs;
    }

    const minMs = 90_000;
    const maxMs = 3 * 60 * 60 * 1000;

    final clamped = ms < minMs ? minMs : (ms > maxMs ? maxMs : ms);
    return Duration(milliseconds: clamped);
  }

  void _startTimeoutTimer({
    required String executionId,
    required Duration timeout,
    required bool enableLogging,
    required String? payloadId,
    required String? payloadName,
  }) {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(timeout, () async {
      if (_activeExecutionId != executionId) return;
      if (!state.isRunning) return;

      final finishedAt = DateTime.now();
      state = state.copyWith(
        isRunning: false,
        status: 'Timed out',
        finishedAt: finishedAt,
        success: false,
      );

      _pushTail(_mkTail(
        executionId: executionId,
        level: 'error',
        message: 'Execution timed out',
        success: false,
        payloadId: payloadId,
        payloadName: payloadName,
        meta: {'timeoutMs': timeout.inMilliseconds.toString()},
      ));

      if (enableLogging) {
        await _emitAndPersist(LogEntry(
          id: '$executionId-timeout',
          timestamp: finishedAt,
          level: 'error',
          message: 'Execution timed out',
          success: false,
          payloadId: payloadId,
          payloadName: payloadName,
          meta: {
            'executionId': executionId,
            'finishedAt': finishedAt.toIso8601String(),
            'timeoutMs': timeout.inMilliseconds.toString(),
          },
        ));
      }

      await _execSub?.cancel();
      _execSub = null;
      _activeExecutionId = null;

      _timeoutTimer?.cancel();
      _timeoutTimer = null;
    });
  }

  Future<void> sendRawCommand(String cmd) async {
    final script = cmd.trim();
    if (script.isEmpty) return;
    if (state.isRunning) return;

    final settings = ref.read(appSettingsControllerProvider).value ?? AppSettings.defaults();
    final enableLogging = settings.enableLogging;
    final delayMultiplier = settings.delayMultiplier;

    final hid = ref.read(hidStatusControllerProvider);
    final rootOk = _effectiveRootAvailable(settings, hid);
    final hidOk = _effectiveHidSupported(settings, hid);

    if (!rootOk || !hidOk) {
      await _emitAndPersist(LogEntry(
        id: _uuid.v4(),
        timestamp: DateTime.now(),
        level: 'error',
        message: 'Cannot execute: root/HID not available.',
        success: false,
        meta: const {'guard': 'root_hid_unavailable'},
      ));
      return;
    }

    if (!hid.sessionArmed) {
      await _emitAndPersist(LogEntry(
        id: _uuid.v4(),
        timestamp: DateTime.now(),
        level: 'warn',
        message: 'HID session not armed. Activate gadget first.',
        success: false,
        meta: const {'guard': 'session_not_armed'},
      ));
      return;
    }

    final executionId = _uuid.v4();
    _activeExecutionId = executionId;

    await _execSub?.cancel();
    _execSub = null;

    _tailSeq = 0;
    _lastStepTailAt = null;
    _lastStepTailMsg = null;

    final startedAt = DateTime.now();
    state = state.copyWith(
      isRunning: true,
      progress: 0,
      status: 'Executing…',
      payloadId: null,
      payloadName: null,
      startedAt: startedAt,
      finishedAt: null,
      success: null,
      executionId: executionId,
      tail: const <LogEntry>[],
    );

    final service = ref.read(platformGadgetServiceProvider);
    var sawAnyEvent = false;

    _execSub = service.execStream.listen((evt) async {
      final id = evt['executionId']?.toString();
      if (id != executionId) return;

      sawAnyEvent = true;

      final type = evt['type']?.toString() ?? '';
      if (type == 'start') {
        final msg = (evt['message']?.toString() ?? '').trim();
        final m = msg.isNotEmpty ? msg : 'Executing…';
        state = state.copyWith(progress: 0, status: m);
        _pushTail(_mkTail(executionId: executionId, level: 'info', message: m, success: true));
        return;
      }

      if (type == 'step') {
        final p = (evt['progress'] as num?)?.toDouble() ?? state.progress;
        final msg = (evt['message']?.toString() ?? '').trim();
        state = state.copyWith(
          progress: p.clamp(0.0, 0.99),
          status: msg.isNotEmpty ? msg : state.status,
        );
        if (msg.isNotEmpty) {
          final now = DateTime.now();
          final allow = _lastStepTailAt == null ||
              now.difference(_lastStepTailAt!).inMilliseconds >= 400 ||
              _lastStepTailMsg != msg;
          if (allow) {
            _lastStepTailAt = now;
            _lastStepTailMsg = msg;
            _pushTail(_mkTail(executionId: executionId, level: 'debug', message: msg, success: true));
          }
        }
        return;
      }

      if (type == 'error') {
        final msg = (evt['message']?.toString() ?? '').trim();
        final m = msg.isNotEmpty ? msg : 'Execution error';
        state = state.copyWith(status: m);
        _pushTail(_mkTail(executionId: executionId, level: 'error', message: m, success: false));
        if (enableLogging) {
          await _emitAndPersist(LogEntry(
            id: '$executionId-error-event',
            timestamp: DateTime.now(),
            level: 'error',
            message: m,
            success: false,
            meta: {'executionId': executionId},
          ));
        }
        return;
      }

      if (type == 'done') {
        final ok = evt['success'] == true;
        final cancelled = evt['cancelled'] == true;
        final finishedAt = DateTime.now();
        state = state.copyWith(
          isRunning: false,
          progress: 1.0,
          status: cancelled ? 'Cancelled' : (ok ? 'Completed' : 'Failed'),
          finishedAt: finishedAt,
          success: ok && !cancelled,
        );

        _pushTail(_mkTail(
          executionId: executionId,
          level: ok && !cancelled ? 'info' : (cancelled ? 'warn' : 'error'),
          message: cancelled ? 'Execution cancelled' : (ok ? 'Execution completed' : 'Execution failed'),
          success: ok && !cancelled,
        ));

        if (enableLogging) {
          await _emitAndPersist(LogEntry(
            id: '$executionId-end',
            timestamp: finishedAt,
            level: 'info',
            message: cancelled ? 'Execution cancelled' : (ok ? 'Execution completed' : 'Execution failed'),
            success: ok && !cancelled,
            meta: {
              'executionId': executionId,
              'startedAt': (state.startedAt ?? startedAt).toIso8601String(),
              'finishedAt': finishedAt.toIso8601String(),
              'durationMs': finishedAt.difference(state.startedAt ?? startedAt).inMilliseconds.toString(),
              'cancelled': cancelled.toString(),
            },
          ));
        }

        await _execSub?.cancel();
        _execSub = null;
        _activeExecutionId = null;

        _timeoutTimer?.cancel();
        _timeoutTimer = null;
        return;
      }
    });

    final timeout = _estimateTimeoutForScript(script, delayMultiplier);
    _startTimeoutTimer(
      executionId: executionId,
      timeout: timeout,
      enableLogging: enableLogging,
      payloadId: null,
      payloadName: null,
    );

    if (enableLogging) {
      await _emitAndPersist(LogEntry(
        id: '$executionId-start',
        timestamp: startedAt,
        level: 'info',
        message: 'Execution started (raw command)',
        success: true,
        meta: {
          'executionId': executionId,
          'startedAt': startedAt.toIso8601String(),
        },
      ));
    }

    final beforeCall = DateTime.now();
    try {
      await _applySelectedKeyboardLayout();
      await service.executeDuckyScript(
        script: script,
        delayMultiplier: delayMultiplier,
        executionId: executionId,
      );

      final callElapsedMs = DateTime.now().difference(beforeCall).inMilliseconds;
      Timer(const Duration(seconds: 2), () async {
        if (callElapsedMs < 800) return;
        if (_activeExecutionId != executionId) return;
        if (!state.isRunning) return;
        if (sawAnyEvent) return;

        final finishedAt = DateTime.now();
        state = state.copyWith(
          isRunning: false,
          progress: 1.0,
          status: 'Completed',
          finishedAt: finishedAt,
          success: true,
        );

        _pushTail(_mkTail(
          executionId: executionId,
          level: 'info',
          message: 'Execution completed',
          success: true,
        ));

        if (enableLogging) {
          await _emitAndPersist(LogEntry(
            id: '$executionId-end',
            timestamp: finishedAt,
            level: 'info',
            message: 'Execution completed',
            success: true,
            meta: {
              'executionId': executionId,
              'startedAt': startedAt.toIso8601String(),
              'finishedAt': finishedAt.toIso8601String(),
              'durationMs': finishedAt.difference(startedAt).inMilliseconds.toString(),
            },
          ));
        }

        await _execSub?.cancel();
        _execSub = null;
        _activeExecutionId = null;

        _timeoutTimer?.cancel();
        _timeoutTimer = null;
      });
    } catch (e) {
      final finishedAt = DateTime.now();
      final s = e.toString();
      final cancelled = s.toLowerCase().contains('cancel');

      state = state.copyWith(
        isRunning: false,
        status: cancelled ? 'Cancelled' : 'Failed',
        finishedAt: finishedAt,
        success: false,
      );

      _pushTail(_mkTail(
        executionId: executionId,
        level: 'error',
        message: 'Execution error: $e',
        success: false,
      ));

      if (enableLogging) {
        await _emitAndPersist(LogEntry(
          id: '$executionId-error',
          timestamp: finishedAt,
          level: 'error',
          message: 'Execution error: $e',
          success: false,
          meta: {'executionId': executionId},
        ));
      }

      await _execSub?.cancel();
      _execSub = null;
      _activeExecutionId = null;

      _timeoutTimer?.cancel();
      _timeoutTimer = null;
    }
  }

  Future<void> runPayload(Payload payload, Map<String, String> params) async {
    if (state.isRunning) return;

    final settings = ref.read(appSettingsControllerProvider).value ?? AppSettings.defaults();
    final enableLogging = settings.enableLogging;

    final hid = ref.read(hidStatusControllerProvider);
    final rootOk = _effectiveRootAvailable(settings, hid);
    final hidOk = _effectiveHidSupported(settings, hid);

    if (!rootOk || !hidOk) {
      await _emitAndPersist(LogEntry(
        id: _uuid.v4(),
        timestamp: DateTime.now(),
        level: 'error',
        message: 'Cannot execute: root/HID not available.',
        success: false,
        payloadId: payload.id,
        payloadName: payload.name,
        meta: const {'guard': 'root_hid_unavailable'},
      ));
      return;
    }

    if (!hid.sessionArmed) {
      await _emitAndPersist(LogEntry(
        id: _uuid.v4(),
        timestamp: DateTime.now(),
        level: 'warn',
        message: 'HID session not armed. Activate gadget first.',
        success: false,
        payloadId: payload.id,
        payloadName: payload.name,
        meta: const {'guard': 'session_not_armed'},
      ));
      return;
    }

    try {
      final prefs = await ref.read(prefsStorageProvider.future);
      await prefs.setString('last_executed_payload_id', payload.id);
    } catch (_) {}

    final executionId = _uuid.v4();
    _activeExecutionId = executionId;

    await _execSub?.cancel();
    _execSub = null;

    _tailSeq = 0;
    _lastStepTailAt = null;
    _lastStepTailMsg = null;

    final startedAt = DateTime.now();
    state = state.copyWith(
      isRunning: true,
      progress: 0,
      status: 'Starting…',
      payloadId: payload.id,
      payloadName: payload.name,
      startedAt: startedAt,
      finishedAt: null,
      success: null,
      executionId: executionId,
      tail: const <LogEntry>[],
    );

    final resolved = DuckyScript.resolvePlaceholders(payload.script, params);
    final service = ref.read(platformGadgetServiceProvider);
    final delayMultiplier = settings.delayMultiplier;

    var sawAnyEvent = false;

    _execSub = service.execStream.listen((evt) async {
      final id = evt['executionId']?.toString();
      if (id != executionId) return;

      sawAnyEvent = true;

      final type = evt['type']?.toString() ?? '';
      if (type == 'start') {
        final msg = (evt['message']?.toString() ?? '').trim();
        final m = msg.isNotEmpty ? msg : 'Executing…';
        state = state.copyWith(progress: 0, status: m);
        _pushTail(_mkTail(
          executionId: executionId,
          level: 'info',
          message: m,
          success: true,
          payloadId: payload.id,
          payloadName: payload.name,
        ));
        return;
      }

      if (type == 'step') {
        final p = (evt['progress'] as num?)?.toDouble() ?? state.progress;
        final msg = (evt['message']?.toString() ?? '').trim();
        state = state.copyWith(
          progress: p.clamp(0.0, 0.99),
          status: msg.isNotEmpty ? msg : state.status,
        );
        if (msg.isNotEmpty) {
          final now = DateTime.now();
          final allow = _lastStepTailAt == null ||
              now.difference(_lastStepTailAt!).inMilliseconds >= 400 ||
              _lastStepTailMsg != msg;
          if (allow) {
            _lastStepTailAt = now;
            _lastStepTailMsg = msg;
            _pushTail(_mkTail(
              executionId: executionId,
              level: 'debug',
              message: msg,
              success: true,
              payloadId: payload.id,
              payloadName: payload.name,
            ));
          }
        }
        return;
      }

      if (type == 'error') {
        final msg = (evt['message']?.toString() ?? '').trim();
        final m = msg.isNotEmpty ? msg : 'Execution error';
        state = state.copyWith(status: m);
        _pushTail(_mkTail(
          executionId: executionId,
          level: 'error',
          message: m,
          success: false,
          payloadId: payload.id,
          payloadName: payload.name,
        ));
        if (enableLogging) {
          await _emitAndPersist(LogEntry(
            id: '$executionId-error-event',
            timestamp: DateTime.now(),
            level: 'error',
            message: m,
            success: false,
            payloadId: payload.id,
            payloadName: payload.name,
            meta: {'executionId': executionId},
          ));
        }
        return;
      }

      if (type == 'done') {
        final ok = evt['success'] == true;
        final cancelled = evt['cancelled'] == true;
        final finishedAt = DateTime.now();
        state = state.copyWith(
          isRunning: false,
          progress: 1.0,
          status: cancelled ? 'Cancelled' : (ok ? 'Completed' : 'Failed'),
          finishedAt: finishedAt,
          success: ok && !cancelled,
        );

        _pushTail(_mkTail(
          executionId: executionId,
          level: ok && !cancelled ? 'info' : (cancelled ? 'warn' : 'error'),
          message: cancelled ? 'Execution cancelled' : (ok ? 'Execution completed' : 'Execution failed'),
          success: ok && !cancelled,
          payloadId: payload.id,
          payloadName: payload.name,
        ));

        if (enableLogging) {
          await _emitAndPersist(LogEntry(
            id: '$executionId-end',
            timestamp: finishedAt,
            level: 'info',
            message: cancelled ? 'Execution cancelled' : (ok ? 'Execution completed' : 'Execution failed'),
            success: ok && !cancelled,
            payloadId: payload.id,
            payloadName: payload.name,
            meta: {
              'executionId': executionId,
              'startedAt': (state.startedAt ?? startedAt).toIso8601String(),
              'finishedAt': finishedAt.toIso8601String(),
              'durationMs': finishedAt.difference(state.startedAt ?? startedAt).inMilliseconds.toString(),
              'cancelled': cancelled.toString(),
            },
          ));
        }

        await _execSub?.cancel();
        _execSub = null;
        _activeExecutionId = null;

        _timeoutTimer?.cancel();
        _timeoutTimer = null;
        return;
      }
    });

    final timeout = _estimateTimeoutForScript(resolved, delayMultiplier);
    _startTimeoutTimer(
      executionId: executionId,
      timeout: timeout,
      enableLogging: enableLogging,
      payloadId: payload.id,
      payloadName: payload.name,
    );

    if (enableLogging) {
      await _emitAndPersist(LogEntry(
        id: '$executionId-start',
        timestamp: startedAt,
        level: 'info',
        message: 'Execution started',
        success: true,
        payloadId: payload.id,
        payloadName: payload.name,
        meta: {
          'executionId': executionId,
          'startedAt': startedAt.toIso8601String(),
        },
      ));
    }

    final beforeCall = DateTime.now();
    try {
      await _applySelectedKeyboardLayout();
      await service.executeDuckyScript(
        script: resolved,
        delayMultiplier: delayMultiplier,
        executionId: executionId,
      );

      final callElapsedMs = DateTime.now().difference(beforeCall).inMilliseconds;
      Timer(const Duration(seconds: 2), () async {
        if (callElapsedMs < 800) return;
        if (_activeExecutionId != executionId) return;
        if (!state.isRunning) return;
        if (sawAnyEvent) return;

        final finishedAt = DateTime.now();
        state = state.copyWith(
          isRunning: false,
          progress: 1.0,
          status: 'Completed',
          finishedAt: finishedAt,
          success: true,
        );

        _pushTail(_mkTail(
          executionId: executionId,
          level: 'info',
          message: 'Execution completed',
          success: true,
          payloadId: payload.id,
          payloadName: payload.name,
        ));

        if (enableLogging) {
          await _emitAndPersist(LogEntry(
            id: '$executionId-end',
            timestamp: finishedAt,
            level: 'info',
            message: 'Execution completed',
            success: true,
            payloadId: payload.id,
            payloadName: payload.name,
            meta: {
              'executionId': executionId,
              'startedAt': startedAt.toIso8601String(),
              'finishedAt': finishedAt.toIso8601String(),
              'durationMs': finishedAt.difference(startedAt).inMilliseconds.toString(),
            },
          ));
        }

        await _execSub?.cancel();
        _execSub = null;
        _activeExecutionId = null;

        _timeoutTimer?.cancel();
        _timeoutTimer = null;
      });
    } catch (e) {
      final finishedAt = DateTime.now();
      final s = e.toString();
      final cancelled = s.toLowerCase().contains('cancel');

      state = state.copyWith(
        isRunning: false,
        status: cancelled ? 'Cancelled' : 'Failed',
        finishedAt: finishedAt,
        success: false,
      );

      _pushTail(_mkTail(
        executionId: executionId,
        level: 'error',
        message: 'Execution error: $e',
        success: false,
        payloadId: payload.id,
        payloadName: payload.name,
      ));

      if (enableLogging) {
        await _emitAndPersist(LogEntry(
          id: '$executionId-error',
          timestamp: finishedAt,
          level: 'error',
          message: 'Execution error: $e',
          success: false,
          payloadId: payload.id,
          payloadName: payload.name,
          meta: {'executionId': executionId},
        ));
      }

      await _execSub?.cancel();
      _execSub = null;
      _activeExecutionId = null;

      _timeoutTimer?.cancel();
      _timeoutTimer = null;
    }
  }

  Future<void> stop() async {
    if (!state.isRunning) return;
    final id = _activeExecutionId;
    if (id == null) return;
    final service = ref.read(platformGadgetServiceProvider);
    state = state.copyWith(status: 'Stopping…');
    await service.cancelExecution(id);
  }

  Future<void> _emitAndPersist(LogEntry entry) async {
    final ctrl = ref.read(logsControllerProvider.notifier);
    await ctrl.append(entry);
  }
}

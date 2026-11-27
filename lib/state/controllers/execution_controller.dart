import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../data/models/execution_outcome.dart';
import '../../data/models/run_recording.dart';
import '../../data/models/log_entry.dart';
import '../../data/models/payload.dart';
import '../../data/services/ducky_script.dart';
import '../../data/models/app_settings.dart';
import '../providers.dart';
import 'advanced_settings_controller.dart';
import 'app_settings_controller.dart';
import 'hid_status_controller.dart';
import 'logs_controller.dart';
import 'run_observation_controller.dart';

enum ScriptIndicator { off, red, green }

class ExecutionState {
  const ExecutionState({
    required this.isRunning,
    required this.progress,
    required this.status,
    required this.executionId,
    this.stopRequested = false,
    this.panicAvailable = false,
    this.buttonPromptId,
    this.scriptButtonAvailable = false,
    this.activityIndicatorEnabled = true,
    this.activityStep = 0,
    this.systemIndicatorEnabled = true,
    this.systemIndicatorStep = 0,
    this.scriptIndicator = ScriptIndicator.off,
    this.payloadId,
    this.payloadName,
    this.startedAt,
    this.finishedAt,
    this.success,
    this.outcome,
    this.inputReleaseUnconfirmed = false,
    this.tail = const <LogEntry>[],
  });

  final bool isRunning;
  final double progress;
  final String status;
  final String executionId;
  final bool stopRequested;
  final bool panicAvailable;
  final String? buttonPromptId;
  final bool scriptButtonAvailable;
  final bool activityIndicatorEnabled;
  final int activityStep;
  final bool systemIndicatorEnabled;
  final int systemIndicatorStep;
  final ScriptIndicator scriptIndicator;
  final String? payloadId;
  final String? payloadName;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final bool? success;
  final ExecutionOutcome? outcome;
  final bool inputReleaseUnconfirmed;
  final List<LogEntry> tail;

  ExecutionState copyWith({
    bool? isRunning,
    double? progress,
    String? status,
    String? executionId,
    bool? stopRequested,
    bool? panicAvailable,
    String? buttonPromptId,
    bool clearButtonPrompt = false,
    bool? scriptButtonAvailable,
    bool? activityIndicatorEnabled,
    int? activityStep,
    bool? systemIndicatorEnabled,
    int? systemIndicatorStep,
    ScriptIndicator? scriptIndicator,
    String? payloadId,
    String? payloadName,
    DateTime? startedAt,
    DateTime? finishedAt,
    bool? success,
    ExecutionOutcome? outcome,
    bool? inputReleaseUnconfirmed,
    List<LogEntry>? tail,
  }) {
    return ExecutionState(
      isRunning: isRunning ?? this.isRunning,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      executionId: executionId ?? this.executionId,
      stopRequested: stopRequested ?? this.stopRequested,
      panicAvailable: panicAvailable ?? this.panicAvailable,
      buttonPromptId: clearButtonPrompt ? null : buttonPromptId ?? this.buttonPromptId,
      scriptButtonAvailable: scriptButtonAvailable ?? this.scriptButtonAvailable,
      activityIndicatorEnabled: activityIndicatorEnabled ?? this.activityIndicatorEnabled,
      activityStep: activityStep ?? this.activityStep,
      systemIndicatorEnabled: systemIndicatorEnabled ?? this.systemIndicatorEnabled,
      systemIndicatorStep: systemIndicatorStep ?? this.systemIndicatorStep,
      scriptIndicator: scriptIndicator ?? this.scriptIndicator,
      payloadId: payloadId ?? this.payloadId,
      payloadName: payloadName ?? this.payloadName,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      success: success ?? this.success,
      outcome: outcome ?? this.outcome,
      inputReleaseUnconfirmed: inputReleaseUnconfirmed ?? this.inputReleaseUnconfirmed,
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
  static const _inputReleaseWarning = 'Input release could not be confirmed.';
  static const Duration _panicGraceDelay = Duration(seconds: 3);
  static const Duration _autoPanicDelay = Duration(seconds: 6);

  StreamSubscription<Map<String, dynamic>>? _execSub;
  String? _activeExecutionId;
  Timer? _timeoutTimer;
  final _timeoutClock = Stopwatch();
  Duration _timeoutBudget = Duration.zero;
  String? _waitingButtonPromptId;
  Timer? _panicTimer;
  Timer? _autoPanicTimer;
  String? _timedOutExecutionId;
  String? _panicStoppingId;
  bool _logCurrentRun = false;

  int _tailSeq = 0;
  DateTime? _lastStepTailAt;
  String? _lastStepTailMsg;

  bool get isBusy => state.isRunning || _activeExecutionId != null || _panicStoppingId != null;

  @override
  ExecutionState build() {
    ref.onDispose(() {
      _timeoutTimer?.cancel();
      _timeoutTimer = null;
      _panicTimer?.cancel();
      _panicTimer = null;
      _autoPanicTimer?.cancel();
      _autoPanicTimer = null;
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
    try {
      final settings = await ref.read(advancedSettingsControllerProvider.future);
      final service = ref.read(platformGadgetServiceProvider);
      await service.setKeyboardLayout(settings.keyboardLayoutBackendId);
    } catch (_) {
      throw StateError('Could not apply the selected keyboard layout.');
    }
  }

  void _pushTail(LogEntry entry) {
    final next = <LogEntry>[...state.tail, entry];
    final trimmed = next.length <= 50 ? next : next.sublist(next.length - 50);
    state = state.copyWith(tail: trimmed);
  }

  Future<void> _finishFromNative(
    String executionId,
    Map<String, dynamic> event,
    DateTime startedAt,
    bool enableLogging, {
    Payload? payload,
  }) async {
    if (_activeExecutionId != executionId) return;
    final cancelled = event['cancelled'] == true;
    final runFinished = event['type'] == 'done' && event['success'] == true && !cancelled;
    final inputReleased = event['inputReleased'];
    final releaseUnconfirmed = inputReleased == false || (runFinished && inputReleased != true);
    final outcome = switch ((_timedOutExecutionId == executionId, cancelled, runFinished && !releaseUnconfirmed)) {
      (true, _, _) => ExecutionOutcome.timedOut,
      (_, true, _) => ExecutionOutcome.stopped,
      (_, _, true) => ExecutionOutcome.completed,
      _ => ExecutionOutcome.failed,
    };
    final ok = outcome == ExecutionOutcome.completed;
    final finishedAt = DateTime.now();
    final durationMs = (event['elapsedMs'] as num?)?.toInt();
    final reason = event['message']?.toString().trim() ?? '';
    final line = event['lineNumber'];
    final location = line is int ? ' at line $line' : '';
    final message = switch (outcome) {
      ExecutionOutcome.timedOut => 'Execution timed out',
      ExecutionOutcome.stopped => 'Execution stopped',
      ExecutionOutcome.completed => 'Execution completed',
      ExecutionOutcome.failed when releaseUnconfirmed && event['type'] == 'done' => 'Script finished',
      _ => 'Execution failed$location${reason.isEmpty ? '' : ': $reason'}',
    };
    final level = ok ? 'info' : outcome == ExecutionOutcome.stopped ? 'warn' : 'error';
    final status = switch (outcome) {
      ExecutionOutcome.failed => message,
      _ => outcome.label,
    };
    final payloadId = payload?.id ?? state.payloadId;
    final payloadName = payload?.name ?? state.payloadName;
    final meta = {
      'executionId': executionId,
      'startedAt': startedAt.toIso8601String(),
      'finishedAt': finishedAt.toIso8601String(),
      'cancelled': cancelled.toString(),
      'outcome': outcome.name,
      if (releaseUnconfirmed) 'inputReleased': 'false'
      else if (inputReleased == true) 'inputReleased': 'true',
      if (durationMs != null) 'durationMs': durationMs.toString(),
      if (event['error_code'] case final String code) 'error_code': code,
      if (line is int) 'lineNumber': line.toString(),
      if (event['completed'] case final int steps) 'completedSteps': steps.toString(),
    };
    final observation = ref.read(runObservationProvider.notifier);
    final recording = observation.isRecording(executionId);
    final recorded = observation.finish(
      executionId,
      RunEventKind.forOutcome(outcome),
      releaseUnconfirmed: releaseUnconfirmed,
    ).then((_) => recording, onError: (Object _, StackTrace _) => false);

    final subscription = _execSub;
    _execSub = null;
    _activeExecutionId = null;
    _timedOutExecutionId = null;
    _panicStoppingId = null;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _waitingButtonPromptId = null;
    _panicTimer?.cancel();
    _panicTimer = null;
    _autoPanicTimer?.cancel();
    _autoPanicTimer = null;

    state = state.copyWith(
      isRunning: false,
      systemIndicatorStep: state.systemIndicatorStep + 1,
      progress: ok ? 1.0 : state.progress,
      status: releaseUnconfirmed ? '$status. $_inputReleaseWarning' : status,
      finishedAt: finishedAt,
      success: ok,
      outcome: outcome,
      inputReleaseUnconfirmed: releaseUnconfirmed,
      stopRequested: false,
      panicAvailable: releaseUnconfirmed,
      clearButtonPrompt: true,
      scriptButtonAvailable: false,
    );
    final resultMessage = releaseUnconfirmed ? '$message. $_inputReleaseWarning' : message;
    final detail = durationMs == null ? resultMessage : '$resultMessage ($durationMs ms on device)';
    _pushTail(_mkTail(
      executionId: executionId,
      level: level,
      message: detail,
      success: ok,
      payloadId: payloadId,
      payloadName: payloadName,
      meta: meta,
    ));
    await subscription?.cancel();
    final recordingSaved = await recorded;
    if (recording && !recordingSaved) {
      if (ref.mounted && state.executionId == executionId && !state.isRunning) {
        _pushTail(_mkTail(
          executionId: executionId,
          level: 'warn',
          message: 'Could not save the run recording.',
          success: false,
        ));
      }
    }
    if (enableLogging || recordingSaved) {
      final savedMeta = enableLogging ? meta : {
        'executionId': executionId,
        'startedAt': startedAt.toIso8601String(),
        'finishedAt': finishedAt.toIso8601String(),
        'outcome': outcome.name,
        if (releaseUnconfirmed) 'inputReleased': 'false',
      };
      await _emitAndPersist(LogEntry(
        id: '$executionId-end',
        timestamp: finishedAt,
        level: level,
        message: enableLogging ? resultMessage : outcome.label,
        success: ok,
        payloadId: enableLogging ? payloadId : null,
        payloadName: enableLogging ? payloadName : 'Recorded run',
        meta: {...savedMeta, if (recordingSaved) 'hasRecording': 'true'},
      ));
    }
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
    bool extendOnly = false,
  }) {
    if (extendOnly && _timeoutTimer?.isActive == true &&
        timeout <= _timeoutBudget - _timeoutClock.elapsed) return;
    _timeoutTimer?.cancel();
    _timeoutBudget = timeout;
    _timeoutClock
      ..reset()
      ..start();
    _timeoutTimer = Timer(timeout, () async {
      if (_activeExecutionId != executionId) return;
      if (!state.isRunning || state.stopRequested) return;

      final timedOutAt = DateTime.now();
      _timedOutExecutionId = executionId;
      unawaited(_requestStop('Timed out. Stopping…'));

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
          timestamp: timedOutAt,
          level: 'error',
          message: 'Execution timed out',
          success: false,
          payloadId: payloadId,
          payloadName: payloadName,
          meta: {
            'executionId': executionId,
            'timeoutMs': timeout.inMilliseconds.toString(),
          },
        ));
      }
    });
  }

  void _noteNativeWait(
    String executionId,
    Map<String, dynamic> event,
    bool enableLogging, {
    Payload? payload,
  }) {
    if (_activeExecutionId != executionId || state.stopRequested) return;
    final waitMs = event['waitMs'];
    final timed = waitMs is int && waitMs > 0;
    final promptId = event['promptId'];
    if (!timed && promptId is! String) return;
    final label = event['message']?.toString() ?? 'Waiting';
    final line = event['lineNumber'];
    state = state.copyWith(
      status: label,
      buttonPromptId: promptId is String ? promptId : null,
      clearButtonPrompt: promptId is! String,
    );
    _pushTail(_mkTail(
      executionId: executionId,
      level: 'info',
      message: '${line is int ? 'Line $line: ' : ''}$label${timed ? ' (up to $waitMs ms)' : ''}',
      success: true,
      payloadId: payload?.id,
      payloadName: payload?.name,
    ));
    if (!timed) {
      _waitingButtonPromptId = promptId as String;
      _timeoutTimer?.cancel();
      _timeoutTimer = null;
      _timeoutClock.stop();
      return;
    }
    _startTimeoutTimer(
      executionId: executionId,
      timeout: Duration(milliseconds: waitMs, seconds: 90),
      enableLogging: enableLogging,
      payloadId: payload?.id,
      payloadName: payload?.name,
      extendOnly: true,
    );
  }

  void _resumeAfterButton(
    String executionId,
    Object? promptId,
    bool enableLogging, {
    Payload? payload,
  }) {
    if (_activeExecutionId != executionId || state.stopRequested ||
        _waitingButtonPromptId == null || _waitingButtonPromptId != promptId) return;
    _waitingButtonPromptId = null;
    state = state.copyWith(status: 'Executing…', clearButtonPrompt: true);
    final remaining = _timeoutBudget - _timeoutClock.elapsed;
    _startTimeoutTimer(
      executionId: executionId,
      timeout: remaining.isNegative ? Duration.zero : remaining,
      enableLogging: enableLogging,
      payloadId: payload?.id,
      payloadName: payload?.name,
    );
  }

  void _startPanicGraceTimer(String executionId) {
    _panicTimer?.cancel();
    _panicTimer = Timer(_panicGraceDelay, () {
      if (_activeExecutionId != executionId) return;
      if (!state.isRunning) return;
      if (!state.stopRequested) return;
      state = state.copyWith(panicAvailable: true);
    });
  }

  void _startAutoPanicTimer(String executionId) {
    _autoPanicTimer?.cancel();
    _autoPanicTimer = Timer(_autoPanicDelay, () async {
      if (_activeExecutionId != executionId) return;
      if (!state.isRunning) return;
      if (!state.stopRequested) return;
      await panicStop();
    });
  }

  Future<void> sendRawCommand(String cmd) async {
    final script = cmd.trim();
    if (script.isEmpty) return;
    if (isBusy) return;

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

    if (!hid.sessionArmed || !hid.gadgetBound) {
      await _emitAndPersist(LogEntry(
        id: _uuid.v4(),
        timestamp: DateTime.now(),
        level: 'warn',
        message: hid.sessionArmed
            ? (hid.message ?? 'USB HID interface is still being prepared.')
            : 'HID session not armed. Arm the session first.',
        success: false,
        meta: {'guard': hid.sessionArmed ? 'gadget_not_ready' : 'session_not_armed'},
      ));
      return;
    }

    final executionId = _uuid.v4();
    _activeExecutionId = executionId;
    ref.read(runObservationProvider.notifier).start(executionId);
    _logCurrentRun = enableLogging;

    await _execSub?.cancel();
    _execSub = null;

    _tailSeq = 0;
    _lastStepTailAt = null;
    _lastStepTailMsg = null;

    final startedAt = DateTime.now();
    state = ExecutionState(
      isRunning: true,
      progress: 0,
      status: 'Executing…',
      stopRequested: false,
      panicAvailable: false,
      payloadId: null,
      payloadName: null,
      startedAt: startedAt,
      executionId: executionId,
      tail: const <LogEntry>[],
    );

    final service = ref.read(platformGadgetServiceProvider);

    _execSub = service.execStream.listen((evt) async {
      final id = evt['executionId']?.toString();
      if (id != executionId || _activeExecutionId != executionId) return;
      if (!state.stopRequested) ref.read(runObservationProvider.notifier).observe(executionId, evt);

      final type = evt['type']?.toString() ?? '';
      if (type == 'phase' && !state.stopRequested) {
        if (state.status != 'Running…') state = state.copyWith(status: 'Running…');
        return;
      }
      if (type == 'script_indicator') {
        if (_activeExecutionId == executionId) {
          final indicator = switch (evt['color']) {
            'red' => ScriptIndicator.red,
            'green' => ScriptIndicator.green,
            'off' => ScriptIndicator.off,
            _ => null,
          };
          if (indicator != null) state = state.copyWith(scriptIndicator: indicator);
        }
        return;
      }
      if (type == 'activity_indicator' || type == 'system_indicator') {
        final enabled = evt['enabled'];
        if (_activeExecutionId == executionId && enabled is bool) {
          state = type == 'system_indicator'
              ? state.copyWith(systemIndicatorEnabled: enabled)
              : state.copyWith(activityIndicatorEnabled: enabled);
        }
        return;
      }
      if (type == 'button_available') {
        if (_activeExecutionId == executionId && !state.stopRequested) {
          state = state.copyWith(scriptButtonAvailable: evt['available'] != false);
        }
        return;
      }
      if (type == 'start') {
        if (state.stopRequested) return;
        final msg = (evt['message']?.toString() ?? '').trim();
        final m = msg.isNotEmpty ? msg : 'Executing…';
        state = state.copyWith(progress: 0, status: m, systemIndicatorStep: state.systemIndicatorStep + 1);
        _pushTail(_mkTail(executionId: executionId, level: 'info', message: m, success: true));
        return;
      }

      if (type == 'step') {
        if (state.stopRequested) return;
        final p = (evt['progress'] as num?)?.toDouble() ?? state.progress;
        final msg = (evt['message']?.toString() ?? '').trim();
        state = state.copyWith(
          progress: p.clamp(0.0, 0.99),
          activityStep: state.activityStep + 1,
          clearButtonPrompt: true,
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

      if (type == 'wait') {
        _noteNativeWait(executionId, evt, enableLogging);
      } else if (type == 'button_resumed') {
        _resumeAfterButton(executionId, evt['promptId'], enableLogging);
      } else if (type == 'error' || type == 'done') {
        await _finishFromNative(executionId, evt, startedAt, enableLogging);
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

    try {
      await _applySelectedKeyboardLayout();
      if (_activeExecutionId != executionId) return;
      if (state.stopRequested) {
        await _finishFromNative(executionId, {'type': 'done', 'cancelled': true}, startedAt, enableLogging);
        return;
      }
      await service.executeDuckyScript(
        script: script,
        delayMultiplier: delayMultiplier,
        executionId: executionId,
      );
    } catch (e) {
      if (_activeExecutionId != executionId) return;
      await _finishFromNative(executionId, {
        'type': 'error',
        'message': e.toString(),
        'cancelled': state.stopRequested,
      }, startedAt, enableLogging);
    }
  }

  Future<void> runPayload(Payload payload, Map<String, String> params, {bool recordTimeline = false}) async {
    if (isBusy) return;

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

    if (!hid.sessionArmed || !hid.gadgetBound) {
      await _emitAndPersist(LogEntry(
        id: _uuid.v4(),
        timestamp: DateTime.now(),
        level: 'warn',
        message: hid.sessionArmed
            ? (hid.message ?? 'USB HID interface is still being prepared.')
            : 'HID session not armed. Arm the session first.',
        success: false,
        payloadId: payload.id,
        payloadName: payload.name,
        meta: {'guard': hid.sessionArmed ? 'gadget_not_ready' : 'session_not_armed'},
      ));
      return;
    }

    final executionId = _uuid.v4();
    _activeExecutionId = executionId;
    ref.read(runObservationProvider.notifier).start(executionId, record: recordTimeline);
    _logCurrentRun = enableLogging;

    try {
      final prefs = await ref.read(prefsStorageProvider.future);
      await prefs.setString('last_executed_payload_id', payload.id);
    } catch (_) {}

    await _execSub?.cancel();
    _execSub = null;

    _tailSeq = 0;
    _lastStepTailAt = null;
    _lastStepTailMsg = null;

    final startedAt = DateTime.now();
    state = ExecutionState(
      isRunning: true,
      progress: 0,
      status: 'Starting…',
      stopRequested: false,
      panicAvailable: false,
      payloadId: payload.id,
      payloadName: payload.name,
      startedAt: startedAt,
      executionId: executionId,
      tail: const <LogEntry>[],
    );

    final resolved = DuckyScript.resolvePlaceholders(payload.script, params);
    final service = ref.read(platformGadgetServiceProvider);
    final delayMultiplier = settings.delayMultiplier;


    _execSub = service.execStream.listen((evt) async {
      final id = evt['executionId']?.toString();
      if (id != executionId || _activeExecutionId != executionId) return;
      if (!state.stopRequested) ref.read(runObservationProvider.notifier).observe(executionId, evt);

      final type = evt['type']?.toString() ?? '';
      if (type == 'phase' && !state.stopRequested) {
        if (state.status != 'Running…') state = state.copyWith(status: 'Running…');
        return;
      }
      if (type == 'script_indicator') {
        if (_activeExecutionId == executionId) {
          final indicator = switch (evt['color']) {
            'red' => ScriptIndicator.red,
            'green' => ScriptIndicator.green,
            'off' => ScriptIndicator.off,
            _ => null,
          };
          if (indicator != null) state = state.copyWith(scriptIndicator: indicator);
        }
        return;
      }
      if (type == 'activity_indicator' || type == 'system_indicator') {
        final enabled = evt['enabled'];
        if (_activeExecutionId == executionId && enabled is bool) {
          state = type == 'system_indicator'
              ? state.copyWith(systemIndicatorEnabled: enabled)
              : state.copyWith(activityIndicatorEnabled: enabled);
        }
        return;
      }
      if (type == 'button_available') {
        if (_activeExecutionId == executionId && !state.stopRequested) {
          state = state.copyWith(scriptButtonAvailable: evt['available'] != false);
        }
        return;
      }
      if (type == 'start') {
        if (state.stopRequested) return;
        final msg = (evt['message']?.toString() ?? '').trim();
        final m = msg.isNotEmpty ? msg : 'Executing…';
        state = state.copyWith(progress: 0, status: m, systemIndicatorStep: state.systemIndicatorStep + 1);
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
        if (state.stopRequested) return;
        final p = (evt['progress'] as num?)?.toDouble() ?? state.progress;
        final msg = (evt['message']?.toString() ?? '').trim();
        state = state.copyWith(
          progress: p.clamp(0.0, 0.99),
          activityStep: state.activityStep + 1,
          clearButtonPrompt: true,
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

      if (type == 'wait') {
        _noteNativeWait(executionId, evt, enableLogging, payload: payload);
      } else if (type == 'button_resumed') {
        _resumeAfterButton(executionId, evt['promptId'], enableLogging, payload: payload);
      } else if (type == 'error' || type == 'done') {
        await _finishFromNative(executionId, evt, startedAt, enableLogging, payload: payload);
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

    try {
      await _applySelectedKeyboardLayout();
      if (_activeExecutionId != executionId) return;
      if (state.stopRequested) {
        await _finishFromNative(executionId, {'type': 'done', 'cancelled': true}, startedAt, enableLogging, payload: payload);
        return;
      }
      await service.executeDuckyScript(
        script: resolved,
        delayMultiplier: delayMultiplier,
        executionId: executionId,
      );
    } catch (e) {
      if (_activeExecutionId != executionId) return;
      await _finishFromNative(executionId, {
        'type': 'error',
        'message': e.toString(),
        'cancelled': state.stopRequested,
      }, startedAt, enableLogging, payload: payload);
    }
  }

  Future<void> stop() => _requestStop('Stopping…');

  Future<void> pressScriptButton(String executionId) async {
    if (_activeExecutionId != executionId || state.stopRequested ||
        !state.scriptButtonAvailable || state.buttonPromptId != null) return;
    try {
      await ref.read(platformGadgetServiceProvider).pressScriptButton(executionId);
    } catch (_) {
      if (_activeExecutionId == executionId && !state.stopRequested) {
        state = state.copyWith(status: 'Could not send button press.');
      }
    }
  }

  Future<void> confirmButtonPrompt(String promptId) async {
    final executionId = _activeExecutionId;
    if (executionId == null || state.stopRequested || state.buttonPromptId != promptId) return;
    try {
      final accepted = await ref.read(platformGadgetServiceProvider).confirmButtonPrompt(executionId, promptId);
      if (accepted && _activeExecutionId == executionId && state.buttonPromptId == promptId) {
        state = state.copyWith(clearButtonPrompt: true);
      }
    } catch (_) {
      if (_activeExecutionId == executionId && state.buttonPromptId == promptId) {
        state = state.copyWith(status: 'Could not continue. Try again.');
      }
    }
  }

  Future<void> _requestStop(String status) async {
    if (!state.isRunning || state.stopRequested) return;
    final id = _activeExecutionId;
    if (id == null) return;
    final service = ref.read(platformGadgetServiceProvider);
    ref.read(runObservationProvider.notifier).stopRequested(id);
    state = state.copyWith(
      status: status,
      stopRequested: true,
      panicAvailable: false,
      clearButtonPrompt: true,
    );
    _startPanicGraceTimer(id);
    _startAutoPanicTimer(id);
    try {
      await service.cancelExecution(id);
    } catch (_) {
      if (_activeExecutionId != id || !state.isRunning) return;
      ref.read(runObservationProvider.notifier).stopFailed(id);
      _pushTail(_mkTail(
        executionId: id,
        level: 'warn',
        message: 'Graceful cancellation failed. Panic Stop will run if execution continues.',
        success: false,
      ));
    }
  }

  Future<void> panicStop() async {
    if (!state.isRunning) return;
    final service = ref.read(platformGadgetServiceProvider);
    final execId = _activeExecutionId;
    final startedAt = state.startedAt;
    if (execId == null || startedAt == null || _panicStoppingId == execId) return;
    _panicStoppingId = execId;
    ref.read(runObservationProvider.notifier).stopEscalated(execId);

    state = state.copyWith(
      status: 'Panic stopping…',
      stopRequested: true,
      panicAvailable: false,
    );

    final bool inputReleased;
    try {
      inputReleased = await service.panicStop(executionId: execId);
    } catch (_) {
      if (_activeExecutionId != execId) return;
      _panicStoppingId = null;
      state = state.copyWith(
        status: 'Stop could not be confirmed. Try Panic Stop again.',
        panicAvailable: true,
      );
      try {
        await service.cancelExecution(execId);
      } catch (_) {}
      return;
    }
    await _finishFromNative(
      execId,
      {'type': 'done', 'cancelled': true, 'inputReleased': inputReleased},
      startedAt,
      _logCurrentRun,
    );
  }

  Future<void> retryInputRelease() async {
    if (isBusy || !state.inputReleaseUnconfirmed || !state.panicAvailable) return;
    final id = state.executionId;
    _panicStoppingId = id;
    state = state.copyWith(panicAvailable: false);
    var released = false;
    try {
      released = await ref.read(platformGadgetServiceProvider).panicStop(executionId: id);
    } catch (_) {
      // Keep the release warning and retry action available on transport failure.
    } finally {
      _panicStoppingId = null;
    }
    if (!ref.mounted || state.executionId != id) return;
    const suffix = '. $_inputReleaseWarning';
    final status = state.status;
    state = state.copyWith(
      inputReleaseUnconfirmed: !released,
      panicAvailable: !released,
      status: released && status.endsWith(suffix)
          ? status.substring(0, status.length - suffix.length)
          : status,
    );
  }

  Future<void> _emitAndPersist(LogEntry entry) async {
    final ctrl = ref.read(logsControllerProvider.notifier);
    await ctrl.append(entry);
  }
}

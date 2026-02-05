// lib/data/services/hardware_keys_service.dart
import 'dart:async';

import 'package:flutter/services.dart';

class HardwareKeyEvent {
  HardwareKeyEvent({
    required this.keyCode,
    required this.action,
    required this.eventTimeMs,
    required this.downTimeMs,
    required this.repeatCount,
    required this.isLongPress,
    required this.metaState,
  });

  final int keyCode;
  final int action;
  final int eventTimeMs;
  final int downTimeMs;
  final int repeatCount;
  final bool isLongPress;
  final int metaState;

  bool get isDown => action == 0;
  bool get isUp => action == 1;

  factory HardwareKeyEvent.fromMap(Map<dynamic, dynamic> map) {
    int asInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }

    bool asBool(dynamic v) {
      if (v is bool) return v;
      final s = (v?.toString() ?? '').toLowerCase().trim();
      return s == 'true' || s == '1' || s == 'yes';
    }

    return HardwareKeyEvent(
      keyCode: asInt(map['keyCode']),
      action: asInt(map['action']),
      eventTimeMs: asInt(map['eventTime']),
      downTimeMs: asInt(map['downTime']),
      repeatCount: asInt(map['repeatCount']),
      isLongPress: asBool(map['isLongPress']),
      metaState: asInt(map['metaState']),
    );
  }
}

class HardwareKeysService {
  static const String _channelMethods = 'org.kaijinlab.tap_ducky/gadget';
  static const String _channelLogs = 'org.kaijinlab.tap_ducky/gadget_logs';
  static const String _channelStatus = 'org.kaijinlab.tap_ducky/gadget_status';
  static const String _channelExec = 'org.kaijinlab.tap_ducky/gadget_exec';
  static const String _channelKeys = 'org.kaijinlab.tap_ducky/hardware_keys';

  static const MethodChannel _methods = MethodChannel(_channelMethods);
  static const EventChannel _logsChannel = EventChannel(_channelLogs);
  static const EventChannel _statusChannel = EventChannel(_channelStatus);
  static const EventChannel _execChannel = EventChannel(_channelExec);
  static const EventChannel _keysChannel = EventChannel(_channelKeys);

  late final Stream<dynamic> logs = _logsChannel.receiveBroadcastStream();
  late final Stream<dynamic> status = _statusChannel.receiveBroadcastStream();
  late final Stream<dynamic> exec = _execChannel.receiveBroadcastStream();

  late final Stream<HardwareKeyEvent> events =
      _keysChannel.receiveBroadcastStream().map((dynamic e) {
    if (e is Map) {
      return HardwareKeyEvent.fromMap(e.cast<dynamic, dynamic>());
    }
    if (e is String) {
      return HardwareKeyEvent.fromMap(<dynamic, dynamic>{'keyCode': 0, 'action': 0, 'eventTime': 0, 'downTime': 0, 'repeatCount': 0, 'isLongPress': false, 'metaState': 0});
    }
    return HardwareKeyEvent.fromMap(<dynamic, dynamic>{});
  });

  Future<bool> checkRoot() async {
    final v = await _methods.invokeMethod<dynamic>('checkRoot');
    return v == true;
  }

  Future<bool> checkSupport() async {
    final v = await _methods.invokeMethod<dynamic>('checkSupport');
    return v == true;
  }

  Future<List<String>> listUdcs() async {
    final v = await _methods.invokeMethod<dynamic>('listUdcs');
    if (v is List) return v.map((e) => e.toString()).toList(growable: false);
    return const <String>[];
  }

  Future<Map<String, dynamic>> getStatus() async {
    final v = await _methods.invokeMethod<dynamic>('getStatus');
    if (v is Map) return v.cast<String, dynamic>();
    return const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> getDiagnostics() async {
    final v = await _methods.invokeMethod<dynamic>('getDiagnostics');
    if (v is Map) return v.cast<String, dynamic>();
    return const <String, dynamic>{};
  }

  Future<void> setKeyboardLayout(int layoutId) async {
    await _methods.invokeMethod<dynamic>('setKeyboardLayout', layoutId);
  }

  Future<List<Map<String, dynamic>>> getKeyboardLayouts() async {
    final v = await _methods.invokeMethod<dynamic>('getKeyboardLayouts');
    if (v is List) {
      return v
          .whereType<Map>()
          .map((m) => m.cast<String, dynamic>())
          .toList(growable: false);
    }
    return const <Map<String, dynamic>>[];
  }

  Future<void> activateProfile(Map<String, dynamic> profile) async {
    await _methods.invokeMethod<dynamic>('activateProfile', profile);
  }

  Future<void> deactivate() async {
    await _methods.invokeMethod<dynamic>('deactivate');
  }

  Future<void> panicStop() async {
    await _methods.invokeMethod<dynamic>('panicStop');
  }

  Future<void> retryOpenHidWriters() async {
    await _methods.invokeMethod<dynamic>('retryOpenHidWriters');
  }

  Future<void> cancelExecution({String? executionId}) async {
    await _methods.invokeMethod<dynamic>('cancelExecution', <String, dynamic>{
      'executionId': executionId,
    });
  }

  Future<void> testMouseMove({
    int dx = 8,
    int dy = 0,
    int wheel = 0,
    int buttons = 0,
  }) async {
    await _methods.invokeMethod<dynamic>('testMouseMove', <String, dynamic>{
      'dx': dx,
      'dy': dy,
      'wheel': wheel,
      'buttons': buttons,
    });
  }

  Future<void> testKeyboardKey(String keyLabelOrKey) async {
    await _methods.invokeMethod<dynamic>('testKeyboardKey', <String, dynamic>{
      'label': keyLabelOrKey,
      'key': keyLabelOrKey,
    });
  }

  Future<void> testCtrlAltDel() async {
    await _methods.invokeMethod<dynamic>('testCtrlAltDel');
  }

  Future<void> executeDuckyScript({
    required String script,
    double delayMultiplier = 1.0,
    String? executionId,
  }) async {
    await _methods.invokeMethod<dynamic>('executeDuckyScript', <String, dynamic>{
      'script': script,
      'delayMultiplier': delayMultiplier,
      'executionId': executionId,
    });
  }

  Future<double> getTypingSpeedFactor() async {
    final v = await _methods.invokeMethod<dynamic>('getTypingSpeedFactor');
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 1.0;
  }

  Future<void> setTypingSpeedFactor(double factor) async {
    await _methods.invokeMethod<dynamic>('setTypingSpeedFactor', factor);
  }
}

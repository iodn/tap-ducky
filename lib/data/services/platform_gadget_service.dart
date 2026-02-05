import 'dart:async';
import 'package:flutter/services.dart';
import '../models/app_settings.dart';

class KeyboardLayoutInfo {
  const KeyboardLayoutInfo({required this.id, required this.name});

  final int id;
  final String name;

  String get code {
    final n = name.trim();
    if (n.isEmpty) return '';
    final first = n.split(RegExp(r'[\s(]+')).first;
    return first.trim().toLowerCase();
  }

  static KeyboardLayoutInfo fromMap(Map<String, dynamic> m) {
    final idRaw = m['id'];
    final id = (idRaw is num) ? idRaw.toInt() : int.tryParse(idRaw?.toString() ?? '') ?? 0;
    final name = (m['name'] ?? '').toString();
    return KeyboardLayoutInfo(id: id, name: name);
  }
}

class GadgetProfile {
  const GadgetProfile({
    required this.id,
    required this.name,
    required this.roleType,
    required this.vendorId,
    required this.productId,
    required this.manufacturer,
    required this.product,
    required this.serialNumber,
    required this.maxPowerMa,
  });

  final String id;
  final String name;
  final String roleType;
  final int vendorId;
  final int productId;
  final String manufacturer;
  final String product;
  final String serialNumber;
  final int maxPowerMa;

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'roleType': roleType,
        'manufacturer': manufacturer,
        'product': product,
        'serialNumber': serialNumber,
        'vendorId': vendorId,
        'productId': productId,
        'maxPowerMa': maxPowerMa,
      };

  factory GadgetProfile.keyboard({
    required String id,
    required String name,
    required int vendorId,
    required int productId,
    String manufacturer = 'TapDucky',
    String product = 'TapDucky Keyboard',
    String serialNumber = 'TDK-001',
    int maxPowerMa = 250,
  }) {
    return GadgetProfile(
      id: id,
      name: name,
      roleType: 'keyboard',
      vendorId: vendorId,
      productId: productId,
      manufacturer: manufacturer,
      product: product,
      serialNumber: serialNumber,
      maxPowerMa: maxPowerMa,
    );
  }

  factory GadgetProfile.mouse({
    required String id,
    required String name,
    required int vendorId,
    required int productId,
    String manufacturer = 'TapDucky',
    String product = 'TapDucky Mouse',
    String serialNumber = 'TDM-001',
    int maxPowerMa = 250,
  }) {
    return GadgetProfile(
      id: id,
      name: name,
      roleType: 'mouse',
      vendorId: vendorId,
      productId: productId,
      manufacturer: manufacturer,
      product: product,
      serialNumber: serialNumber,
      maxPowerMa: maxPowerMa,
    );
  }

  factory GadgetProfile.composite({
    required String id,
    required String name,
    required int vendorId,
    required int productId,
    String manufacturer = 'TapDucky',
    String product = 'TapDucky Composite',
    String serialNumber = 'TDC-001',
    int maxPowerMa = 250,
  }) {
    return GadgetProfile(
      id: id,
      name: name,
      roleType: 'composite',
      vendorId: vendorId,
      productId: productId,
      manufacturer: manufacturer,
      product: product,
      serialNumber: serialNumber,
      maxPowerMa: maxPowerMa,
    );
  }
}

class GadgetStatus {
  const GadgetStatus({
    required this.rootAvailable,
    required this.supportAvailable,
    required this.deviceConnected,
    required this.isActive,
    required this.state,
    this.activeProfileId,
    this.message,
    this.udcList = const <String>[],
    this.keyboardWriterReady = false,
    this.mouseWriterReady = false,
    this.udcState,
    this.hostConfigurationRequestCount = 0,
  });

  final bool rootAvailable;
  final bool supportAvailable;
  final bool deviceConnected;
  final bool isActive;
  final String state;
  final String? activeProfileId;
  final String? message;
  final List<String> udcList;
  final bool keyboardWriterReady;
  final bool mouseWriterReady;
  final String? udcState;
  final int hostConfigurationRequestCount;

  Map<String, dynamic> toMap() => {
        'rootAvailable': rootAvailable,
        'supportAvailable': supportAvailable,
        'deviceConnected': deviceConnected,
        'isActive': isActive,
        'state': state,
        'activeProfileId': activeProfileId,
        'message': message,
        'udcList': udcList,
        'keyboardWriterReady': keyboardWriterReady,
        'mouseWriterReady': mouseWriterReady,
        'udcState': udcState,
        'hostConfigurationRequestCount': hostConfigurationRequestCount,
      };

  factory GadgetStatus.fromMap(Map<String, dynamic> m) {
    bool b(String k, {bool d = false}) {
      final v = m[k];
      if (v is bool) return v;
      final s = v?.toString().toLowerCase().trim();
      if (s == 'true' || s == '1' || s == 'yes') return true;
      if (s == 'false' || s == '0' || s == 'no') return false;
      return d;
    }

    int i(String k, {int d = 0}) {
      final v = m[k];
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? d;
    }

    List<String> list(String k) {
      final v = m[k];
      if (v is List) return v.map((e) => e.toString()).toList();
      return const <String>[];
    }

    final rawState = (m['state'] ?? '').toString().trim();
    final normalizedState = rawState.isEmpty ? '' : rawState.toUpperCase();
    final activeFromState = normalizedState == 'ACTIVE' || normalizedState == 'ACTIVATING';
    final hasIsActive = m.containsKey('isActive');
    final isActive = hasIsActive ? b('isActive') : activeFromState;
    final state = normalizedState.isNotEmpty ? normalizedState : (isActive ? 'ACTIVE' : 'IDLE');

    return GadgetStatus(
      rootAvailable: b('rootAvailable'),
      supportAvailable: b('supportAvailable'),
      deviceConnected: b('deviceConnected'),
      isActive: isActive,
      state: state,
      activeProfileId: m['activeProfileId']?.toString(),
      message: m['message']?.toString(),
      udcList: list('udcList'),
      keyboardWriterReady: b('keyboardWriterReady'),
      mouseWriterReady: b('mouseWriterReady'),
      udcState: m['udcState']?.toString(),
      hostConfigurationRequestCount: i('hostConfigurationRequestCount'),
    );
  }
}

class PlatformGadgetService {
  static const MethodChannel _methods = MethodChannel('org.kaijinlab.tap_ducky/gadget');
  static const EventChannel _logsChannel = EventChannel('org.kaijinlab.tap_ducky/gadget_logs');
  static const EventChannel _statusChannel = EventChannel('org.kaijinlab.tap_ducky/gadget_status');
  static const EventChannel _execChannel = EventChannel('org.kaijinlab.tap_ducky/gadget_exec');

  late final Stream<Map<String, dynamic>> logsStream =
      _logsChannel.receiveBroadcastStream().map(_asMap).asBroadcastStream();

  late final Stream<Map<String, dynamic>> statusStream =
      _statusChannel.receiveBroadcastStream().map(_asMap).asBroadcastStream();

  late final Stream<Map<String, dynamic>> execStream =
      _execChannel.receiveBroadcastStream().map(_asMap).asBroadcastStream();

  Future<bool> checkRoot() async {
    final v = await _methods.invokeMethod<dynamic>('checkRoot');
    if (v is bool) return v;
    return v?.toString().toLowerCase() == 'true';
  }

  Future<bool> checkSupport() async {
    final v = await _methods.invokeMethod<dynamic>('checkSupport');
    if (v is bool) return v;
    return v?.toString().toLowerCase() == 'true';
  }

  Future<List<String>> listUdcs() async {
    final v = await _methods.invokeMethod<dynamic>('listUdcs');
    if (v is List) return v.map((e) => e.toString()).toList();
    return const <String>[];
  }

  Future<GadgetStatus> getStatus() async {
    final v = await _methods.invokeMethod<dynamic>('getStatus');
    if (v is Map) {
      final m = _asMap(v);
      return GadgetStatus.fromMap(m);
    }
    return const GadgetStatus(
      rootAvailable: false,
      supportAvailable: false,
      deviceConnected: false,
      isActive: false,
      state: 'IDLE',
    );
  }

  Future<Map<String, dynamic>> getDiagnostics() async {
    final v = await _methods.invokeMethod<dynamic>('getDiagnostics');
    if (v is Map) return _asMap(v);
    return <String, dynamic>{'value': v};
  }

  Future<List<KeyboardLayoutInfo>> getKeyboardLayouts() async {
    final v = await _methods.invokeMethod<dynamic>('getKeyboardLayouts');
    if (v is List) {
      return v.whereType<Map>().map((e) => e.cast<String, dynamic>()).map(KeyboardLayoutInfo.fromMap).toList();
    }
    return const <KeyboardLayoutInfo>[];
  }

  Future<void> setKeyboardLayout(int layoutId) async {
    await _methods.invokeMethod<void>('setKeyboardLayout', layoutId);
  }

  Future<int> resolveKeyboardLayoutId(String codeOrId) async {
    final raw = codeOrId.trim();
    if (raw.isEmpty) return 0;
    final asInt = int.tryParse(raw);
    if (asInt != null) return asInt;

    final code = raw.toLowerCase();
    final layouts = await getKeyboardLayouts();
    if (layouts.isEmpty) return 0;

    for (final l in layouts) {
      if (l.code == code) return l.id;
    }
    for (final l in layouts) {
      final n = l.name.toLowerCase();
      if (n.startsWith(code)) return l.id;
      if (n.contains('($code')) return l.id;
      if (n.contains(' $code ')) return l.id;
    }
    return layouts.first.id;
  }

  Future<void> setKeyboardLayoutByCode(String codeOrId) async {
    final id = await resolveKeyboardLayoutId(codeOrId);
    await setKeyboardLayout(id);
  }

  Future<void> activateProfile(GadgetProfile profile) async {
    await _methods.invokeMethod<void>('activateProfile', profile.toMap());
  }

  Future<void> deactivate() async {
    await _methods.invokeMethod<void>('deactivate');
  }

  Future<void> panicStop() async {
    await _methods.invokeMethod<void>('panicStop');
  }

  Future<void> retryOpenHidWriters() async {
    await _methods.invokeMethod<void>('retryOpenHidWriters');
  }

  Future<void> cancelExecution(String executionId) async {
    final id = executionId.trim();
    final primary = id.isEmpty ? '*' : id;
    await _methods.invokeMethod<void>('cancelExecution', {'executionId': primary});
    if (primary != '*') {
      await _methods.invokeMethod<void>('cancelExecution', {'executionId': '*'});
    }
  }

  Future<void> executeDuckyScript({
    required String script,
    required double delayMultiplier,
    String? executionId,
  }) async {
    await _methods.invokeMethod<void>('executeDuckyScript', {
      'script': script,
      'delayMultiplier': delayMultiplier,
      'executionId': executionId,
    });
  }

  Future<int> estimateDuckyScriptDurationMs({
    required String script,
    required double delayMultiplier,
  }) async {
    final v = await _methods.invokeMethod<dynamic>('estimateDuckyScriptDuration', {
      'script': script,
      'delayMultiplier': delayMultiplier,
    });
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  Future<void> testMouseMove({
    int dx = 8,
    int dy = 0,
    int wheel = 0,
    int buttons = 0,
  }) async {
    await _methods.invokeMethod<void>('testMouseMove', {
      'dx': dx,
      'dy': dy,
      'wheel': wheel,
      'buttons': buttons,
    });
  }

  Future<void> testKeyboardKey(String label) async {
    await _methods.invokeMethod<void>('testKeyboardKey', {'label': label});
  }

  Future<void> testCtrlAltDel() async {
    await _methods.invokeMethod<void>('testCtrlAltDel');
  }

  Future<void> setHidGraceWindowMs(int ms) async {
    await _methods.invokeMethod<void>('setHidGraceWindowMs', {'ms': ms});
  }

  Future<void> setTypingSpeedFactor(double factor) async {
    await _methods.invokeMethod<void>('setTypingSpeedFactor', factor);
  }

  Future<void> setUnicodeFallbackMode(String mode) async {
    await _methods.invokeMethod<void>('setUnicodeFallbackMode', {'mode': mode});
  }

  Future<void> setRiskyFastMode(bool enabled) async {
    await _methods.invokeMethod<void>('setRiskyFastMode', {'enabled': enabled});
  }

  Future<void> setDialShortcutConfig({
    required bool enabled,
    required String mode,
    String? script,
    String? name,
  }) async {
    await _methods.invokeMethod<void>('setDialShortcutConfig', {
      'enabled': enabled,
      'mode': mode,
      'script': script,
      'name': name,
    });
  }

  Future<void> setDialShortcutBindings({
    required List<DialShortcutBinding> bindings,
  }) async {
    await _methods.invokeMethod<void>('setDialShortcutBindings', {
      'bindings': bindings
          .map((b) => {
                'code': b.code,
                'enabled': b.enabled,
                'mode': b.mode,
                'payloadId': b.payloadId,
                'script': b.script,
                'name': b.name,
              })
          .toList(),
    });
  }

  static Map<String, dynamic> _asMap(dynamic event) {
    if (event is Map) {
      final out = <String, dynamic>{};
      event.forEach((k, v) {
        out[k.toString()] = v;
      });
      return out;
    }
    return <String, dynamic>{'value': event};
  }
}

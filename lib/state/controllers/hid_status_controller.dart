import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/platform_gadget_service.dart';
import '../providers.dart';
import 'advanced_settings_controller.dart';

class HidStatus {
  const HidStatus({
    this.isInitializing = false,
    required this.rootAvailable,
    required this.hidSupported,
    required this.deviceConnected,
    required this.sessionArmed,
    this.activeProfileId,
    this.activeProfileType,
    this.message,
    this.udcList = const <String>[],
    this.keyboardWriterReady = false,
    this.mouseWriterReady = false,
    this.udcState,
    this.hostConfigurationRequestCount = 0,
  });

  final bool isInitializing;
  final bool rootAvailable;
  final bool hidSupported;
  final bool deviceConnected;
  final bool sessionArmed;
  final String? activeProfileId;
  final String? activeProfileType;
  final String? message;
  final List<String> udcList;
  final bool keyboardWriterReady;
  final bool mouseWriterReady;
  final String? udcState;
  final int hostConfigurationRequestCount;

  HidStatus copyWith({
    bool? isInitializing,
    bool? rootAvailable,
    bool? hidSupported,
    bool? deviceConnected,
    bool? sessionArmed,
    String? activeProfileId,
    String? activeProfileType,
    String? message,
    List<String>? udcList,
    bool? keyboardWriterReady,
    bool? mouseWriterReady,
    String? udcState,
    int? hostConfigurationRequestCount,
  }) {
    return HidStatus(
      isInitializing: isInitializing ?? this.isInitializing,
      rootAvailable: rootAvailable ?? this.rootAvailable,
      hidSupported: hidSupported ?? this.hidSupported,
      deviceConnected: deviceConnected ?? this.deviceConnected,
      sessionArmed: sessionArmed ?? this.sessionArmed,
      activeProfileId: activeProfileId ?? this.activeProfileId,
      activeProfileType: activeProfileType ?? this.activeProfileType,
      message: message ?? this.message,
      udcList: udcList ?? this.udcList,
      keyboardWriterReady: keyboardWriterReady ?? this.keyboardWriterReady,
      mouseWriterReady: mouseWriterReady ?? this.mouseWriterReady,
      udcState: udcState ?? this.udcState,
      hostConfigurationRequestCount: hostConfigurationRequestCount ?? this.hostConfigurationRequestCount,
    );
  }

  factory HidStatus.fromGadgetStatus(
    GadgetStatus gs,
    String? roleType, {
    bool isInitializing = false,
  }) {
    return HidStatus(
      isInitializing: isInitializing,
      rootAvailable: gs.rootAvailable,
      hidSupported: gs.supportAvailable,
      deviceConnected: gs.deviceConnected,
      sessionArmed: gs.isActive,
      activeProfileId: gs.activeProfileId,
      activeProfileType: roleType,
      message: gs.message,
      udcList: gs.udcList,
      keyboardWriterReady: gs.keyboardWriterReady,
      mouseWriterReady: gs.mouseWriterReady,
      udcState: gs.udcState,
      hostConfigurationRequestCount: gs.hostConfigurationRequestCount,
    );
  }
}

final hidStatusProvider = StreamProvider<HidStatus>((ref) async* {
  final service = ref.watch(platformGadgetServiceProvider);
  final prefs = await ref.watch(prefsStorageProvider.future);

  final roleType = prefs.getString('active_role_type');
  try {
    final initial = await service.getStatus();
    yield HidStatus.fromGadgetStatus(initial, roleType, isInitializing: false);
  } catch (_) {
    yield const HidStatus(
      isInitializing: false,
      rootAvailable: false,
      hidSupported: false,
      deviceConnected: false,
      sessionArmed: false,
    );
  }

  await for (final statusMap in service.statusStream) {
    final gs = GadgetStatus.fromMap(statusMap);
    final currentRole = prefs.getString('active_role_type');

    yield HidStatus.fromGadgetStatus(gs, currentRole);
  }
});

final hidStatusControllerProvider = NotifierProvider<HidStatusController, HidStatus>(
  HidStatusController.new,
);

class HidStatusController extends Notifier<HidStatus> {
  ProviderSubscription<AsyncValue<HidStatus>>? _sub;
  DateTime? _lastConnectedAt;
  int _lastHostConfigCount = 0;
  String? _lastUdcState;

  static const Duration _stickyConnectedTtl = Duration(minutes: 15);

  @override
  HidStatus build() {
    ref.onDispose(() {
      _sub?.close();
    });

    _sub = ref.listen<AsyncValue<HidStatus>>(
      hidStatusProvider,
      (prev, next) {
        next.whenData((status) {
          state = _applyStickyConnection(status);
        });
      },
    );

    final initial = ref.read(hidStatusProvider);
    return initial.when(
      data: (s) {
        final merged = _applyStickyConnection(s);
        return merged;
      },
      loading: () => const HidStatus(
        isInitializing: true,
        rootAvailable: false,
        hidSupported: false,
        deviceConnected: false,
        sessionArmed: false,
      ),
      error: (_, __) => const HidStatus(
        isInitializing: false,
        rootAvailable: false,
        hidSupported: false,
        deviceConnected: false,
        sessionArmed: false,
      ),
    );
  }

  HidStatus _applyStickyConnection(HidStatus next) {
    final now = DateTime.now();

    if (!next.sessionArmed) {
      _lastConnectedAt = null;
      _lastHostConfigCount = next.hostConfigurationRequestCount;
      _lastUdcState = next.udcState;
      return next.copyWith(isInitializing: false);
    }

    final udcState = (next.udcState ?? _lastUdcState ?? '').trim().toLowerCase();
    final udcSaysConfigured = udcState.contains('configured');
    final udcSaysDisconnected = udcState.contains('not attached') ||
        udcState.contains('disconnected') ||
        udcState.contains('unbound') ||
        udcState.contains('disabled') ||
        udcState.contains('not connected');

    if (next.deviceConnected || udcSaysConfigured) {
      _lastConnectedAt = now;
      _lastHostConfigCount = next.hostConfigurationRequestCount;
      _lastUdcState = next.udcState;
      if (next.deviceConnected) return next.copyWith(isInitializing: false);
      return next.copyWith(deviceConnected: true, isInitializing: false);
    }

    final prevWasConnected = state.sessionArmed && state.deviceConnected;
    final lastAt = _lastConnectedAt;
    final hostConfigDroppedToZero = _lastHostConfigCount > 0 && next.hostConfigurationRequestCount == 0;
    final writersStillLookValid = next.keyboardWriterReady || next.mouseWriterReady;
    final allowSticky = prevWasConnected &&
        !udcSaysDisconnected &&
        !hostConfigDroppedToZero &&
        (writersStillLookValid || lastAt != null);

    if (allowSticky && lastAt != null && now.difference(lastAt) <= _stickyConnectedTtl) {
      _lastHostConfigCount = next.hostConfigurationRequestCount;
      _lastUdcState = next.udcState;
      return next.copyWith(deviceConnected: true, isInitializing: false);
    }

    _lastHostConfigCount = next.hostConfigurationRequestCount;
    _lastUdcState = next.udcState;
    return next.copyWith(isInitializing: false);
  }

  Future<void> _setActiveRoleType(String? roleType) async {
    final prefs = await ref.read(prefsStorageProvider.future);
    if (roleType == null || roleType.trim().isEmpty) {
      await prefs.remove('active_role_type');
    } else {
      await prefs.setString('active_role_type', roleType.trim());
    }
  }

  Future<void> activateKeyboard() async {
    final service = ref.read(platformGadgetServiceProvider);
    final advSettings = ref.read(advancedSettingsControllerProvider).value;
    final vid = _parseHexId(advSettings?.defaultVid ?? '0x1D6B', 0x1d6b);
    final pid = _parseHexId(advSettings?.defaultPid ?? '0x0104', 0x0104);

    final profile = GadgetProfile.keyboard(
      id: 'kbd_${DateTime.now().millisecondsSinceEpoch}',
      name: 'TapDucky Keyboard',
      vendorId: vid,
      productId: pid,
    );

    await service.activateProfile(profile);
    await _setActiveRoleType('keyboard');
  }

  Future<void> activateMouse() async {
    final service = ref.read(platformGadgetServiceProvider);
    final advSettings = ref.read(advancedSettingsControllerProvider).value;
    final vid = _parseHexId(advSettings?.defaultVid ?? '0x1D6B', 0x1d6b);
    final pid = _parseHexId(advSettings?.defaultPid ?? '0x0104', 0x0104);

    final profile = GadgetProfile.mouse(
      id: 'mouse_${DateTime.now().millisecondsSinceEpoch}',
      name: 'TapDucky Mouse',
      vendorId: vid,
      productId: pid,
    );

    await service.activateProfile(profile);
    await _setActiveRoleType('mouse');
  }

  Future<void> activateComposite() async {
    final service = ref.read(platformGadgetServiceProvider);
    final advSettings = ref.read(advancedSettingsControllerProvider).value;
    final vid = _parseHexId(advSettings?.defaultVid ?? '0x1D6B', 0x1d6b);
    final pid = _parseHexId(advSettings?.defaultPid ?? '0x0104', 0x0104);

    final profile = GadgetProfile.composite(
      id: 'comp_${DateTime.now().millisecondsSinceEpoch}',
      name: 'TapDucky Composite',
      vendorId: vid,
      productId: pid,
    );

    await service.activateProfile(profile);
    await _setActiveRoleType('composite');
  }

  Future<void> deactivate() async {
    final service = ref.read(platformGadgetServiceProvider);
    await service.deactivate();
    await _setActiveRoleType(null);
  }

  Future<void> panicStop() async {
    final service = ref.read(platformGadgetServiceProvider);
    await service.panicStop();
    await _setActiveRoleType(null);
  }

  Future<void> retryOpenHidWriters() async {
    final service = ref.read(platformGadgetServiceProvider);
    await service.retryOpenHidWriters();
  }

  void toggleSessionArmed() {
    if (state.sessionArmed) {
      deactivate();
    } else {
      activateComposite();
    }
  }

  void toggleDeviceConnected() {
    toggleSessionArmed();
  }

  int _parseHexId(String hex, int fallback) {
    try {
      final trimmed = hex.trim();
      if (trimmed.isEmpty) return fallback;
      final normalized = trimmed.toLowerCase();
      if (normalized.startsWith('0x')) {
        return int.parse(normalized.substring(2), radix: 16);
      } else {
        return int.parse(normalized, radix: 16);
      }
    } catch (_) {
      return fallback;
    }
  }
}

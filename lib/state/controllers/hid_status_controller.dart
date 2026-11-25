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
    this.gadgetBound = false,
    this.prepared = false,
    this.usbRestoring = false,
    this.pcConnected = false,
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
  final bool gadgetBound;
  final bool prepared;
  final bool usbRestoring;
  final bool pcConnected;

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
    bool? gadgetBound,
    bool? prepared,
    bool? usbRestoring,
    bool? pcConnected,
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
      gadgetBound: gadgetBound ?? this.gadgetBound,
      prepared: prepared ?? this.prepared,
      usbRestoring: usbRestoring ?? this.usbRestoring,
      pcConnected: pcConnected ?? this.pcConnected,
    );
  }

  factory HidStatus.fromGadgetStatus(
    GadgetStatus gs, {
    bool isInitializing = false,
  }) {
    return HidStatus(
      isInitializing: isInitializing,
      rootAvailable: gs.rootAvailable,
      hidSupported: gs.supportAvailable,
      deviceConnected: gs.deviceConnected,
      pcConnected: gs.pcConnected ?? gs.deviceConnected,
      sessionArmed: gs.isActive,
      activeProfileId: gs.activeProfileId,
      activeProfileType: gs.activeRoleType,
      message: gs.message,
      udcList: gs.udcList,
      keyboardWriterReady: gs.keyboardWriterReady,
      mouseWriterReady: gs.mouseWriterReady,
      udcState: gs.udcState,
      hostConfigurationRequestCount: gs.hostConfigurationRequestCount,
      gadgetBound: gs.gadgetBound,
      prepared: gs.prepared,
      usbRestoring: gs.state == 'RESTORING',
    );
  }
}

final hidStatusProvider = StreamProvider<HidStatus>((ref) async* {
  final service = ref.watch(platformGadgetServiceProvider);
  try {
    final initial = await service.getStatus();
    yield HidStatus.fromGadgetStatus(initial);
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
    yield HidStatus.fromGadgetStatus(gs);
  }
});

final hidStatusControllerProvider = NotifierProvider<HidStatusController, HidStatus>(
  HidStatusController.new,
);

class HidStatusController extends Notifier<HidStatus> {
  ProviderSubscription<AsyncValue<HidStatus>>? _sub;

  @override
  HidStatus build() {
    ref.onDispose(() {
      _sub?.close();
    });

    _sub = ref.listen<AsyncValue<HidStatus>>(
      hidStatusProvider,
      (prev, next) {
        next.whenData((status) {
          state = status.copyWith(isInitializing: false);
        });
      },
    );

    final initial = ref.read(hidStatusProvider);
    return initial.when(
      data: (s) => s.copyWith(isInitializing: false),
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

  Future<void> activateKeyboard() async {
    final service = ref.read(platformGadgetServiceProvider);
    final advSettings = ref.read(advancedSettingsControllerProvider).value;
    final vid = _parseHexId(advSettings?.defaultVid ?? '0x1D6B', 0x1d6b);
    final pid = _parseHexId(advSettings?.defaultPid ?? '0x0104', 0x0104);
    final preferredUdc = _preferredUdcOrNull(advSettings?.preferredUdc);

    final profile = GadgetProfile.keyboard(
      id: 'kbd_${DateTime.now().millisecondsSinceEpoch}',
      name: 'TapDucky Keyboard',
      vendorId: vid,
      productId: pid,
      preferredUdc: preferredUdc,
    );

    await service.activateProfile(profile);
  }

  Future<void> activateMouse() async {
    final service = ref.read(platformGadgetServiceProvider);
    final advSettings = ref.read(advancedSettingsControllerProvider).value;
    final vid = _parseHexId(advSettings?.defaultVid ?? '0x1D6B', 0x1d6b);
    final pid = _parseHexId(advSettings?.defaultPid ?? '0x0104', 0x0104);
    final preferredUdc = _preferredUdcOrNull(advSettings?.preferredUdc);

    final profile = GadgetProfile.mouse(
      id: 'mouse_${DateTime.now().millisecondsSinceEpoch}',
      name: 'TapDucky Mouse',
      vendorId: vid,
      productId: pid,
      preferredUdc: preferredUdc,
    );

    await service.activateProfile(profile);
  }

  Future<void> activateComposite() async {
    final service = ref.read(platformGadgetServiceProvider);
    final advSettings = ref.read(advancedSettingsControllerProvider).value;
    final vid = _parseHexId(advSettings?.defaultVid ?? '0x1D6B', 0x1d6b);
    final pid = _parseHexId(advSettings?.defaultPid ?? '0x0104', 0x0104);
    final preferredUdc = _preferredUdcOrNull(advSettings?.preferredUdc);

    final profile = GadgetProfile.composite(
      id: 'comp_${DateTime.now().millisecondsSinceEpoch}',
      name: 'TapDucky Composite',
      vendorId: vid,
      productId: pid,
      preferredUdc: preferredUdc,
    );

    await service.activateProfile(profile);
  }

  Future<void> deactivate() async {
    final service = ref.read(platformGadgetServiceProvider);
    await service.deactivate();
  }

  Future<bool> isHostAttached() {
    return ref.read(platformGadgetServiceProvider).isHostAttached();
  }

  Future<void> panicStop() async {
    final service = ref.read(platformGadgetServiceProvider);
    await service.panicStop();
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

  String? _preferredUdcOrNull(String? raw) {
    final v = raw?.trim() ?? '';
    if (v.isEmpty) return null;
    if (v.toLowerCase() == 'auto') return null;
    return v;
  }
}

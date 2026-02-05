import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../app/router.dart';
import '../data/models/payload.dart';
import '../data/services/hardware_keys_service.dart';
import '../state/controllers/advanced_settings_controller.dart';
import '../state/controllers/execution_controller.dart';
import '../state/controllers/hid_status_controller.dart';
import '../state/controllers/payloads_controller.dart';
import '../state/controllers/scheduler_controller.dart';
import '../state/controllers/selection_controller.dart';
import '../state/providers.dart';
import 'task_bar.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _TapState {
  int count = 0;
  int lastUpAtMs = 0;
  Timer? timer;
}

class _AppShellState extends ConsumerState<AppShell> with WidgetsBindingObserver {
  StreamSubscription<HardwareKeyEvent>? _keysSub;
  bool _isForeground = true;

  final Map<int, int> _downAtMs = <int, int>{};
  final Map<int, _TapState> _tap = <int, _TapState>{};

  static const int _multiTapWindowMs = 350;
  static const int _longPressMinMs = 550;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _keysSub = ref.read(hardwareKeysServiceProvider).events.listen((e) {
      if (!_isForeground) return;
      _handleHardwareKeyEvent(e);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _keysSub?.cancel();
    for (final s in _tap.values) {
      s.timer?.cancel();
    }
    _tap.clear();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _isForeground = true;
      ref.read(schedulerControllerProvider.notifier).onAppResumed();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.detached) {
      _isForeground = false;
    }
  }

  void _handleHardwareKeyEvent(HardwareKeyEvent e) {
    final base = _baseForKeyCode(e.keyCode);
    if (base == null) return;

    if (e.isDown) {
      _downAtMs.putIfAbsent(
        e.keyCode,
        () => (e.downTimeMs != 0 ? e.downTimeMs : e.eventTimeMs),
      );
      return;
    }

    if (!e.isUp) return;

    final down = _downAtMs.remove(e.keyCode) ?? (e.downTimeMs != 0 ? e.downTimeMs : e.eventTimeMs);
    final duration = (e.eventTimeMs - down).abs();

    if (duration >= _longPressMinMs) {
      _clearTapState(e.keyCode);
      unawaited(_dispatchGesture('${base}_long_press'));
      return;
    }

    _registerTap(base, e.keyCode, e.eventTimeMs);
  }

  void _registerTap(String base, int keyCode, int upAtMs) {
    final s = _tap.putIfAbsent(keyCode, () => _TapState());
    final last = s.lastUpAtMs;

    if (last != 0 && (upAtMs - last).abs() <= _multiTapWindowMs) {
      s.count += 1;
    } else {
      s.count = 1;
    }

    s.lastUpAtMs = upAtMs;
    s.timer?.cancel();

    if (s.count >= 3) {
      _tap.remove(keyCode)?.timer?.cancel();
      if (!_isForeground) return;
      unawaited(_dispatchGesture('${base}_triple_tap'));
      return;
    }

    s.timer = Timer(const Duration(milliseconds: _multiTapWindowMs), () {
      final current = _tap.remove(keyCode);
      if (current == null) return;
      current.timer?.cancel();
      if (!_isForeground) return;
      if (current.count == 2) {
        unawaited(_dispatchGesture('${base}_double_tap'));
      }
    });
  }

  void _clearTapState(int keyCode) {
    final s = _tap.remove(keyCode);
    s?.timer?.cancel();
  }

  String? _baseForKeyCode(int keyCode) {
    if (keyCode == 24) return 'volume_up';
    if (keyCode == 25) return 'volume_down';
    return null;
  }

  Future<void> _dispatchGesture(String gestureToken) async {
    final settings = ref.read(advancedSettingsControllerProvider).value;
    if (settings == null) return;

    final hotkeys = settings.hotkeys;
    final order = <String>['stop_execution', 'arm_toggle', 'execute_recent', 'execute_selected'];

    for (final action in order) {
      final binding = hotkeys[action] ?? '';
      if (!_bindingMatches(binding, gestureToken)) continue;
      await _executeHotkeyAction(action);
      return;
    }
  }

  bool _bindingMatches(String bindingRaw, String gestureToken) {
    final binding = bindingRaw.trim();
    if (binding.isEmpty || binding == '—') return false;

    final b = binding
        .toLowerCase()
        .replaceAll(RegExp(r'[\(\)\[\]\{\}]'), ' ')
        .replaceAll(RegExp(r'[_\-]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final g = gestureToken.toLowerCase();

    bool hasAll(List<String> tokens) => tokens.every((t) => b.contains(t));
    bool isDouble() => b.contains('double') || b.contains('2x') || b.contains('twice');
    bool isTriple() => b.contains('triple') || b.contains('3x') || b.contains('thrice');
    bool isLong() => b.contains('long') || b.contains('hold') || b.contains('press');

    if (g == 'volume_up_double_tap') return hasAll(['volume', 'up']) && isDouble();
    if (g == 'volume_down_double_tap') return hasAll(['volume', 'down']) && isDouble();
    if (g == 'volume_up_triple_tap') return hasAll(['volume', 'up']) && isTriple();
    if (g == 'volume_down_triple_tap') return hasAll(['volume', 'down']) && isTriple();
    if (g == 'volume_up_long_press') return hasAll(['volume', 'up']) && isLong();
    if (g == 'volume_down_long_press') return hasAll(['volume', 'down']) && isLong();

    return false;
  }

  Future<void> _executeHotkeyAction(String action) async {
    switch (action) {
      case 'arm_toggle':
        ref.read(hidStatusControllerProvider.notifier).toggleSessionArmed();
        return;
      case 'stop_execution':
        await ref.read(executionControllerProvider.notifier).stop();
        return;
      case 'execute_recent':
        await _executeMostRecentPayload();
        return;
      case 'execute_selected':
        await _executeSelectedPayload();
        return;
    }
  }

  Future<bool> _ensureArmed() async {
    final hid = ref.read(hidStatusControllerProvider);
    if (hid.sessionArmed) return true;
    try {
      await ref.read(hidStatusControllerProvider.notifier).activateComposite();
    } catch (_) {}
    return ref.read(hidStatusControllerProvider).sessionArmed;
  }

  Payload? _findPayloadById(List<Payload> payloads, String id) {
    for (final p in payloads) {
      if (p.id == id) return p;
    }
    return null;
  }

  Map<String, String>? _defaultParamsOrNull(Payload payload) {
    final out = <String, String>{};
    for (final p in payload.parameters) {
      final v = p.defaultValue;
      if (p.required && v.trim().isEmpty) return null;
      out[p.key] = v;
    }
    return out;
  }

  Future<void> _executeSelectedPayload() async {
    if (!mounted) return;

    final exec = ref.read(executionControllerProvider);
    if (exec.isRunning) return;

    final payloadsAsync = ref.read(payloadsControllerProvider);
    final payloads = payloadsAsync.value;
    if (payloads == null || payloads.isEmpty) return;

    final selectedId = ref.read(selectedPayloadIdProvider);
    final payload = selectedId != null ? _findPayloadById(payloads, selectedId) : payloads.first;
    if (payload == null) return;

    final params = _defaultParamsOrNull(payload);
    if (params == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selected payload requires parameters. Open Execute to configure and run.'),
          duration: Duration(seconds: 2),
        ),
      );
      context.go(const ExecuteRoute().location);
      return;
    }

    await _ensureArmed();
    await ref.read(executionControllerProvider.notifier).runPayload(payload, params);
  }

  Future<void> _executeMostRecentPayload() async {
    if (!mounted) return;

    final exec = ref.read(executionControllerProvider);
    if (exec.isRunning) return;

    final payloadsAsync = ref.read(payloadsControllerProvider);
    final payloads = payloadsAsync.value;
    if (payloads == null || payloads.isEmpty) return;

    String? lastId;
    try {
      final prefs = await ref.read(prefsStorageProvider.future);
      lastId = prefs.getString('last_executed_payload_id');
    } catch (_) {}

    final selectedId = ref.read(selectedPayloadIdProvider);
    final candidateId = (lastId != null && lastId.trim().isNotEmpty) ? lastId : selectedId;

    Payload? payload;
    if (candidateId != null) {
      payload = _findPayloadById(payloads, candidateId);
    }
    payload ??= payloads.first;

    final params = _defaultParamsOrNull(payload);
    if (params == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Most recent payload requires parameters. Open Execute to configure and run.'),
          duration: Duration(seconds: 2),
        ),
      );
      context.go(const ExecuteRoute().location);
      return;
    }

    await _ensureArmed();
    await ref.read(executionControllerProvider.notifier).runPayload(payload, params);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(schedulerControllerProvider);
    final location = GoRouterState.of(context).uri.toString();
    final index = _tabIndex(location);
    return Scaffold(
      body: widget.child,
      bottomNavigationBar: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const TaskBar(),
            NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (i) {
                switch (i) {
                  case 0:
                    context.go(const DashboardRoute().location);
                    break;
                  case 1:
                    context.go(const PayloadsRoute().location);
                    break;
                  case 2:
                    context.go(const ExecuteRoute().location);
                    break;
                  case 3:
                    context.go(const ScheduleRoute().location);
                    break;
                  case 4:
                    context.go(const SettingsRoute().location);
                    break;
                }
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  selectedIcon: Icon(Icons.dashboard),
                  label: 'Dashboard',
                ),
                NavigationDestination(
                  icon: Icon(Icons.inventory_2_outlined),
                  selectedIcon: Icon(Icons.inventory_2),
                  label: 'Payloads',
                ),
                NavigationDestination(
                  icon: Icon(Icons.play_circle_outline),
                  selectedIcon: Icon(Icons.play_circle),
                  label: 'Execute',
                ),
                NavigationDestination(
                  icon: Icon(Icons.schedule_outlined),
                  selectedIcon: Icon(Icons.schedule),
                  label: 'Schedule',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: 'Settings',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  int _tabIndex(String location) {
    if (location.startsWith(const PayloadsRoute().location)) return 1;
    if (location.startsWith(const ExecuteRoute().location)) return 2;
    if (location.startsWith(const ScheduleRoute().location)) return 3;
    if (location.startsWith(const SettingsRoute().location)) return 4;
    return 0;
  }
}

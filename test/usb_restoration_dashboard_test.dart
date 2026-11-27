import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tap_ducky/app/theme.dart';
import 'package:tap_ducky/data/models/app_settings.dart';
import 'package:tap_ducky/data/models/payload.dart';
import 'package:tap_ducky/data/services/platform_gadget_service.dart';
import 'package:tap_ducky/features/dashboard/dashboard_screen.dart';
import 'package:tap_ducky/state/controllers/app_settings_controller.dart';
import 'package:tap_ducky/state/controllers/payloads_controller.dart';
import 'package:tap_ducky/state/providers.dart';

class _Settings extends AppSettingsController {
  @override
  Future<AppSettings> build() async => AppSettings.defaults();
}

class _Payloads extends PayloadsController {
  @override
  Future<List<Payload>> build() async => const [
    Payload(
      id: 'demo',
      name: 'Demo',
      description: '',
      script: 'REM Demo',
      tags: [],
      parameters: [],
      isBuiltin: false,
    ),
  ];
}

class _Usb extends PlatformGadgetService {
  final _statuses = StreamController<Map<String, dynamic>>.broadcast();
  int restoreRequests = 0;

  Map<String, dynamic> _status(
    String phase, {
    String? message,
    bool root = true,
  }) => {
    'rootAvailable': root,
    'supportAvailable': root,
    'state': phase == 'VERIFIED' || phase == 'FINISHED' ? 'IDLE' : 'RESTORING',
    'usbRestorePhase': phase,
    'message': message,
  };

  @override
  Future<GadgetStatus> getStatus() async =>
      GadgetStatus.fromMap(_status('WAITING_FOR_UNPLUG'));

  @override
  Stream<Map<String, dynamic>> get statusStream => _statuses.stream;

  @override
  Future<void> deactivate() async {
    restoreRequests++;
    update('RESTORING');
  }

  void update(String phase, {String? message, bool root = true}) =>
      _statuses.add(_status(phase, message: message, root: root));

  Future<void> close() => _statuses.close();
}

void main() {
  testWidgets('Dashboard shows restore progress, recovery, and verification', (
    tester,
  ) async {
    final usb = _Usb();
    addTearDown(usb.close);
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          platformGadgetServiceProvider.overrideWithValue(usb),
          appSettingsControllerProvider.overrideWith(_Settings.new),
          payloadsControllerProvider.overrideWith(_Payloads.new),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const DashboardScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Unplug to finish'), findsOneWidget);
    expect(find.text('Arm Session'), findsNothing);
    final recentRun = find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == 'Run',
    );
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(recentRun, 120, scrollable: scrollable);
    expect(tester.widget<IconButton>(recentRun).onPressed, isNull);
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pumpAndSettle();

    usb.update('RESTORING', root: false);
    await tester.pumpAndSettle();
    expect(find.text('USB restoration paused'), findsOneWidget);
    expect(find.text('Restoring original USB settings...'), findsNothing);
    expect(
      find.text('Grant TapDucky root access, then recheck the device.'),
      findsOneWidget,
    );
    final recheck = find.text('Recheck device');
    await Scrollable.ensureVisible(tester.element(recheck), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(recheck.hitTestable());
    await tester.pumpAndSettle();
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('Unplug to finish'), findsOneWidget);

    usb.update('VERIFYING');
    await tester.pumpAndSettle();
    expect(find.text('Verifying original USB settings...'), findsOneWidget);

    usb.update('FAILED', message: 'USB restoration incomplete (exit=25).');
    await tester.pumpAndSettle();
    expect(find.text('Retry restoration'), findsOneWidget);
    expect(find.textContaining('exit=25'), findsNothing);
    final details = find.text('Details');
    await Scrollable.ensureVisible(tester.element(details), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(details.hitTestable());
    await tester.pumpAndSettle();
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      'USB restoration incomplete (exit=25).',
    );
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    final retry = find.text('Retry restoration');
    await Scrollable.ensureVisible(tester.element(retry), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(retry.hitTestable());
    await tester.pumpAndSettle();
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pumpAndSettle();
    expect(usb.restoreRequests, 1);
    expect(find.text('Restoring original USB settings...'), findsOneWidget);

    usb.update('FINISHED');
    await tester.pumpAndSettle();
    expect(find.text('USB restoration finished'), findsOneWidget);
    expect(find.text('Original USB restored'), findsNothing);

    usb.update('VERIFIED');
    await tester.pumpAndSettle();
    expect(find.text('Original USB restored'), findsOneWidget);
    expect(find.text('Arm Session'), findsOneWidget);
    await tester.scrollUntilVisible(recentRun, 120, scrollable: scrollable);
    expect(tester.widget<IconButton>(recentRun).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });
}

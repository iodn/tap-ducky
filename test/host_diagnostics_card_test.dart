import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tap_ducky/data/models/app_settings.dart';
import 'package:tap_ducky/data/models/host_os.dart';
import 'package:tap_ducky/features/device/widgets/host_diagnostics_card.dart';
import 'package:tap_ducky/state/controllers/app_settings_controller.dart';
import 'package:tap_ducky/state/controllers/hid_status_controller.dart';
import 'package:tap_ducky/state/controllers/host_os_controller.dart';

class _TestSettingsController extends AppSettingsController {
  _TestSettingsController(this.initial);

  final AppSettings initial;

  @override
  Future<AppSettings> build() async => initial;

  @override
  Future<void> setManualHostOs(HostOs? os) async {
    state = AsyncData((state.value ?? initial).copyWith(manualHostOs: os));
  }
}

class _TestHidController extends HidStatusController {
  _TestHidController({required this.connected});

  final bool connected;

  @override
  HidStatus build() => HidStatus(
        rootAvailable: true,
        hidSupported: true,
        deviceConnected: connected,
        sessionArmed: true,
      );
}

Future<void> _pumpCard(
  WidgetTester tester, {
  HostOs? manual,
  bool connected = true,
}) async {
  final settings = AppSettings.defaults().copyWith(manualHostOs: manual);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appSettingsControllerProvider.overrideWith(
          () => _TestSettingsController(settings),
        ),
        hidStatusControllerProvider.overrideWith(
          () => _TestHidController(connected: connected),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: HostDiagnosticsCard(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows host connection separately from host OS', (tester) async {
    await _pumpCard(tester);

    expect(find.text('Host connected'), findsOneWidget);
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('Host OS'), findsOneWidget);
    expect(find.text('Unknown'), findsOneWidget);
    expect(
      find.textContaining('Automatic identification is unavailable'),
      findsOneWidget,
    );
  });

  testWidgets('shows a disconnected host without inventing an OS',
      (tester) async {
    await _pumpCard(tester, connected: false);

    expect(find.text('Disconnected'), findsOneWidget);
    expect(find.text('Unknown'), findsOneWidget);
    expect(
      find.textContaining('No USB host connection observed'),
      findsOneWidget,
    );
  });

  testWidgets('manual selection is labelled as manual', (tester) async {
    await _pumpCard(tester, manual: HostOs.ios);

    expect(find.text('iOS (Manually selected)'), findsOneWidget);
    expect(
      find.textContaining('Automatic identification is unavailable'),
      findsOneWidget,
    );
  });

  testWidgets('selecting an OS updates the diagnostic label', (tester) async {
    await _pumpCard(tester);

    await tester.tap(find.byType(DropdownButton<HostOs>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Windows').last);
    await tester.pumpAndSettle();

    expect(find.text('Windows (Manually selected)'), findsOneWidget);
  });

  testWidgets('an inferred OS is hedged, never presented as detected',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        appSettingsControllerProvider.overrideWith(
          () => _TestSettingsController(AppSettings.defaults()),
        ),
        hidStatusControllerProvider.overrideWith(
          () => _TestHidController(connected: true),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: const Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: HostDiagnosticsCard(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    container
        .read(hostOsControllerProvider.notifier)
        .applySessionOs(HostOs.windows, HostOsSource.inferred);
    await tester.pump();

    expect(find.text('Likely Windows'), findsOneWidget);
  });
}

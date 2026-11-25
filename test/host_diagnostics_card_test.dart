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
  _TestHidController({
    required this.connected,
    this.available = false,
    this.inferred = HostOs.unknown,
    this.detecting = false,
  });

  final bool connected;
  final bool available;
  final HostOs inferred;
  final bool detecting;

  void finishDetection(HostOs os) {
    state = state.copyWith(hostOsDetecting: false, inferredHostOs: os);
  }

  @override
  HidStatus build() => HidStatus(
        rootAvailable: true,
        hidSupported: true,
        pcConnected: connected,
        deviceConnected: connected,
        sessionArmed: true,
        hostOsDetectionAvailable: available,
        inferredHostOs: inferred,
        hostOsDetecting: detecting,
      );
}

Future<_TestHidController> _pumpCard(
  WidgetTester tester, {
  HostOs? manual,
  bool connected = true,
  bool available = false,
  HostOs inferred = HostOs.unknown,
  bool detecting = false,
}) async {
  final settings = AppSettings.defaults().copyWith(manualHostOs: manual);
  final hid = _TestHidController(
    connected: connected,
    available: available,
    inferred: inferred,
    detecting: detecting,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appSettingsControllerProvider.overrideWith(
          () => _TestSettingsController(settings),
        ),
        hidStatusControllerProvider.overrideWith(() => hid),
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
  return hid;
}

void main() {
  testWidgets('shows host connection separately from host OS', (tester) async {
    await _pumpCard(tester);

    expect(find.text('USB connection'), findsOneWidget);
    expect(find.text('Connected · HID ready'), findsOneWidget);
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
  });

  testWidgets('manual selection is labelled as manual', (tester) async {
    await _pumpCard(tester, manual: HostOs.ios);

    expect(find.text('iOS (Manually selected)'), findsOneWidget);
    expect(find.text('Manual selection'), findsOneWidget);
    expect(find.byTooltip('Automatically inferred from USB'), findsNothing);
  });

  testWidgets('selecting an OS updates the diagnostic label', (tester) async {
    await _pumpCard(tester);

    await tester.tap(find.byType(DropdownButton<HostOs>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Windows').last);
    await tester.pumpAndSettle();

    expect(find.text('Windows (Manually selected)'), findsOneWidget);
  });

  testWidgets('renders native inference and keeps the manual fallback visible',
      (tester) async {
    await _pumpCard(
      tester,
      manual: HostOs.chromeos,
      available: true,
      inferred: HostOs.windows,
    );

    expect(find.text('Windows'), findsOneWidget);
    expect(find.text('ChromeOS'), findsOneWidget);
    expect(find.byTooltip('Automatically inferred from USB'), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as AssetImage).assetName,
        'assets/images/host_os/windows.png');
  });

  testWidgets('supported controllers report when the signature is unknown',
      (tester) async {
    await _pumpCard(tester, available: true);
    expect(find.text('No recognizable USB signature for this connection.'),
        findsOneWidget);
  });

  testWidgets('shows detection progress until the name or Unknown is ready',
      (tester) async {
    final hid = await _pumpCard(tester, available: true, detecting: true);
    expect(find.text('Detecting host OS…'), findsOneWidget);
    expect(find.text('Unknown'), findsNothing);

    hid.finishDetection(HostOs.android);
    await tester.pumpAndSettle();
    expect(find.text('Android'), findsOneWidget);
    expect(find.byTooltip('Automatically inferred from USB'), findsOneWidget);
    expect(find.text('Detecting host OS…'), findsNothing);

    hid.finishDetection(HostOs.unknown);
    await tester.pumpAndSettle();
    expect(find.text('Unknown'), findsOneWidget);
  });

  testWidgets('a session inference displays the OS name',
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

    expect(find.text('Windows'), findsOneWidget);
  });
}

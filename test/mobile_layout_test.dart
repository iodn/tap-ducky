import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tap_ducky/app/theme.dart';
import 'package:tap_ducky/data/models/app_settings.dart';
import 'package:tap_ducky/data/models/log_entry.dart';
import 'package:tap_ducky/data/models/payload.dart';
import 'package:tap_ducky/data/models/scheduled_task.dart';
import 'package:tap_ducky/features/dashboard/dashboard_screen.dart';
import 'package:tap_ducky/features/execute/execute_screen.dart';
import 'package:tap_ducky/features/payloads/payloads_screen.dart';
import 'package:tap_ducky/state/controllers/app_settings_controller.dart';
import 'package:tap_ducky/state/controllers/hid_status_controller.dart';
import 'package:tap_ducky/state/controllers/logs_controller.dart';
import 'package:tap_ducky/state/controllers/payloads_controller.dart';
import 'package:tap_ducky/state/controllers/scheduler_controller.dart';
import 'package:tap_ducky/widgets/task_bar.dart';

class _HidStatus extends HidStatusController {
  @override
  HidStatus build() => const HidStatus(
    rootAvailable: true,
    hidSupported: true,
    sessionArmed: false,
    deviceConnected: false,
  );
}

class _Settings extends AppSettingsController {
  @override
  Future<AppSettings> build() async => AppSettings.defaults();
}

class _Payloads extends PayloadsController {
  _Payloads(this.items);
  final List<Payload> items;

  @override
  Future<List<Payload>> build() async => items;
}

class _Schedules extends SchedulerController {
  @override
  Future<List<ScheduledTask>> build() async => [];
}

class _Logs extends LogsController {
  @override
  Future<List<LogEntry>> build() async => [];
}

Future<void> _pumpScreen(
  WidgetTester tester,
  Widget screen, {
  required Size size,
  List<Payload> payloads = const [],
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        hidStatusControllerProvider.overrideWith(_HidStatus.new),
        appSettingsControllerProvider.overrideWith(_Settings.new),
        payloadsControllerProvider.overrideWith(() => _Payloads(payloads)),
        schedulerControllerProvider.overrideWith(_Schedules.new),
        logsControllerProvider.overrideWith(_Logs.new),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: screen,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('task bar grows and keeps actions reachable', (tester) async {
    await _pumpScreen(
      tester,
      const Scaffold(bottomNavigationBar: TaskBar()),
      size: const Size(320, 568),
    );

    await tester.tap(find.text('Ready'));
    await tester.pumpAndSettle();

    expect(find.text('Logs').hitTestable(), findsOneWidget);
    expect(
      tester
          .getSize(
            find
                .ancestor(of: find.text('Logs'), matching: find.byType(InkWell))
                .first,
          )
          .height,
      greaterThanOrEqualTo(44),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty library brings Create into the first viewport', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      const Scaffold(body: PayloadsScreen(), bottomNavigationBar: TaskBar()),
      size: const Size(320, 568),
    );

    final create = find.text('Create Payload');
    expect(create, findsOneWidget);
    expect(tester.getRect(create).bottom, lessThan(490));
    expect(find.text('Import from Clipboard'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('quick actions remain reachable on a short screen', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      const DashboardScreen(),
      size: const Size(844, 390),
    );

    final more = find.widgetWithIcon(IconButton, Icons.more_horiz);
    await tester.scrollUntilVisible(more, 180);
    await Scrollable.ensureVisible(tester.element(more), alignment: 0.15);
    await tester.pumpAndSettle();
    await tester.tap(more);
    await tester.pumpAndSettle();

    final sheet = find.byType(BottomSheet);
    expect(sheet, findsOneWidget);
    final lastAction = find.text('Device Info');
    await tester.scrollUntilVisible(
      lastAction,
      120,
      scrollable: find.descendant(of: sheet, matching: find.byType(Scrollable)),
    );
    await tester.pumpAndSettle();
    expect(lastAction.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('console controls fit at large text size', (tester) async {
    await _pumpScreen(
      tester,
      const ExecuteScreen(),
      size: const Size(320, 568),
      payloads: const [
        Payload(
          id: 'hello',
          name: 'Hello world',
          description: '',
          script: 'STRING hello world',
          tags: [],
          parameters: [],
          isBuiltin: false,
        ),
      ],
    );

    await tester.scrollUntilVisible(find.text('Command'), 200);
    final send = find.widgetWithIcon(IconButton, Icons.send);
    await tester.ensureVisible(send);
    await tester.pumpAndSettle();
    expect(send.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

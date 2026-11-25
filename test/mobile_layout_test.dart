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
import 'package:tap_ducky/widgets/arm_profile_sheet.dart';

class _HidStatus extends HidStatusController {
  String? armedProfile;

  @override
  HidStatus build() => const HidStatus(
    rootAvailable: true,
    hidSupported: true,
    sessionArmed: false,
    deviceConnected: false,
  );

  @override
  Future<void> activateMouse() async {
    armedProfile = 'mouse';
    state = state.copyWith(sessionArmed: true);
  }
}

class _Settings extends AppSettingsController {
  _Settings({this.lastProfileType = 'composite'});

  final String lastProfileType;
  String? get savedProfile => state.value?.lastProfileType;

  @override
  Future<AppSettings> build() async =>
      AppSettings.defaults().copyWith(lastProfileType: lastProfileType);

  @override
  Future<void> setLastProfileType(String profileType) async {
    state = AsyncData(
      state.requireValue.copyWith(lastProfileType: profileType),
    );
  }
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
  _HidStatus? hid,
  _Settings? settings,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        hidStatusControllerProvider.overrideWith(() => hid ?? _HidStatus()),
        appSettingsControllerProvider.overrideWith(
          () => settings ?? _Settings(),
        ),
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

    await tester.tap(find.text('Execution'));
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
      greaterThanOrEqualTo(48),
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

  testWidgets('Arm picker stays usable at large text and short height', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      const DashboardScreen(),
      size: const Size(640, 280),
    );

    await tester.tap(find.text('Arm Session'));
    await tester.pumpAndSettle();

    final sheet = find.byType(BottomSheet);
    final mouse = find.widgetWithText(
      RadioListTile<GadgetProfileType>,
      'Mouse',
    );
    final confirm = find.widgetWithText(FilledButton, 'Arm');
    await Scrollable.ensureVisible(tester.element(mouse));
    await tester.pumpAndSettle();
    expect(tester.getSize(mouse).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(sheet).width, greaterThanOrEqualTo(600));
    expect(confirm.hitTestable(), findsOneWidget);

    await tester.tap(mouse);
    await tester.pumpAndSettle();
    final selected = tester.widget<RadioGroup<GadgetProfileType>>(
      find.byType(RadioGroup<GadgetProfileType>),
    );
    expect(selected.groupValue, GadgetProfileType.mouse);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);
    expect(find.text('Arm Session'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Arm restores the last choice and commits only on confirmation', (
    tester,
  ) async {
    final hid = _HidStatus();
    final settings = _Settings(lastProfileType: 'keyboard');
    await _pumpScreen(
      tester,
      const DashboardScreen(),
      size: const Size(320, 568),
      hid: hid,
      settings: settings,
    );

    await tester.tap(find.text('Arm Session'));
    await tester.pumpAndSettle();
    final group = find.byType(RadioGroup<GadgetProfileType>);
    expect(
      tester.widget<RadioGroup<GadgetProfileType>>(group).groupValue,
      GadgetProfileType.keyboard,
    );

    final mouse = find.widgetWithText(
      RadioListTile<GadgetProfileType>,
      'Mouse',
    );
    await tester.ensureVisible(mouse);
    await tester.tap(mouse);
    await tester.pumpAndSettle();
    expect(hid.armedProfile, isNull);
    expect(settings.savedProfile, 'keyboard');

    await tester.tap(find.widgetWithText(FilledButton, 'Arm'));
    await tester.pumpAndSettle();
    expect(hid.armedProfile, 'mouse');
    expect(settings.savedProfile, 'mouse');
    expect(find.text('Disarm'), findsOneWidget);
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

    final run = find.text('Run Payload');
    expect(tester.getRect(run).bottom, lessThan(568));
    expect(
      tester.getRect(run).bottom,
      lessThan(tester.getRect(find.text('Script speed')).top),
    );
    await tester.scrollUntilVisible(find.text('Command'), 200);
    final send = find.widgetWithIcon(IconButton, Icons.send);
    await tester.ensureVisible(send);
    await tester.pumpAndSettle();
    expect(send.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

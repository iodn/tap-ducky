import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tap_ducky/app/theme.dart';
import 'package:tap_ducky/data/models/app_settings.dart';
import 'package:tap_ducky/data/models/host_os.dart';
import 'package:tap_ducky/data/models/log_entry.dart';
import 'package:tap_ducky/data/models/payload.dart';
import 'package:tap_ducky/data/models/scheduled_task.dart';
import 'package:tap_ducky/features/dashboard/dashboard_screen.dart';
import 'package:tap_ducky/features/execute/execute_screen.dart';
import 'package:tap_ducky/features/payloads/payload_editor_screen.dart';
import 'package:tap_ducky/features/schedule/schedule_editor_screen.dart';
import 'package:tap_ducky/features/schedule/schedule_screen.dart';
import 'package:tap_ducky/features/payloads/payloads_screen.dart';
import 'package:tap_ducky/state/controllers/app_settings_controller.dart';
import 'package:tap_ducky/state/controllers/execution_controller.dart';
import 'package:tap_ducky/state/controllers/hid_status_controller.dart';
import 'package:tap_ducky/state/controllers/logs_controller.dart';
import 'package:tap_ducky/state/controllers/payloads_controller.dart';
import 'package:tap_ducky/state/controllers/scheduler_controller.dart';
import 'package:tap_ducky/widgets/ducky_script_text.dart';
import 'package:tap_ducky/widgets/task_bar.dart';
import 'package:tap_ducky/widgets/arm_profile_sheet.dart';

class _HidStatus extends HidStatusController {
  String? armedProfile;

  void connectHost() {
    state = state.copyWith(
      sessionArmed: true,
      gadgetBound: true,
      deviceConnected: true,
      pcConnected: true,
      inferredHostOs: HostOs.windows,
      hostOsDetectionAvailable: true,
    );
  }

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
  _Schedules(this.items);

  final List<ScheduledTask> items;

  @override
  Future<List<ScheduledTask>> build() async => items;
}

class _Logs extends LogsController {
  @override
  Future<List<LogEntry>> build() async => [];
}

class _RunningExecution extends ExecutionController {
  @override
  ExecutionState build() => ExecutionState.idle();

  @override
  Future<void> runPayload(Payload payload, Map<String, String> params) async {
    state = ExecutionState(
      isRunning: true,
      progress: 0.25,
      status: 'Executing',
      executionId: 'test',
      payloadName: payload.name,
    );
  }
}

Future<void> _pumpScreen(
  WidgetTester tester,
  Widget screen, {
  required Size size,
  List<Payload> payloads = const [],
  List<ScheduledTask> tasks = const [],
  _HidStatus? hid,
  _Settings? settings,
  ExecutionController? execution,
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
        schedulerControllerProvider.overrideWith(() => _Schedules(tasks)),
        logsControllerProvider.overrideWith(_Logs.new),
        if (execution != null)
          executionControllerProvider.overrideWith(() => execution),
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

final _longName = List.filled(24, 'LongPayloadName').join();
final _longParameter = PayloadParameter(
  key: 'shared',
  label: List.filled(24, 'LongParameterLabel').join(),
  type: 'string',
  defaultValue: 'First default',
  description: List.filled(24, 'LongParameterDescription').join(),
  required: false,
);
final _longPayload = Payload(
  id: 'long',
  name: _longName,
  description: List.filled(24, 'Description').join(),
  script: 'STRING ${List.filled(180, 'hello').join()}',
  tags: [List.filled(24, 'tag').join()],
  parameters: [_longParameter],
  isBuiltin: false,
);

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

  testWidgets('armed session shows its USB host OS at large text size', (
    tester,
  ) async {
    final hid = _HidStatus();
    await _pumpScreen(
      tester,
      const DashboardScreen(),
      size: const Size(320, 568),
      hid: hid,
    );

    hid.connectHost();
    await tester.pumpAndSettle();

    expect(find.text('Host OS · Windows'), findsOneWidget);
    expect(find.byTooltip('Automatically inferred from USB'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('playing a recent payload fits its long title beside progress', (
    tester,
  ) async {
    final hid = _HidStatus();
    await _pumpScreen(
      tester,
      const DashboardScreen(),
      size: const Size(320, 568),
      hid: hid,
      payloads: [_longPayload],
      execution: _RunningExecution(),
    );
    hid.connectHost();
    await tester.pumpAndSettle();

    final run = find.byTooltip('Run');
    final scrollable = find.byType(Scrollable);
    await tester.scrollUntilVisible(run, 180, scrollable: scrollable);
    await Scrollable.ensureVisible(tester.element(run), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(run.hitTestable());
    await tester.pumpAndSettle();
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pumpAndSettle();

    expect(find.text('~25%'), findsOneWidget);
    expect(
      tester.widgetList<Text>(find.text(_longPayload.name))
          .any((text) => text.maxLines == 2 && text.overflow == TextOverflow.ellipsis),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'schedule picker handles long names and keeps overrides per payload',
    (tester) async {
      final alternate = _longPayload.copyWith(
        id: 'alternate',
        name: '${_longName}UniqueAlternate',
        parameters: const [
          PayloadParameter(
            key: 'shared',
            label: 'Alternate parameter',
            type: 'text',
            defaultValue: 'Alternate default',
            description: '',
            required: false,
          ),
        ],
      );
      await _pumpScreen(
        tester,
        const ScheduleEditorScreen.newTask(),
        size: const Size(320, 568),
        payloads: [_longPayload, alternate],
      );

      expect(find.text(_longName).hitTestable(), findsOneWidget);
      final scheduleScroll = find.byType(Scrollable).first;
      final firstParameter = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.controller?.text == 'First default',
      );
      await tester.scrollUntilVisible(
        firstParameter,
        220,
        scrollable: scheduleScroll,
      );
      await tester.enterText(firstParameter, 'Schedule override');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      final picker = find.widgetWithText(OutlinedButton, 'Payload');
      await tester.scrollUntilVisible(picker, -240, scrollable: scheduleScroll);
      await Scrollable.ensureVisible(tester.element(picker), alignment: 0.2);
      await tester.pumpAndSettle();
      expect(picker.hitTestable(), findsOneWidget);
      await tester.tap(picker);
      await tester.pumpAndSettle();
      expect(find.text('Choose payload'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'UniqueAlternate');
      await tester.pumpAndSettle();
      expect(find.text(_longName), findsNothing);
      await tester.tap(find.text(alternate.name));
      await tester.pumpAndSettle();
      expect(find.text(alternate.name), findsOneWidget);
      final alternateParameter = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.controller?.text == 'Alternate default',
      );
      await tester.scrollUntilVisible(
        alternateParameter,
        220,
        scrollable: scheduleScroll,
      );
      expect(find.text('Schedule override'), findsNothing);
      expect(alternateParameter, findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('payload preview and actions fit with long text', (tester) async {
    await _pumpScreen(
      tester,
      const PayloadsScreen(),
      size: const Size(320, 568),
      payloads: [_longPayload],
    );
    final list = find
        .byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        )
        .first;
    await tester.scrollUntilVisible(
      find.text(_longName),
      140,
      scrollable: list,
    );
    await tester.ensureVisible(find.byTooltip('Expand preview'));
    await tester.tap(find.byTooltip('Expand preview'));
    await tester.pumpAndSettle();
    expect(find.byType(DuckyScriptText), findsOneWidget);
    final menu = find.byType(PopupMenuButton<VoidCallback>);
    await tester.scrollUntilVisible(menu, 160, scrollable: list);
    await Scrollable.ensureVisible(tester.element(menu), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(menu);
    await tester.pumpAndSettle();
    expect(find.text('Duplicate'), findsOneWidget);
    expect(find.text('Export'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'parameter editor keeps Save reachable with a keyboard and large text',
    (tester) async {
      await _pumpScreen(
        tester,
        const PayloadEditorScreen(),
        size: const Size(320, 568),
      );
      await tester.tap(find.text('Parameters'));
      await tester.pumpAndSettle();
      final add = find.text('Add');
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(find.text('Add parameter'), findsOneWidget);
      final form = find.byType(Form).last;
      final save = find.widgetWithText(TextButton, 'Save');
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text('Enter a key'), findsOneWidget);

      final fields = find.descendant(
        of: form,
        matching: find.byType(TextFormField),
      );
      await tester.enterText(fields.at(0), 'GREETING');
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(save.hitTestable(), findsOneWidget);

      await tester.ensureVisible(fields.at(1));
      await tester.enterText(fields.at(1), 'Greeting');
      await tester.tap(save);
      await tester.pumpAndSettle();
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(find.text('Add parameter'), findsNothing);
      final edit = find.byTooltip('Edit parameter');
      await tester.scrollUntilVisible(
        edit,
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(edit);
      await tester.pumpAndSettle();
      await tester.tap(edit);
      await tester.pumpAndSettle();
      expect(find.text('Edit parameter'), findsOneWidget);
      expect(find.text('Greeting'), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Greeting'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('imported parameters with a legacy type open for editing', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      PayloadEditorScreen(payloadId: _longPayload.id),
      size: const Size(320, 568),
      payloads: [_longPayload],
    );

    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextFormField && widget.controller?.text == _longName,
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Parameters'));
    await tester.pumpAndSettle();
    final edit = find.byTooltip('Edit parameter');
    await tester.ensureVisible(edit);
    await tester.pumpAndSettle();
    await tester.tap(edit);
    await tester.pumpAndSettle();

    expect(find.text('Edit parameter'), findsOneWidget);
    final type = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>),
    );
    expect(type.initialValue, 'string');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'new payload starts in the code editor and keeps edits across tabs',
    (tester) async {
      await _pumpScreen(
        tester,
        const PayloadEditorScreen(),
        size: const Size(320, 568),
      );
      final editor = find.byKey(const ValueKey('payload-script-editor'));
      expect(editor.hitTestable(), findsOneWidget);
      expect(find.byTooltip('Syntax').hitTestable(), findsOneWidget);
      expect(find.text('Name'), findsNothing);

      await tester.enterText(editor, 'STRING hello');
      await tester.pump(const Duration(milliseconds: 650));
      tester.view.viewInsets = const FakeViewPadding(bottom: 225);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(find.text('Save').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a name'), findsOneWidget);
      await tester.tap(find.text('Script'));
      await tester.pumpAndSettle();
      final field = tester.widget<TextFormField>(editor);
      expect(field.controller!.text, 'STRING hello');
      expect(field.controller, isA<DuckyScriptEditingController>());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('schedule cards wrap long labels and metadata', (tester) async {
    await _pumpScreen(
      tester,
      const ScheduleScreen(),
      size: const Size(320, 568),
      payloads: [_longPayload],
      tasks: [
        ScheduledTask(
          id: 'schedule',
          payloadId: _longPayload.id,
          name: _longName,
          enabled: true,
          trigger: 'app_foreground',
          params: const {},
          createdAt: DateTime(2026),
          windowStart: '09:00',
          windowEnd: '20:00',
          lastRunAt: DateTime(2026, 9, 20, 23, 30),
        ),
      ],
    );
    final delete = find.widgetWithIcon(OutlinedButton, Icons.delete);
    await tester.scrollUntilVisible(delete, 160);
    await tester.pumpAndSettle();
    expect(delete.hitTestable(), findsOneWidget);
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

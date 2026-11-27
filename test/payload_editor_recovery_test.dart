import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tap_ducky/data/models/payload.dart';
import 'package:tap_ducky/data/services/local_drafts_service.dart';
import 'package:tap_ducky/features/payloads/payload_editor_screen.dart';
import 'package:tap_ducky/state/controllers/payloads_controller.dart';

final _scriptField = find.byKey(const ValueKey('payload-script-editor'));
const _gadget = MethodChannel('org.kaijinlab.tap_ducky/gadget');
const _savedPayload = Payload(
  id: 'hi',
  name: 'Original name',
  description: 'Original description',
  tags: ['original'],
  parameters: [],
  script: 'STRING Original text',
  isBuiltin: false,
);

class _Payloads extends PayloadsController {
  _Payloads(this.items);

  final List<Payload> items;
  final saved = <Payload>[];

  @override
  Future<List<Payload>> build() async => items;

  @override
  Future<void> updatePayload(Payload payload) async => saved.add(payload);
}

class _LocalDrafts extends LocalDraftsService {
  @override
  Future<LocalModelStatus> status() async =>
      (state: 'ready', name: 'Local test model', sizeBytes: 1);

  @override
  Future<PayloadDraft> generate(String prompt) async =>
      PayloadDraft.fromResponse(
        '{"title":"Generated name","description":"Generated description",'
        '"tags":["generated"],"script":"STRING Draft text"}',
      );
}

Future<void> _openEditor(
  WidgetTester tester, {
  required _Payloads payloads,
  String? payloadId,
  LocalDraftsService? model,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        payloadsControllerProvider.overrideWith(() => payloads),
        if (model != null) localDraftsServiceProvider.overrideWithValue(model),
      ],
      child: MaterialApp(home: PayloadEditorScreen(payloadId: payloadId)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('validation updates an open issue list when Android responds', (
    tester,
  ) async {
    final response = Completer<Map<String, Object>>();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_gadget, (call) async {
      if (call.method == 'validateDuckyScript') return response.future;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_gadget, null));
    await _openEditor(tester, payloads: _Payloads([]));
    await tester.enterText(_scriptField, 'DELAY (100 + 20');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byTooltip('Script validation and estimate'));
    await tester.pumpAndSettle();
    expect(find.text('Checking Android syntax...'), findsOneWidget);
    expect(find.text('No issues found'), findsNothing);

    response.complete({'message': 'Missing closing parenthesis', 'line': 1});
    await tester.pumpAndSettle();
    expect(find.text('Missing closing parenthesis'), findsOneWidget);
    expect(find.text('Checking Android syntax...'), findsNothing);
  });

  testWidgets('Save refuses an Android parser error and opens its line', (
    tester,
  ) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_gadget, (call) async {
      if (call.method == 'validateDuckyScript' &&
          (call.arguments as Map)['script'] != _savedPayload.script) {
        return {
          'message': 'Missing closing parenthesis in expression',
          'line': 12,
        };
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_gadget, null));
    final payloads = _Payloads([_savedPayload]);
    await _openEditor(tester, payloads: payloads, payloadId: _savedPayload.id);
    final prefix = List.filled(11, 'REM sample').join('\n');
    const badLine = 'DELAY (100 + 20';
    await tester.enterText(_scriptField, '$prefix\n$badLine');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(payloads.saved, isEmpty);
    expect(
      find.text('Missing closing parenthesis in expression'),
      findsOneWidget,
    );
    await tester.tap(find.text('Line 12'));
    await tester.pumpAndSettle();
    final editor = tester.widget<TextFormField>(_scriptField).controller!;
    expect(editor.selection.textInside(editor.text), badLine);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an editor draft restores script and details after reopening', (
    tester,
  ) async {
    await _openEditor(tester, payloads: _Payloads([]));
    await tester.enterText(_scriptField, 'STRING Unsaved text');
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Unsaved name',
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    await _openEditor(tester, payloads: _Payloads([]));
    expect(
      tester.widget<TextFormField>(_scriptField).controller!.text,
      'STRING Unsaved text',
    );
    expect(find.text('Unsaved draft restored'), findsOneWidget);
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved name'), findsOneWidget);
  });

  testWidgets(
    'an existing payload applies only the draft script and can undo',
    (tester) async {
      await _openEditor(
        tester,
        payloads: _Payloads([_savedPayload]),
        payloadId: _savedPayload.id,
        model: _LocalDrafts(),
      );
      await tester.tap(find.text('Draft with AI'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Request'),
        'Type draft text',
      );
      await tester.tap(find.text('Generate'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, 'Replace script only'),
            )
            .value,
        isTrue,
      );
      await tester.tap(find.text('Use draft'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(_scriptField).controller!.text,
        contains('STRING Draft text'),
      );
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(find.text('Original name'), findsOneWidget);
      expect(find.text('Original description'), findsOneWidget);
      expect(find.text('original'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Script'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(_scriptField).controller!.text,
        _savedPayload.script,
      );
    },
  );
}

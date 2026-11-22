import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tap_ducky/data/services/local_drafts_service.dart';
import 'package:tap_ducky/features/payloads/payload_editor_screen.dart';

const _greeting =
    '''{"title":"Hello world","description":"Types a greeting twenty times.",
"tags":["demo"],"text":"hello world","repeat":20}''';

class _LocalDrafts extends LocalDraftsService {
  _LocalDrafts(this.modelStatus);

  final String modelStatus;
  String? request;

  @override
  Future<String> status() async => modelStatus;

  @override
  Future<PayloadDraft> generate(String prompt) async {
    request = prompt;
    return PayloadDraft.fromResponse(_greeting);
  }
}

void main() {
  test('model output becomes a bounded typing script', () {
    final result = PayloadDraft.fromResponse('```json\n$_greeting\n```');
    expect(result.title, 'Hello world');
    expect(result.tags, ['demo']);
    expect(result.script, 'STRINGLN hello world\nREPEAT 19');
  });

  test('rejects multiline instructions and out-of-range repetition', () {
    expect(
      () => PayloadDraft.fromResponse(
        _greeting.replaceFirst(
          '"text":"hello world"',
          r'"text":"hello\nENTER"',
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => PayloadDraft.fromResponse(
        _greeting.replaceFirst('"repeat":20', '"repeat":1000'),
      ),
      throwsFormatException,
    );
  });

  testWidgets('draft action requires a model and fills the form after review', (
    tester,
  ) async {
    Future<void> editor(_LocalDrafts service) async {
      await tester.pumpWidget(
        ProviderScope(
          key: ValueKey(service.modelStatus),
          overrides: [localDraftsServiceProvider.overrideWithValue(service)],
          child: const MaterialApp(home: PayloadEditorScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    await editor(_LocalDrafts('missing'));
    final action = find.text('Draft with AI');
    expect(action, findsNothing);

    final service = _LocalDrafts('ready');
    await editor(service);
    await tester.scrollUntilVisible(
      action,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(action);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Request'),
      'Type hello world 20 times',
    );
    await tester.tap(find.text('Generate'));
    await tester.pumpAndSettle();
    expect(service.request, 'Type hello world 20 times');
    expect(find.text('Review draft'), findsOneWidget);
    await tester.tap(find.text('Use draft'));
    await tester.pumpAndSettle();

    Iterable<String?> fieldValues() => tester
        .widgetList<TextFormField>(find.byType(TextFormField))
        .map((field) => field.controller?.text);
    expect(fieldValues(), contains('STRINGLN hello world\nREPEAT 19'));
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
    expect(
      fieldValues(),
      containsAll(['Hello world', 'Types a greeting twenty times.', 'demo']),
    );
  });
}

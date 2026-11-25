import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tap_ducky/data/services/local_drafts_service.dart';
import 'package:tap_ducky/features/payloads/payload_editor_screen.dart';
import 'package:tap_ducky/features/settings/widgets/local_draft_settings.dart';

const _urlScript =
    'DELAY 1000\nGUI r\nDELAY 800\nSTRING https://google.com\nENTER\n'
    'DELAY 3000';

String _draft({
  String title = 'Google',
  String description = 'Opens Google.',
  List<String> tags = const ['browser'],
  List<Object?> steps = const [
    {'action': 'open_url', 'value': 'google.com'},
  ],
}) => jsonEncode({
  'title': title,
  'description': description,
  'tags': tags,
  'steps': steps,
});

const _fullScript = r'''
REM full command set
REM_BLOCK
comment inside the block
END_REM
DELAY 1000
DEFAULTDELAY 10
STRING hello
STRINGLN world
STRING_DELAY 40 slow
REPEAT 2
GUI r
CTRL l
CTRL SHIFT T
ALT TAB
HOLD SHIFT
RELEASE SHIFT
KEYDOWN CTRL
KEYUP CTRL
INJECT_MOD ALT
INJECT_MOD CLEAR
MOUSE CLICK LEFT 2
MOUSE MOVE 10 0 2
MOUSE SCROLL DOWN 3
MOUSE HOLD LEFT 5 5 1
MOUSE DRAG LEFT 5 5 1
VAR $counter = 1
DEFINE APP notepad
FUNCTION greet(name)
STRING hello
RETURN 1
END_FUNCTION
greet(world)
IF $counter == 1 THEN
ENTER
ELSE IF $counter == 2 THEN
TAB
ELSE
ESC
END_IF
WHILE $counter < 3
VAR $counter = $counter + 1
END_WHILE
TRY
DELAY 100
CATCH
REM ignored
END_TRY
WAIT_FOR KEYBOARD_READY 5000
SLEEP_UNTIL 500
RANDOM_LOWERCASE_LETTER 3
RANDOM_UPPERCASE_LETTER 2
RANDOM_LETTER 2
RANDOM_NUMBER 2
RANDOM_SPECIAL 2
RANDOM_CHAR 2
MEDIA_PLAYPAUSE
MEDIA_STOP
MEDIA_PREV
MEDIA_NEXT
MEDIA_VOLUMEUP
MEDIA_VOLUMEDOWN
MEDIA_MUTE
NUMPAD_0
NUMPAD_9
NUMPAD_PLUS
NUMPAD_MINUS
NUMPAD_MULTIPLY
NUMPAD_DIVIDE
NUMPAD_ENTER
NUMPAD_PERIOD
ENTER
TAB
ESC
SPACE
BACKSPACE
DELETE
INSERT
HOME
END
PAGEUP
PAGEDOWN
UP
DOWN
LEFT
RIGHT
F1
F12
MENU
CAPSLOCK
NUMLOCK
SCROLLLOCK
PRINTSCREEN
PAUSE
''';

class _LocalDrafts extends LocalDraftsService {
  _LocalDrafts(this.modelStatus);

  final String modelStatus;
  String? request;

  @override
  Future<LocalModelStatus> status() async =>
      (state: modelStatus, name: null, sizeBytes: null);

  @override
  Future<PayloadDraft> generate(String prompt) async {
    request = prompt;
    return PayloadDraft.fromResponse(_draft());
  }
}

void main() {
  testWidgets('model settings show the imported filename and size', (
    tester,
  ) async {
    const channel = MethodChannel('org.kaijinlab.tap_ducky/local_drafts');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {
        'state': 'ready',
        'name': 'gemma-4-E2B-it.litertlm',
        'sizeBytes': 2588147712,
      },
    );
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: LocalDraftSettings())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('gemma-4-E2B-it.litertlm'), findsOneWidget);
    expect(find.textContaining('2.41 GiB'), findsOneWidget);
    expect(find.text('Replace model'), findsOneWidget);
  });

  testWidgets('model setup explains GGUF and shows the picker error', (
    tester,
  ) async {
    const channel = MethodChannel('org.kaijinlab.tap_ducky/local_drafts');
    final messenger = tester.binding.defaultBinaryMessenger;
    const message =
        'GGUF is not supported by LiteRT-LM. Choose a .litertlm model instead.';
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'status') return {'state': 'missing'};
      throw PlatformException(code: 'MODEL_FORMAT', message: message);
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: LocalDraftSettings())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Get Qwen2 0.5B'), findsNothing);
    expect(find.textContaining('GGUF files are not supported'), findsOneWidget);
    await tester.tap(find.text('Choose model'));
    await tester.pumpAndSettle();
    expect(find.text(message), findsOneWidget);
  });

  test('model steps become a validated DuckyScript payload', () {
    final result = PayloadDraft.fromResponse('```json\n${_draft()}\n```');
    expect(result.title, 'Google');
    expect(result.description, 'Opens Google.');
    expect(result.tags, ['browser']);
    expect(result.script, _urlScript);
  });

  test('extracts a URL from a sentence', () {
    final result = PayloadDraft.fromResponse(
      _draft(
        steps: const [
          {'action': 'open_url', 'value': 'I want to open google.com'},
        ],
      ),
    );
    expect(result.script, _urlScript);
  });

  test('compiles all supported action types', () {
    final result = PayloadDraft.fromResponse(
      _draft(
        steps: const [
          {'action': 'open_app', 'value': 'notepad'},
          {'action': 'type', 'value': 'hello'},
          {'action': 'type_line', 'value': 'world'},
          {'action': 'key', 'value': 'ENTER'},
          {'action': 'shortcut', 'value': 'CTRL+L'},
          {'action': 'delay', 'ms': 500},
          {'action': 'mouse_click', 'value': 'left'},
          {'action': 'mouse_move', 'value': '10,5'},
          {'action': 'mouse_scroll', 'value': 'down'},
          {'action': 'repeat', 'ms': 2},
          {'action': 'comment', 'value': 'note'},
          {'action': 'raw', 'value': 'MEDIA_MUTE'},
        ],
      ),
    );

    expect(result.script, contains('GUI r'));
    expect(result.script, contains('STRING notepad'));
    expect(result.script, contains('STRING hello'));
    expect(result.script, contains('STRINGLN world'));
    expect(result.script, contains('ENTER'));
    expect(result.script, contains('CTRL L'));
    expect(result.script, contains('DELAY 500'));
    expect(result.script, contains('MOUSE CLICK LEFT'));
    expect(result.script, contains('MOUSE MOVE 10 5'));
    expect(result.script, contains('MOUSE SCROLL DOWN'));
    expect(result.script, contains('REPEAT 2'));
    expect(result.script, contains('REM note'));
    expect(result.script, contains('MEDIA_MUTE'));
  });

  test('accepts a raw DuckyScript when steps are absent', () {
    final result = PayloadDraft.fromResponse(
      jsonEncode({
        'title': 'Full command set',
        'description': 'Exercises the full command set.',
        'tags': ['full'],
        'script': _fullScript,
      }),
      prompt: 'full command set',
    );
    expect(result.script, contains('CTRL SHIFT T'));
    expect(result.script, contains('WAIT_FOR KEYBOARD_READY 5000'));
    expect(result.script, contains('MEDIA_MUTE'));
  });

  test('sanitizes bad metadata but keeps valid steps', () {
    final result = PayloadDraft.fromResponse(
      _draft(title: '', tags: const ['bad tag']),
      prompt: 'open google.com',
    );
    expect(result.title, 'open google.com');
    expect(result.tags, ['badtag']);
    expect(result.script, _urlScript);
  });

  test('falls back to the request when the model output is unusable', () {
    final result = PayloadDraft.fromResponse(
      'not json',
      prompt: 'I want a script to open my website google.com',
    );
    expect(result.title, 'Open google.com');
    expect(result.tags, ['browser']);
    expect(result.script, _urlScript);
  });

  test('falls back to opening an app or typing text', () {
    final app = PayloadDraft.fromResponse('not json', prompt: 'open notepad');
    expect(app.script, contains('GUI r'));
    expect(app.script, contains('STRING notepad'));

    final typed = PayloadDraft.fromResponse(
      'not json',
      prompt: 'type hello world',
    );
    expect(typed.script, contains('STRING hello world'));
    expect(typed.tags, ['text']);
  });

  test('falls back when every model action is unsupported', () {
    final result = PayloadDraft.fromResponse(
      _draft(
        steps: const [
          {'action': 'explode'},
        ],
      ),
      prompt: 'open google.com',
    );
    expect(result.script, _urlScript);
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
    expect(find.text('Set up AI'), findsOneWidget);

    final service = _LocalDrafts('ready');
    await editor(service);
    expect(action.hitTestable(), findsOneWidget);
    await tester.tap(action);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Request'),
      'Open google.com',
    );
    await tester.tap(find.text('Generate'));
    await tester.pumpAndSettle();
    expect(service.request, 'Open google.com');
    expect(find.text('Review draft'), findsOneWidget);
    await tester.tap(find.text('Use draft'));
    await tester.pumpAndSettle();

    Iterable<String?> fieldValues() => tester
        .widgetList<TextFormField>(find.byType(TextFormField))
        .map((field) => field.controller?.text);
    expect(fieldValues(), contains(_urlScript));
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(fieldValues(), containsAll(['Google', 'Opens Google.', 'browser']));
  });
}

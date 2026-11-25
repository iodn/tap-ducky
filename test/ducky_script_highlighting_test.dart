import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tap_ducky/widgets/ducky_script_text.dart';

void main() {
  testWidgets('highlights syntax and retains the exact script and IME range', (
    tester,
  ) async {
    const script =
        '  DELAY 200\r\nSTRING 123 {{NAME}}\nREM this is a comment\n'
        'REM_BLOCK\nDELAY 42\nEND_REM\nSTRINGLN\nDELAY 99\nEND_STRINGLN\n';
    final compositionStart = script.indexOf('{{NAME}}') + 2;
    final controller = DuckyScriptEditingController();
    addTearDown(controller.dispose);
    controller.value = const TextEditingValue(text: script).copyWith(
      selection: TextSelection.collapsed(offset: compositionStart + 2),
      composing: TextRange(start: compositionStart, end: compositionStart + 2),
    );
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (innerContext) {
            context = innerContext;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    final span = controller.buildTextSpan(
      context: context,
      withComposing: false,
    );
    final pieces = span.children!.cast<TextSpan>();
    Color? colorOf(String text) =>
        pieces.firstWhere((piece) => piece.text == text).style?.color;

    expect(span.toPlainText(), script);
    expect(colorOf('DELAY'), isNotNull);
    expect(colorOf('200'), isNot(colorOf('DELAY')));
    expect(colorOf(' 123 '), isNot(colorOf('200')));
    expect(colorOf('{{NAME}}'), isNot(colorOf(' 123 ')));
    expect(colorOf('DELAY 42'), colorOf('REM this is a comment'));
    expect(colorOf('DELAY 99'), colorOf(' 123 '));
    final composing = controller.buildTextSpan(
      context: context,
      withComposing: true,
    );
    expect(composing.toPlainText(), script);
    expect(
      composing.children!.cast<TextSpan>().any(
        (piece) =>
            piece.text == 'NA' &&
            piece.style?.decoration == TextDecoration.underline,
      ),
      isTrue,
    );
    expect(controller.value.selection.baseOffset, compositionStart + 2);
  });

  testWidgets('uses a distinct theme palette in selectable previews', (
    tester,
  ) async {
    const script = 'STRING Hello 🌱\nDELAY 20';
    Future<TextSpan> preview(Brightness brightness) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          themeAnimationDuration: Duration.zero,
          home: const Scaffold(body: DuckyScriptText(script, selectable: true)),
        ),
      );
      await tester.pumpAndSettle();
      final text = tester.widget<SelectableText>(find.byType(SelectableText));
      return text.textSpan!;
    }

    final light = await preview(Brightness.light);
    final dark = await preview(Brightness.dark);
    expect(light.toPlainText(), script);
    expect(dark.toPlainText(), script);
    final darkColors = dark.children!.cast<TextSpan>().map(
      (piece) => piece.style?.color,
    );
    final lightColors = light.children!.cast<TextSpan>().map(
      (piece) => piece.style?.color,
    );
    expect(darkColors, isNot(equals(lightColors)));
  });
}

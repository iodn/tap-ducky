import 'package:flutter_test/flutter_test.dart';
import 'package:tap_ducky/data/services/digispark_converter.dart';

void main() {
  test('converts DigiMouse wheel movement into MOUSE SCROLL commands', () {
    const sketch = '''
#include "DigiKeyboard.h"
void loop() {
  DigiMouse.move(10, -5, -2);
  DigiMouse.scroll(3);
}
''';

    final result = DigiSparkConverter.convert(sketch);

    expect(result, isNotNull);
    expect(result!.text, contains('MOUSE MOVE 10 -5'));
    expect(result.text, contains('MOUSE SCROLL DOWN 2'));
    expect(result.text, contains('MOUSE SCROLL UP 3'));
    expect(result.text, isNot(contains('MOUSE SCROLL -2')));
    expect(result.text, isNot(contains('MOUSE SCROLL 3')));
  });

  test('skips a zero wheel scroll', () {
    const sketch = '''
#include "DigiKeyboard.h"
void loop() {
  DigiMouse.scroll(0);
}
''';

    expect(DigiSparkConverter.convert(sketch), isNull);
  });

  test('converts the official DigiMouse click helpers', () {
    const sketch = '''
#include "DigiKeyboard.h"
void loop() {
  DigiMouse.leftClick();
  DigiMouse.rightClick();
  DigiMouse.middleClick();
}
''';

    final result = DigiSparkConverter.convert(sketch);

    expect(result, isNotNull);
    expect(result!.usedMouseApis, isTrue);
    expect(result.text, contains('MOUSE CLICK LEFT'));
    expect(result.text, contains('MOUSE CLICK RIGHT'));
    expect(result.text, contains('MOUSE CLICK MIDDLE'));
  });
}

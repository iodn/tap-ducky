import 'package:flutter_test/flutter_test.dart';
import 'package:tap_ducky/data/services/ducky_script_validator.dart';

void main() {
  final validator = DuckyScriptValidator();

  test('accepts Hak5 OS extension imports and symbolic comparisons', () {
    final result = validator.validate(r'''
EXTENSION OS_DETECTION
FUNCTION DETECT_OS()
  $_OS = WINDOWS
END_FUNCTION
END_EXTENSION
DETECT_OS()
IF ($_OS == MACOS) THEN
  DELAY $pause
END_IF
''');
    expect(result.issues, isEmpty);
  });

  test('reports bad extension syntax and writes to the detected OS', () {
    for (final script in [
      'DETECT_OS(1)',
      r'$_OS = WINDOWS',
      r'VAR $_OS=0',
      'EXTENSION OS_DETECTION',
      'EXTENSION OTHER\nEND_EXTENSION',
    ]) {
      expect(validator.validate(script).hasErrors, isTrue, reason: script);
    }
  });

  test('warns once for unsupported Hak5 variables in expressions', () {
    final result = validator.validate(r'''
REM $_CAPSLOCK_ON is part of a note
STRING $_CURRENT_PID
VAR $count = $_HOST_CONFIGURATION_REQUEST_COUNT
IF $_HOST_CONFIGURATION_REQUEST_COUNT > 0 THEN
  DELAY 50
END_IF
''');
    expect(result.hasErrors, isFalse);
    expect(result.issues.single.line, 3);
    expect(result.issues.single.message,
        contains(r'$_HOST_CONFIGURATION_REQUEST_COUNT'));
  });
}

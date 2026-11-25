import 'package:flutter_test/flutter_test.dart';
import 'package:tap_ducky/data/services/ducky_script_validator.dart';

void main() {
  final validator = DuckyScriptValidator();

  test('reports unsupported writes once as errors', () {
    for (final script in [r'$_JITTER_MAX = 20', r'VAR $_BUTTON_ENABLED = TRUE']) {
      final result = validator.validate(script);
      expect(result.issues.single.severity, IssueSeverity.error);
      expect(result.issues.single.message, contains('unavailable in TapDucky'));
    }
  });

  test('accepts Hak5 OS extension imports and symbolic comparisons', () {
    final result = validator.validate(r'''
EXTENSION OS_DETECTION
FUNCTION DETECT_OS()
  $_OS = WINDOWS
END_FUNCTION
END_EXTENSION
DETECT_OS()
VAR $pause = 20
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

  test('recognizes USB identity, writable ranges, and stored scancodes', () {
    final result = validator.validate(r'''
$_RANDOM_MIN = 1
$_RANDOM_MAX = 6
VAR $key = $_RANDOM_UPPER_LETTER_KEYCODE
IF $_CURRENT_VID == 0x1234 THEN
  INJECT_VAR $key
END_IF
''');
    expect(result.issues, isEmpty);
    expect(validator.validate(r'$_CURRENT_PID = 0').hasErrors, isTrue);
    expect(validator.validate('INJECT_VAR').hasErrors, isTrue);
  });

  test('accepts delay expressions and Hak5 DEFINE constants', () {
    final result = validator.validate(r'''
DEFINE #WAIT 100
DEFINE #BASE 100
VAR $pause = 200
DELAY #WAIT
DELAY ( #BASE + ($pause >> 1) )
DELAY 100 + $pause
''');
    expect(result.issues, isEmpty);
    expect(validator.validate('DELAY (100 + unresolved)').hasErrors, isTrue);
    expect(validator.validate('DEFINE #WAIT').hasErrors, isTrue);
  });

  test('DEFINE protects variable names and preserves nested labels', () {
    final result = validator.validate(r'''
DEFINE WAIT 100
VAR $WAIT = 30
DELAY $WAIT
DELAY WAIT
''');
    expect(result.issues, isEmpty);
    expect(result.totalDelayMs, 120);
    expect(validator.validate('DEFINE #A 100\nDEFINE #B #A\nDELAY #B').hasErrors, isTrue);
  });

  test('rejects literal random bounds outside the unsigned 16-bit range', () {
    final result = validator.validate(r'''
DEFINE #LIMIT 65536
$_RANDOM_MIN = -1
VAR $_RANDOM_MAX = #LIMIT
$_RANDOM_MAX = 0xffff
VAR $next = 42
$_RANDOM_MIN = $next + 2
''');
    expect(result.issues.map((issue) => (issue.line, issue.message)), [
      (2, r'$_RANDOM_MIN requires a value from 0 to 65535, got -1'),
      (3, r'$_RANDOM_MAX requires a value from 0 to 65535, got 65536'),
    ]);
    expect(result.hasErrors, isTrue);
  });

  test('validates the button timeout as a writable debounce interval', () {
    final result = validator.validate(r'''
$_BUTTON_TIMEOUT = 0
WAIT_FOR_BUTTON_PRESS
$_BUTTON_TIMEOUT = 65536
''');
    expect(result.issues.single.line, 3);
    expect(result.issues.single.message,
        r'$_BUTTON_TIMEOUT requires a value from 0 to 65535, got 65536');
  });

  test('flags literals too large for native integer parsing', () {
    for (final literal in ['0x100000000', '0x10000000000000000', '999999999999999999999999']) {
      final result = validator.validate('\$_RANDOM_MAX = $literal');
      expect(result.hasErrors, isTrue, reason: literal);
      expect(result.issues.single.message, contains('requires a value from 0 to 65535'));
    }
  });

  test('warns for variable references with no assignment in their scope', () {
    final result = validator.validate(r'''
DEFINE #WAIT $misspelled
FUNCTION adjust($amount)
  $amount = $amount + $later
  RETURN $amount
END_FUNCTION
DELAY #WAIT
DELAY $amount
DELAY $misspelled
IF ($_CURRENT_VID > 0 && $? == 0) THEN
  REM ($ignored)
  STRING ($literal)
END_IF
$later = 20
''');

    expect(result.hasErrors, isFalse);
    expect(result.issues.map((issue) => (issue.line, issue.message)), [
      (6, r'$misspelled has no assignment in this script'),
      (7, r'$amount has no assignment in this script'),
    ]);
  });

  test('checks declaration names and requires a value after equals', () {
    final valid = validator.validate(r'''
VAR $2seconds
$2seconds = 2000
VAR $pause $2seconds + 30
DELAY $pause
''');
    expect(valid.issues, isEmpty);
    for (final script in [r'VAR $bad-name = 20', r'VAR $pause =', r'$pause =']) {
      expect(validator.validate(script).errorCount, 1, reason: script);
    }
  });
}

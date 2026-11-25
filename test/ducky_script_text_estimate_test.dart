import 'package:flutter_test/flutter_test.dart';
import 'package:tap_ducky/data/services/ducky_script_validator.dart';

void main() {
  final validator = DuckyScriptValidator();

  test('text estimates count leading, repeated and trailing spaces', () {
    final literal = validator.validate('STRING  a  b ');
    final compact = validator.validate('STRING a b');
    expect(literal.estimatedDurationMs - compact.estimatedDurationMs, 75);

    final delayed = validator.validate('STRING_DELAY 20  a  b ');
    expect(delayed.totalDelayMs, 120);
  });

  test('blocks count the same text and line breaks the engine will emit', () {
    final string = validator.validate('STRING\na\nb\n end_string');
    final stringLn = validator.validate('STRINGLN\na\n\nb\n end_stringln');
    expect(
      string.estimatedDurationMs,
      validator.validate('STRING ab').estimatedDurationMs,
    );
    expect(stringLn.estimatedDurationMs - string.estimatedDurationMs, 75);
    expect(validator.validate('STRINGLN\nEND_STRINGLN').estimatedDurationMs, 0);
  });
}

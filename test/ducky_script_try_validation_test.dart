import 'package:flutter_test/flutter_test.dart';
import 'package:tap_ducky/data/services/ducky_script_validator.dart';

void main() {
  final validator = DuckyScriptValidator();

  test('reports an unclosed TRY and unmatched block markers', () {
    expect(validator.validate('TRY\nDELAY 20').hasErrors, isTrue);
    expect(validator.validate('CATCH\nEND_TRY').errorCount, 2);
  });

  test('rejects duplicate CATCH and accepts nested TRY blocks', () {
    expect(validator.validate('TRY\nCATCH\nCATCH\nEND_TRY').hasErrors, isTrue);
    expect(
      validator.validate('TRY\nTRY\nCATCH\nENDTRY\nCATCH\nEND_TRY').hasErrors,
      isFalse,
    );
  });
}

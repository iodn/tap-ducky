import 'package:flutter_test/flutter_test.dart';
import 'package:tap_ducky/data/services/ducky_script_validator.dart';

void main() {
  test('warns when a modifier command has no key', () {
    final result = DuckyScriptValidator().validate('GUI');
    expect(result.hasWarnings, isTrue);
  });

  test('warns when a modifier command has an unknown key', () {
    final result = DuckyScriptValidator().validate('GUI definitelynotakey');
    expect(result.hasWarnings, isTrue);
  });

  test('accepts valid modifier combos', () {
    for (final script in [
      'GUI r',
      'CTRL SHIFT T',
      'ALT TAB',
      'CTRL ALT DEL',
      'GUI F4',
      'CTRL UP',
      'GUI RCTRL r',
      'GUI WIN r',
      'GUI CTRL-L',
    ]) {
      final result = DuckyScriptValidator().validate(script);
      expect(result.hasWarnings, isFalse, reason: script);
      expect(result.hasErrors, isFalse, reason: script);
    }
  });

  test('does not apply combo checks to HOLD or INJECT_MOD', () {
    expect(
      DuckyScriptValidator().validate('HOLD CTRL SHIFT').hasWarnings,
      isFalse,
    );
    expect(
      DuckyScriptValidator().validate('INJECT_MOD CTRL').hasWarnings,
      isFalse,
    );
  });
}

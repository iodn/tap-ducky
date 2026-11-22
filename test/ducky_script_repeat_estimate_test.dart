import 'package:flutter_test/flutter_test.dart';
import 'package:tap_ducky/data/services/ducky_script_validator.dart';

void main() {
  test('REPEAT scales the preceding command only once', () {
    final validator = DuckyScriptValidator();

    for (final multiplier in [0.5, 1.0, 2.0]) {
      final single = validator.validate('DELAY 100', delayMultiplier: multiplier);
      final repeated = validator.validate(
        'DELAY 100\nREPEAT 2',
        delayMultiplier: multiplier,
      );

      expect(repeated.hasErrors, isFalse);
      expect(repeated.estimatedDurationMs, single.estimatedDurationMs * 3);
    }
  });
}

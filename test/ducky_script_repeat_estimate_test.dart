import 'package:flutter_test/flutter_test.dart';
import 'package:tap_ducky/data/services/ducky_script_validator.dart';

void main() {
  test('script multiplier scales delays, not typing or readiness waits', () {
    final validator = DuckyScriptValidator();
    const script = 'STRING hello\nWAIT_FOR HOST_CONNECTED 300000\nDELAY 100';
    final normal = validator.validate(script);
    final fast = validator.validate(script, delayMultiplier: 0.5);

    expect(normal.totalDelayMs, 100);
    expect(fast.totalDelayMs, 50);
    expect(normal.estimatedDurationMs - fast.estimatedDurationMs, 50);
  });

  test('REPEAT scales the preceding command only once', () {
    final validator = DuckyScriptValidator();

    for (final multiplier in [0.5, 1.0, 2.0]) {
      final single = validator.validate(
        'DELAY 100',
        delayMultiplier: multiplier,
      );
      final repeated = validator.validate(
        'DELAY 100\nREPEAT 2',
        delayMultiplier: multiplier,
      );

      expect(repeated.hasErrors, isFalse);
      expect(repeated.estimatedDurationMs, single.estimatedDurationMs * 3);
    }
  });

  test('REPEAT budget applies cumulatively across the script', () {
    final validator = DuckyScriptValidator();
    expect(
      validator.validate('STRING sample\nREPEAT 12000\nREPEAT 8000').hasErrors,
      isFalse,
    );
    final tooMany = validator.validate(
      'STRING sample\nREPEAT 12000\nREPEAT 8001',
    );
    expect(tooMany.issues.single.line, 3);
    expect(tooMany.issues.single.message, contains('20000'));
    expect(
      validator.validate('STRING sample\nREPEAT 2147483648').hasErrors,
      isTrue,
    );
  });
}

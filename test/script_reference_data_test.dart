import 'package:flutter_test/flutter_test.dart';
import 'package:tap_ducky/data/services/ducky_script_validator.dart';
import 'package:tap_ducky/features/settings/script_reference_data.dart';

void main() {
  test('reference lists every reserved variable recognized by the validator', () {
    final entries = scriptReference.values.expand((entries) => entries);
    final variable = RegExp(r'\$_[A-Z0-9_]+');
    final documented = entries
        .expand((entry) => variable.allMatches(entry.syntax))
        .map((match) => match.group(0)!)
        .toSet();

    expect(documented, {
      ...DuckyScriptValidator.readOnlyHak5Variables,
      ...DuckyScriptValidator.writableHak5Variables,
      ...DuckyScriptValidator.unsupportedHak5Variables,
    });
  });
}

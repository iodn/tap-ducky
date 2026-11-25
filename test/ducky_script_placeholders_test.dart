import 'package:flutter_test/flutter_test.dart';
import 'package:tap_ducky/data/services/ducky_script.dart';

void main() {
  test('detects placeholders in either supported style before estimation', () {
    expect(DuckyScript.hasPlaceholders('DELAY {{PAUSE}}'), isTrue);
    expect(DuckyScript.hasPlaceholders(r'DELAY ${ PAUSE }'), isTrue);
    expect(DuckyScript.hasPlaceholders(r'DELAY $pause'), isFalse);
  });
  test('resolves the double-brace placeholders shown in the editor', () {
    const script = 'STRING {{TARGET_IP}}\nENTER';
    expect(
      DuckyScript.resolvePlaceholders(script, {'TARGET_IP': '192.168.1.1'}),
      'STRING 192.168.1.1\nENTER',
    );
  });

  test('resolves legacy dollar-brace placeholders', () {
    expect(
      DuckyScript.resolvePlaceholders(r'STRING ${TARGET_IP}', {
        'TARGET_IP': '10.0.0.5',
      }),
      'STRING 10.0.0.5',
    );
  });

  test('resolves repeated placeholders and trims spaced keys', () {
    expect(
      DuckyScript.resolvePlaceholders('{{A}} {{ A }} {{A}}', {'A': 'x'}),
      'x x x',
    );
  });

  test('leaves unknown placeholders untouched', () {
    expect(
      DuckyScript.resolvePlaceholders('{{MISSING}}', const <String, String>{}),
      '{{MISSING}}',
    );
    expect(
      DuckyScript.resolvePlaceholders(r'${MISSING}', const <String, String>{}),
      r'${MISSING}',
    );
  });

  test('does not re-expand placeholders inside replacement values', () {
    expect(
      DuckyScript.resolvePlaceholders('{{A}}', {'A': '{{B}}', 'B': 'x'}),
      '{{B}}',
    );
  });

  test('replaces a placeholder with an empty value', () {
    expect(DuckyScript.resolvePlaceholders('x{{A}}y', {'A': ''}), 'xy');
  });
}

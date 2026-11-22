// ignore: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:tap_ducky/data/models/advanced_settings.dart';

void main() {
  test('keyboard layout backend ids match native layout ids', () {
    const expected = <String, int>{
      'us': 0,
      'tr': 1,
      'sv': 2,
      'si': 3,
      'ru': 4,
      'pt': 5,
      'no': 6,
      'it': 7,
      'hr': 8,
      'gb': 9,
      'fr': 10,
      'fi': 11,
      'es': 12,
      'dk': 13,
      'de': 14,
      'ca': 15,
      'br': 16,
      'be': 17,
      'hu': 18,
    };

    for (final entry in expected.entries) {
      final settings = AdvancedSettings.defaults().copyWith(
        keyboardLayout: entry.key,
      );
      expect(settings.keyboardLayoutBackendId, entry.value, reason: entry.key);
    }
  });

  test('keyboard layout names from backend normalize to stable ids', () {
    const expected = <String, String>{
      'US': 'us',
      'UK': 'gb',
      'Turkish': 'tr',
      'Swedish': 'sv',
      'Slovenian': 'si',
      'Russian': 'ru',
      'Portuguese': 'pt',
      'Norwegian': 'no',
      'Italian': 'it',
      'Croatian': 'hr',
      'French': 'fr',
      'Finnish': 'fi',
      'Spanish': 'es',
      'Danish': 'dk',
      'German': 'de',
      'Canadian': 'ca',
      'Brazilian': 'br',
      'Belgian': 'be',
      'Hungarian': 'hu',
    };

    for (final entry in expected.entries) {
      expect(
        AdvancedSettings.normalizeKeyboardLayoutId(entry.key),
        entry.value,
        reason: entry.key,
      );
    }
  });
}

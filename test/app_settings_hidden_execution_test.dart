import 'package:flutter_test/flutter_test.dart';
import 'package:tap_ducky/data/models/app_settings.dart';

void main() {
  group('AppSettings.hiddenExecution', () {
    test('defaults to enabled', () {
      expect(AppSettings.defaults().hiddenExecution, isTrue);
    });

    test('round-trips the disabled state', () {
      final settings = AppSettings.defaults().copyWith(hiddenExecution: false);
      final restored = AppSettings.fromJson(settings.toJson());

      expect(restored.hiddenExecution, isFalse);
      expect(settings.toJson()['hiddenExecution'], isFalse);
    });

    test('legacy settings without the key default to enabled', () {
      final json = AppSettings.defaults().toJson()..remove('hiddenExecution');

      expect(AppSettings.fromJson(json).hiddenExecution, isTrue);
    });
  });
}

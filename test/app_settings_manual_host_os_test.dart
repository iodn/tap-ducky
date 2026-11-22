import 'package:flutter_test/flutter_test.dart';
import 'package:tap_ducky/data/models/app_settings.dart';
import 'package:tap_ducky/data/models/host_os.dart';

void main() {
  group('AppSettings.manualHostOs', () {
    test('defaults to no manual label', () {
      expect(AppSettings.defaults().manualHostOs, isNull);
    });

    test('round-trips a manual selection', () {
      final settings =
          AppSettings.defaults().copyWith(manualHostOs: HostOs.macos);
      final restored = AppSettings.fromJson(settings.toJson());

      expect(settings.toJson()['manualHostOs'], 'macos');
      expect(restored.manualHostOs, HostOs.macos);
    });

    test('null explicitly clears the manual selection', () {
      final cleared = AppSettings.defaults()
          .copyWith(manualHostOs: HostOs.windows)
          .copyWith(manualHostOs: null);

      expect(cleared.manualHostOs, isNull);
    });

    test('legacy or invalid values become no manual label', () {
      final legacy = AppSettings.defaults().toJson()..remove('manualHostOs');
      expect(AppSettings.fromJson(legacy).manualHostOs, isNull);

      final invalid = AppSettings.defaults().toJson()
        ..['manualHostOs'] = 'beos';
      expect(AppSettings.fromJson(invalid).manualHostOs, isNull);
    });
  });
}

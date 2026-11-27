import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tap_ducky/data/models/run_recording.dart';
import 'package:tap_ducky/data/storage/prefs_storage.dart';
import 'package:tap_ducky/state/controllers/hid_status_controller.dart';
import 'package:tap_ducky/state/controllers/run_observation_controller.dart';
import 'package:tap_ducky/state/providers.dart';

class _Preferences implements SharedPreferences {
  final _cache = <String, String>{};
  final _persisted = <String, String>{};
  bool acceptWrite = false;

  @override
  String? getString(String key) => _cache[key];

  @override
  Future<bool> setString(String key, String value) async {
    _cache[key] = value;
    if (acceptWrite) _persisted[key] = value;
    return acceptWrite;
  }

  @override
  Future<void> reload() async => _cache
    ..clear()
    ..addAll(_persisted);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Usb extends HidStatusController {
  @override
  HidStatus build() => const HidStatus(
    rootAvailable: true,
    hidSupported: true,
    deviceConnected: false,
    sessionArmed: false,
  );
}

void main() {
  test(
    'a rejected write leaves no recording and does not block later saves',
    () async {
      final prefs = _Preferences();
      final container = ProviderContainer.test(
        overrides: [
          prefsStorageProvider.overrideWith((ref) async => PrefsStorage(prefs)),
          hidStatusControllerProvider.overrideWith(_Usb.new),
        ],
      );
      final observer = container.read(runObservationProvider.notifier);

      observer.start('rejected', record: true);
      await expectLater(
        observer.finish('rejected', RunEventKind.completed),
        throwsStateError,
      );
      expect(
        await container.read(runRecordingProvider('rejected').future),
        isNull,
      );

      prefs.acceptWrite = true;
      observer.start('saved', record: true);
      await observer.finish('saved', RunEventKind.completed);
      final recordings = await container.read(runRecordingsProvider.future);
      expect(recordings.keys, ['saved']);
    },
  );
}

import '../models/advanced_settings.dart';
import '../storage/prefs_storage.dart';

class AdvancedSettingsRepository {
  AdvancedSettingsRepository(this._storage);

  final PrefsStorage _storage;

  static const _key = 'tapducky.advanced_settings.v1';

  AdvancedSettings load() {
    final json = _storage.getJsonMap(_key);
    if (json == null) return AdvancedSettings.defaults();
    return AdvancedSettings.fromJson(json);
  }

  Future<void> save(AdvancedSettings settings) async {
    await _storage.setJsonMap(_key, settings.toJson());
  }
}

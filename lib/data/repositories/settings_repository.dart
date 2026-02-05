import '../models/app_settings.dart';
import '../storage/prefs_storage.dart';

class SettingsRepository {
  SettingsRepository(this._storage);

  final PrefsStorage _storage;

  static const _key = 'tapducky.settings.v1';

  AppSettings load() {
    final json = _storage.getJsonMap(_key);
    if (json == null) return AppSettings.defaults();
    return AppSettings.fromJson(json);
  }

  Future<void> save(AppSettings settings) async {
    await _storage.setJsonMap(_key, settings.toJson());
  }
}

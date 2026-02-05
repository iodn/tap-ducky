import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class PrefsStorage {
  PrefsStorage(this._prefs);

  final SharedPreferences _prefs;

  String? getString(String key) => _prefs.getString(key);

  Future<void> setString(String key, String value) async {
    await _prefs.setString(key, value);
  }

  Future<void> remove(String key) async {
    await _prefs.remove(key);
  }

  List<Map<String, dynamic>> getJsonList(String key) {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        _prefs.remove(key);
        return [];
      }
      return decoded.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    } catch (_) {
      _prefs.remove(key);
      return [];
    }
  }

  Future<void> setJsonList(String key, List<Map<String, dynamic>> value) async {
    await _prefs.setString(key, jsonEncode(value));
  }

  Map<String, dynamic>? getJsonMap(String key) {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        _prefs.remove(key);
        return null;
      }
      return decoded.cast<String, dynamic>();
    } catch (_) {
      _prefs.remove(key);
      return null;
    }
  }

  Future<void> setJsonMap(String key, Map<String, dynamic> value) async {
    await _prefs.setString(key, jsonEncode(value));
  }
}

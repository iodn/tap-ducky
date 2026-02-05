import '../models/log_entry.dart';
import '../storage/prefs_storage.dart';

class LogRepository {
  LogRepository(this._storage);

  final PrefsStorage _storage;

  static const _key = 'tapducky.logs.v1';
  static const _maxEntries = 1500;

  List<LogEntry> load() {
    final items = _storage.getJsonList(_key).map(LogEntry.fromJson).toList();
    items.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return items;
  }

  Future<void> append(LogEntry entry) async {
    final items = load();
    items.insert(0, entry);
    if (items.length > _maxEntries) {
      items.removeRange(_maxEntries, items.length);
    }
    await _storage.setJsonList(_key, items.map((e) => e.toJson()).toList());
  }

  Future<void> replaceAll(List<LogEntry> entries) async {
    final items = [...entries]..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    await _storage.setJsonList(_key, items.map((e) => e.toJson()).toList());
  }

  Future<void> clear() async {
    await _storage.remove(_key);
  }
}

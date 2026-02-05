import '../models/scheduled_task.dart';
import '../storage/prefs_storage.dart';

class SchedulerRepository {
  SchedulerRepository(this._storage);

  final PrefsStorage _storage;

  static const _key = 'tapducky.schedules.v1';

  List<ScheduledTask> loadAll() {
    final items = _storage.getJsonList(_key).map(ScheduledTask.fromJson).toList();
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  Future<void> saveAll(List<ScheduledTask> items) async {
    await _storage.setJsonList(_key, items.map((e) => e.toJson()).toList());
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../data/models/payload.dart';
import '../providers.dart';

final payloadsControllerProvider = AsyncNotifierProvider<PayloadsController, List<Payload>>(
  PayloadsController.new,
);

class PayloadsController extends AsyncNotifier<List<Payload>> {
  static const _uuid = Uuid();

  @override
  Future<List<Payload>> build() async {
    final repo = await ref.watch(payloadRepositoryProvider.future);
    final items = await repo.loadAll();
    final sorted = [...items]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return sorted;
  }

  Payload? byId(String id) {
    final items = state.value ?? const <Payload>[];
    for (final p in items) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<String> create(Payload draft) async {
    final id = _uuid.v4();
    final created = draft.copyWith(
      id: id,
      updatedAt: DateTime.now(),
      isBuiltin: false,
    );
    final items = [created, ...(state.value ?? const <Payload>[])];
    await _persist(items);
    return id;
  }

  Future<void> updatePayload(Payload payload) async {
    final items = [...(state.value ?? const <Payload>[])];
    final idx = items.indexWhere((p) => p.id == payload.id);
    if (idx < 0) return;
    items[idx] = payload.copyWith(updatedAt: DateTime.now());
    items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await _persist(items);
  }

  Future<void> duplicate(String id) async {
    final p = byId(id);
    if (p == null) return;
    final copy = p.copyWith(
      id: _uuid.v4(),
      name: '${p.name} (Copy)',
      isBuiltin: false,
      updatedAt: DateTime.now(),
    );
    final items = [copy, ...(state.value ?? const <Payload>[])];
    await _persist(items);
  }

  Future<void> delete(String id) async {
    final items = [...(state.value ?? const <Payload>[])];
    final idx = items.indexWhere((p) => p.id == id);
    if (idx < 0) return;
    if (items[idx].isBuiltin) return;
    items.removeAt(idx);
    await _persist(items);
  }

  Future<void> importMany(List<Payload> incoming) async {
    final items = [...(state.value ?? const <Payload>[])];
    final existingIds = items.map((e) => e.id).toSet();
    final out = <Payload>[];
    for (final p in incoming) {
      final id = existingIds.contains(p.id) ? _uuid.v4() : p.id;
      existingIds.add(id);
      out.add(p.copyWith(
        id: id,
        isBuiltin: false,
        updatedAt: DateTime.now(),
      ));
    }
    final merged = [...out, ...items]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await _persist(merged);
  }

  Future<void> _persist(List<Payload> items) async {
    state = AsyncData(items);
    final repo = await ref.read(payloadRepositoryProvider.future);
    await repo.saveAll(items);
  }
}

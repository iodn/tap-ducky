import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/payload.dart';
import '../storage/prefs_storage.dart';

class PayloadRepository {
  PayloadRepository(this._storage);

  final PrefsStorage _storage;

  static const _key = 'tapducky.payloads.v1';

  Future<List<Payload>> loadAll() async {
    final stored = _storage.getJsonList(_key).map(Payload.fromJson).toList();
    if (stored.isNotEmpty) return stored;

    // Seeding disabled by request: start with an empty library on first run.
    return const <Payload>[];
  }

  Future<void> saveAll(List<Payload> payloads) async {
    await _storage.setJsonList(_key, payloads.map((e) => e.toJson()).toList());
  }
}

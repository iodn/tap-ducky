import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class UsbProduct {
  const UsbProduct({
    required this.vid,
    required this.pid,
    required this.vendorName,
    required this.productName,
  });

  final int vid;
  final int pid;
  final String vendorName;
  final String productName;

  String get vidHex => _hex16(vid);
  String get pidHex => _hex16(pid);
}

class UsbIdsDb {
  UsbIdsDb._(this._db);

  static const String assetPath = 'assets/db/usbids.sqlite';
  static const String dbFileName = 'usbids.sqlite';

  final Database _db;

  static Future<UsbIdsDb> open() async {
    final dbDir = await getDatabasesPath();
    final dbPath = p.join(dbDir, dbFileName);

    final exists = await databaseExists(dbPath);
    if (!exists) {
      await Directory(dbDir).create(recursive: true);
      final byteData = await rootBundle.load(assetPath);
      final bytes = byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );
      await File(dbPath).writeAsBytes(bytes, flush: true);
    }

    final db = await openDatabase(dbPath, readOnly: true);
    return UsbIdsDb._(db);
  }

  Future<void> close() async {
    await _db.close();
  }

  Future<List<UsbProduct>> searchProducts(String query) async {
    final text = query.trim();
    if (text.length < 2) return const [];
    final pair = RegExp(
      r'^(?:0x)?([0-9a-f]{1,4})\s*:\s*(?:0x)?([0-9a-f]{1,4})$',
      caseSensitive: false,
    ).firstMatch(text);
    final words = text.split(RegExp(r'\s+'));
    final conditions = pair == null
        ? List.filled(
            words.length,
            "instr(lower(v.name || ' ' || p.name), lower(?)) > 0",
          ).join(' AND ')
        : 'p.vid = ? AND p.pid = ?';
    final values = pair == null
        ? <Object>[...words]
        : <Object>[
            int.parse(pair[1]!, radix: 16),
            int.parse(pair[2]!, radix: 16),
          ];
    final rows = await _db.rawQuery(
      'SELECT p.vid, p.pid, v.name AS vendor_name, p.name AS product_name '
      'FROM products p JOIN vendors v ON v.vid = p.vid WHERE $conditions '
      'ORDER BY CASE WHEN p.name = ? COLLATE NOCASE THEN 0 '
      'WHEN instr(lower(p.name), lower(?)) = 1 THEN 1 ELSE 2 END, '
      'p.name COLLATE NOCASE, v.name COLLATE NOCASE, p.vid, p.pid LIMIT 80',
      [...values, text, text],
    );
    return rows
        .map(
          (row) => UsbProduct(
            vid: row['vid'] as int,
            pid: row['pid'] as int,
            vendorName: row['vendor_name'] as String,
            productName: row['product_name'] as String,
          ),
        )
        .toList(growable: false);
  }
}

final usbIdsDbProvider = FutureProvider<UsbIdsDb>((ref) async {
  final db = await UsbIdsDb.open();
  ref.onDispose(() {
    db.close();
  });
  return db;
});

String _hex16(int value) {
  final v = value & 0xFFFF;
  return '0x${v.toRadixString(16).toUpperCase().padLeft(4, '0')}';
}

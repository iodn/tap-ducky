import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class UsbVendor {
  const UsbVendor({required this.vid, required this.name});

  final int vid;
  final String name;

  String get vidHex => _hex16(vid);
}

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
      final bytes = byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);
      await File(dbPath).writeAsBytes(bytes, flush: true);
    }

    final db = await openDatabase(dbPath, readOnly: true);
    return UsbIdsDb._(db);
  }

  Future<void> close() async {
    await _db.close();
  }

  Future<List<UsbVendor>> searchVendors(String query, {int limit = 60}) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    final like = '%$q%';
    final rows = await _db.rawQuery(
      'SELECT vid, name FROM vendors WHERE name LIKE ? ORDER BY name LIMIT ?',
      [like, limit],
    );
    return rows
        .map(
          (r) => UsbVendor(
            vid: (r['vid'] as int),
            name: (r['name'] as String),
          ),
        )
        .toList(growable: false);
  }

  Future<List<UsbProduct>> searchProductsByVendor(int vid, String query, {int limit = 80}) async {
    final q = query.trim();
    if (q.isEmpty) {
      final rows = await _db.rawQuery(
        'SELECT p.vid AS vid, p.pid AS pid, v.name AS vendor_name, p.name AS product_name '
        'FROM products p JOIN vendors v ON v.vid = p.vid '
        'WHERE p.vid = ? '
        'ORDER BY p.name LIMIT ?',
        [vid, limit],
      );
      return rows
          .map(
            (r) => UsbProduct(
              vid: (r['vid'] as int),
              pid: (r['pid'] as int),
              vendorName: (r['vendor_name'] as String),
              productName: (r['product_name'] as String),
            ),
          )
          .toList(growable: false);
    }

    final like = '%$q%';
    final rows = await _db.rawQuery(
      'SELECT p.vid AS vid, p.pid AS pid, v.name AS vendor_name, p.name AS product_name '
      'FROM products p JOIN vendors v ON v.vid = p.vid '
      'WHERE p.vid = ? AND p.name LIKE ? '
      'ORDER BY p.name LIMIT ?',
      [vid, like, limit],
    );
    return rows
        .map(
          (r) => UsbProduct(
            vid: (r['vid'] as int),
            pid: (r['pid'] as int),
            vendorName: (r['vendor_name'] as String),
            productName: (r['product_name'] as String),
          ),
        )
        .toList(growable: false);
  }

  Future<List<UsbProduct>> searchProductsByName(String query, {int limit = 80}) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    final like = '%$q%';
    final rows = await _db.rawQuery(
      'SELECT p.vid AS vid, p.pid AS pid, v.name AS vendor_name, p.name AS product_name '
      'FROM products p JOIN vendors v ON v.vid = p.vid '
      'WHERE p.name LIKE ? '
      'ORDER BY p.name LIMIT ?',
      [like, limit],
    );
    return rows
        .map(
          (r) => UsbProduct(
            vid: (r['vid'] as int),
            pid: (r['pid'] as int),
            vendorName: (r['vendor_name'] as String),
            productName: (r['product_name'] as String),
          ),
        )
        .toList(growable: false);
  }

  Future<String?> getVendorName(int vid) async {
    final rows = await _db.rawQuery('SELECT name FROM vendors WHERE vid = ? LIMIT 1', [vid]);
    if (rows.isEmpty) return null;
    return rows.first['name'] as String?;
  }

  Future<String?> getProductName(int vid, int pid) async {
    final rows = await _db.rawQuery(
      'SELECT name FROM products WHERE vid = ? AND pid = ? LIMIT 1',
      [vid, pid],
    );
    if (rows.isEmpty) return null;
    return rows.first['name'] as String?;
  }

  Future<({String? vendor, String? product})> resolveNames(int vid, int pid) async {
    final vendor = await getVendorName(vid);
    final product = await getProductName(vid, pid);
    return (vendor: vendor, product: product);
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

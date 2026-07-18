import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/inventory_item.dart';

class LocalDb {
  LocalDb._();
  static final LocalDb instance = LocalDb._();
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final path = join(await getDatabasesPath(), 'gokula_inventory.db');
    _db = await openDatabase(path, version: 1, onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE inventory(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          client_uid TEXT NOT NULL UNIQUE,
          cloud_id INTEGER,
          tile_name TEXT NOT NULL,
          size TEXT NOT NULL,
          texture TEXT NOT NULL,
          stock INTEGER NOT NULL DEFAULT 0,
          price REAL NOT NULL DEFAULT 0,
          hsn_code TEXT DEFAULT '6907',
          image_url TEXT DEFAULT '',
          local_image TEXT DEFAULT '',
          sync_state TEXT NOT NULL DEFAULT 'pending',
          deleted INTEGER NOT NULL DEFAULT 0,
          updated_at TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE app_meta(
          key TEXT PRIMARY KEY,
          value TEXT
        )
      ''');
    });
    return _db!;
  }

  Future<List<InventoryItem>> inventory() async {
    final db = await database;
    final rows = await db.query('inventory', where: 'deleted=0', orderBy: 'tile_name');
    return rows.map(InventoryItem.fromMap).toList();
  }

  Future<void> saveInventory(InventoryItem item) async {
    final db = await database;
    await db.insert('inventory', item.toLocalMap()..remove('id'), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateInventory(InventoryItem item) async {
    final db = await database;
    await db.update('inventory', item.toLocalMap()..remove('id'), where: 'id=?', whereArgs: [item.id]);
  }

  Future<List<InventoryItem>> pendingInventory() async {
    final db = await database;
    final rows = await db.query('inventory', where: "sync_state='pending'");
    return rows.map(InventoryItem.fromMap).toList();
  }

  Future<int> pendingCount() async {
    final db = await database;
    final result = await db.rawQuery("SELECT COUNT(*) AS c FROM inventory WHERE sync_state='pending'");
    return (result.first['c'] as int?) ?? 0;
  }

  Future<void> markSynced(int id, int? cloudId, {String? imageUrl}) async {
    final db = await database;
    await db.update('inventory', {
      'cloud_id': cloudId,
      'image_url': imageUrl ?? '',
      'sync_state': 'synced',
    }, where: 'id=?', whereArgs: [id]);
  }

  Future<void> upsertCloud(Map<String, dynamic> cloud) async {
    final db = await database;
    final uid = (cloud['client_uid'] ?? 'cloud-${cloud['id']}').toString();
    final existing = await db.query('inventory', where: 'client_uid=?', whereArgs: [uid], limit: 1);
    final values = {
      'client_uid': uid,
      'cloud_id': cloud['id'],
      'tile_name': cloud['tile_name'] ?? '',
      'size': cloud['size'] ?? '',
      'texture': cloud['texture'] ?? '',
      'stock': cloud['stock'] ?? 0,
      'price': cloud['price'] ?? 0,
      'hsn_code': cloud['hsn_code'] ?? '6907',
      'image_url': cloud['image_url'] ?? '',
      'local_image': '',
      'sync_state': 'synced',
      'deleted': 0,
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (existing.isEmpty) {
      await db.insert('inventory', values, conflictAlgorithm: ConflictAlgorithm.ignore);
    } else if ((existing.first['sync_state'] ?? '') != 'pending') {
      await db.update('inventory', values, where: 'client_uid=?', whereArgs: [uid]);
    }
  }

  Future<void> setLastSync(String value) async {
    final db = await database;
    await db.insert('app_meta', {'key': 'last_sync', 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String> getLastSync() async {
    final db = await database;
    final rows = await db.query('app_meta', where: 'key=?', whereArgs: ['last_sync'], limit: 1);
    return rows.isEmpty ? 'Never' : (rows.first['value'] as String? ?? 'Never');
  }
}

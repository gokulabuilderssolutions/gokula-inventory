import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/customer.dart';
import '../models/inventory_item.dart';
import '../models/master_option.dart';
import '../models/sale.dart';

class LocalDb {
  LocalDb._();
  static final LocalDb instance = LocalDb._();
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final path = join(await getDatabasesPath(), 'gokula_inventory.db');
    _db = await openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async {
        await _createInventory(db);
        await _createSales(db);
        await _createMasters(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _createSales(db);
        if (oldVersion < 3) await _createMasters(db);
      },
    );
    return _db!;
  }

  Future<void> _createInventory(Database db) async {
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
    await db.execute('CREATE TABLE app_meta(key TEXT PRIMARY KEY, value TEXT)');
  }

  Future<void> _createSales(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS customers(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT DEFAULT '',
        address TEXT DEFAULT '',
        gstin TEXT DEFAULT ''
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sales(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_no TEXT NOT NULL UNIQUE,
        customer_id INTEGER,
        customer_name TEXT NOT NULL,
        subtotal REAL NOT NULL,
        gst_percent REAL NOT NULL,
        gst_amount REAL NOT NULL,
        grand_total REAL NOT NULL,
        payment_mode TEXT NOT NULL,
        created_at TEXT NOT NULL,
        sync_state TEXT NOT NULL DEFAULT 'pending'
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sale_lines(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL,
        inventory_id INTEGER NOT NULL,
        tile_name TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        unit_price REAL NOT NULL,
        line_total REAL NOT NULL,
        FOREIGN KEY(sale_id) REFERENCES sales(id) ON DELETE CASCADE
      )
    ''');
  }


  Future<void> _createMasters(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS master_options(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        value TEXT NOT NULL,
        category TEXT NOT NULL DEFAULT 'General',
        favorite INTEGER NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0,
        UNIQUE(type, value)
      )
    ''');
    final count = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM master_options')) ?? 0;
    if (count == 0) {
      const sizes = [
        ['2×2', 'Floor Tiles'], ['2×4', 'Wall Tiles'], ['4×2', 'Wall Tiles'],
        ['4×4', 'Floor Tiles'], ['6×4', 'Floor Tiles'], ['4×3.5', 'Parking Tiles'],
        ['12×18', 'Wall Tiles'], ['18×16', 'Wall Tiles'], ['16×16', 'Floor Tiles'],
        ['1×1', 'Mosaic Tiles'],
      ];
      const finishes = ['Glossy', 'Matt', 'Punch', 'Velvet', 'High Glossy', 'Sugar', 'Carving', 'Rocker'];
      for (var i = 0; i < sizes.length; i++) {
        await db.insert('master_options', {'type': 'size', 'value': sizes[i][0], 'category': sizes[i][1], 'favorite': i < 3 ? 1 : 0, 'sort_order': i});
      }
      for (var i = 0; i < finishes.length; i++) {
        await db.insert('master_options', {'type': 'texture', 'value': finishes[i], 'category': 'Finish', 'favorite': i < 3 ? 1 : 0, 'sort_order': i});
      }
    }
  }

  Future<List<MasterOption>> masterOptions(String type) async {
    final db = await database;
    final rows = await db.query('master_options', where: 'type=?', whereArgs: [type], orderBy: 'favorite DESC, category COLLATE NOCASE, sort_order, value COLLATE NOCASE');
    return rows.map(MasterOption.fromMap).toList();
  }

  Future<int> saveMasterOption(MasterOption option) async {
    final db = await database;
    final map = option.toMap()..remove('id');
    if (option.id == null) return db.insert('master_options', map, conflictAlgorithm: ConflictAlgorithm.abort);
    await db.update('master_options', map, where: 'id=?', whereArgs: [option.id]);
    return option.id!;
  }

  Future<int> masterUsageCount(MasterOption option) async {
    final db = await database;
    final column = option.type == 'size' ? 'size' : 'texture';
    return Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM inventory WHERE deleted=0 AND $column=?', [option.value])) ?? 0;
  }

  Future<void> deleteMasterOption(MasterOption option) async {
    if (option.id == null) return;
    final used = await masterUsageCount(option);
    if (used > 0) throw StateError('This value is used by $used inventory item(s).');
    final db = await database;
    await db.delete('master_options', where: 'id=?', whereArgs: [option.id]);
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
    final inv = Sqflite.firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM inventory WHERE sync_state='pending'")) ?? 0;
    final sales = Sqflite.firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM sales WHERE sync_state='pending'")) ?? 0;
    return inv + sales;
  }

  Future<void> markSynced(int id, int? cloudId, {String? imageUrl}) async {
    final db = await database;
    await db.update('inventory', {'cloud_id': cloudId, 'image_url': imageUrl ?? '', 'sync_state': 'synced'}, where: 'id=?', whereArgs: [id]);
  }

  Future<void> upsertCloud(Map<String, dynamic> cloud, {String? cachedLocalImage}) async {
    final db = await database;
    final uid = (cloud['client_uid'] ?? 'cloud-${cloud['id']}').toString();
    final existing = await db.query('inventory', where: 'client_uid=?', whereArgs: [uid], limit: 1);
    final preservedLocalImage = cachedLocalImage ?? (existing.isEmpty ? '' : (existing.first['local_image'] ?? '').toString());
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
      'local_image': preservedLocalImage,
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


  Future<void> deleteInventory(InventoryItem item) async {
    if (item.id == null) return;
    final db = await database;
    await db.update('inventory', {
      'deleted': 1,
      'sync_state': 'pending',
      'updated_at': DateTime.now().toIso8601String(),
    }, where: 'id=?', whereArgs: [item.id]);
  }

  Future<InventoryItem?> inventoryById(int id) async {
    final db = await database;
    final rows = await db.query('inventory', where: 'id=?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : InventoryItem.fromMap(rows.first);
  }

  Future<void> upsertCloudSale(Map<String, dynamic> cloud) async {
    final db = await database;
    await db.transaction((txn) async {
      final invoiceNo = (cloud['invoice_no'] ?? '').toString();
      if (invoiceNo.isEmpty) return;
      final existing = await txn.query('sales', where: 'invoice_no=?', whereArgs: [invoiceNo], limit: 1);
      if (existing.isNotEmpty && (existing.first['sync_state'] ?? '') == 'pending') return;

      final customerName = (cloud['customer_name'] ?? 'Walk-in Customer').toString();
      int? customerId;
      if (customerName.isNotEmpty && customerName != 'Walk-in Customer') {
        final customerRows = await txn.query('customers', where: 'name=?', whereArgs: [customerName], limit: 1);
        customerId = customerRows.isEmpty
            ? await txn.insert('customers', {'name': customerName, 'phone': '', 'address': '', 'gstin': ''})
            : customerRows.first['id'] as int?;
      }
      final values = {
        'invoice_no': invoiceNo,
        'customer_id': customerId,
        'customer_name': customerName,
        'subtotal': (cloud['subtotal'] as num?)?.toDouble() ?? 0,
        'gst_percent': (cloud['gst_percent'] as num?)?.toDouble() ?? 0,
        'gst_amount': (cloud['gst_amount'] as num?)?.toDouble() ?? 0,
        'grand_total': (cloud['grand_total'] as num?)?.toDouble() ?? 0,
        'payment_mode': (cloud['payment_mode'] ?? 'Cash').toString(),
        'created_at': (cloud['created_at'] ?? DateTime.now().toIso8601String()).toString(),
        'sync_state': 'synced',
      };
      int saleId;
      if (existing.isEmpty) {
        saleId = await txn.insert('sales', values);
      } else {
        saleId = existing.first['id'] as int;
        await txn.update('sales', values, where: 'id=?', whereArgs: [saleId]);
        await txn.delete('sale_lines', where: 'sale_id=?', whereArgs: [saleId]);
      }
      final rawLines = cloud['lines'];
      if (rawLines is List) {
        for (final raw in rawLines) {
          if (raw is! Map) continue;
          final line = Map<String, dynamic>.from(raw);
          int? inventoryId;
          final uid = (line['inventory_client_uid'] ?? '').toString();
          if (uid.isNotEmpty) {
            final inv = await txn.query('inventory', where: 'client_uid=?', whereArgs: [uid], limit: 1);
            if (inv.isNotEmpty) inventoryId = inv.first['id'] as int?;
          }
          if (inventoryId == null) {
            final inv = await txn.query('inventory', where: 'tile_name=? AND deleted=0', whereArgs: [(line['tile_name'] ?? '').toString()], limit: 1);
            if (inv.isNotEmpty) inventoryId = inv.first['id'] as int?;
          }
          if (inventoryId == null) continue;
          await txn.insert('sale_lines', {
            'sale_id': saleId,
            'inventory_id': inventoryId,
            'tile_name': (line['tile_name'] ?? '').toString(),
            'quantity': (line['quantity'] as num?)?.toInt() ?? 0,
            'unit_price': (line['unit_price'] as num?)?.toDouble() ?? 0,
            'line_total': (line['line_total'] as num?)?.toDouble() ?? 0,
          });
        }
      }
    });
  }

  Future<List<Customer>> customers() async {
    final db = await database;
    final rows = await db.query('customers', orderBy: 'name');
    return rows.map(Customer.fromMap).toList();
  }

  Future<int> saveCustomer(Customer customer) async {
    final db = await database;
    return db.insert('customers', customer.toMap()..remove('id'));
  }

  Future<String> nextInvoiceNo() async {
    final db = await database;
    final count = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM sales')) ?? 0;
    final now = DateTime.now();
    final date = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    return 'GOK/$date/${(count + 1).toString().padLeft(4, '0')}';
  }

  Future<int> createSale({
    required Sale sale,
    required List<SaleLine> lines,
  }) async {
    final db = await database;
    return db.transaction((txn) async {
      for (final line in lines) {
        final rows = await txn.query('inventory', columns: ['stock'], where: 'id=? AND deleted=0', whereArgs: [line.inventoryId], limit: 1);
        if (rows.isEmpty) throw StateError('${line.tileName} is no longer available');
        final stock = (rows.first['stock'] as num).toInt();
        if (line.quantity <= 0 || line.quantity > stock) throw StateError('Insufficient stock for ${line.tileName}. Available: $stock');
      }
      final saleId = await txn.insert('sales', {
        'invoice_no': sale.invoiceNo,
        'customer_id': sale.customerId,
        'customer_name': sale.customerName,
        'subtotal': sale.subtotal,
        'gst_percent': sale.gstPercent,
        'gst_amount': sale.gstAmount,
        'grand_total': sale.grandTotal,
        'payment_mode': sale.paymentMode,
        'created_at': sale.createdAt,
        'sync_state': 'pending',
      });
      for (final line in lines) {
        await txn.insert('sale_lines', {
          'sale_id': saleId,
          'inventory_id': line.inventoryId,
          'tile_name': line.tileName,
          'quantity': line.quantity,
          'unit_price': line.unitPrice,
          'line_total': line.lineTotal,
        });
        await txn.rawUpdate('''
          UPDATE inventory
          SET stock = stock - ?, sync_state='pending', updated_at=?
          WHERE id=?
        ''', [line.quantity, DateTime.now().toIso8601String(), line.inventoryId]);
      }
      return saleId;
    });
  }

  Future<void> updateSale({
    required Sale sale,
    required List<SaleLine> lines,
  }) async {
    if (sale.id == null) throw ArgumentError('Sale ID is required');
    final db = await database;
    await db.transaction((txn) async {
      final oldLines = await txn.query('sale_lines', where: 'sale_id=?', whereArgs: [sale.id]);

      for (final old in oldLines) {
        await txn.rawUpdate('''
          UPDATE inventory
          SET stock = stock + ?, sync_state='pending', updated_at=?
          WHERE id=?
        ''', [old['quantity'], DateTime.now().toIso8601String(), old['inventory_id']]);
      }

      for (final line in lines) {
        final rows = await txn.query('inventory', columns: ['stock'], where: 'id=? AND deleted=0', whereArgs: [line.inventoryId], limit: 1);
        if (rows.isEmpty) throw StateError('${line.tileName} is no longer available');
        final stock = (rows.first['stock'] as num).toInt();
        if (line.quantity <= 0 || line.quantity > stock) {
          throw StateError('Insufficient stock for ${line.tileName}. Available: $stock');
        }
      }

      await txn.update('sales', {
        'customer_id': sale.customerId,
        'customer_name': sale.customerName,
        'subtotal': sale.subtotal,
        'gst_percent': sale.gstPercent,
        'gst_amount': sale.gstAmount,
        'grand_total': sale.grandTotal,
        'payment_mode': sale.paymentMode,
        'created_at': sale.createdAt,
        'sync_state': 'pending',
      }, where: 'id=?', whereArgs: [sale.id]);

      await txn.delete('sale_lines', where: 'sale_id=?', whereArgs: [sale.id]);
      for (final line in lines) {
        await txn.insert('sale_lines', {
          'sale_id': sale.id,
          'inventory_id': line.inventoryId,
          'tile_name': line.tileName,
          'quantity': line.quantity,
          'unit_price': line.unitPrice,
          'line_total': line.lineTotal,
        });
        await txn.rawUpdate('''
          UPDATE inventory
          SET stock = stock - ?, sync_state='pending', updated_at=?
          WHERE id=?
        ''', [line.quantity, DateTime.now().toIso8601String(), line.inventoryId]);
      }
    });
  }

  Future<List<Sale>> sales() async {
    final db = await database;
    final rows = await db.query('sales', orderBy: 'created_at DESC');
    return rows.map(Sale.fromMap).toList();
  }

  Future<Sale?> saleById(int id) async {
    final db = await database;
    final rows = await db.query('sales', where: 'id=?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Sale.fromMap(rows.first);
  }

  Future<List<SaleLine>> saleLines(int saleId) async {
    final db = await database;
    final rows = await db.query('sale_lines', where: 'sale_id=?', whereArgs: [saleId], orderBy: 'id');
    return rows.map(SaleLine.fromMap).toList();
  }

  Future<List<Map<String, Object?>>> pendingSalesWithLines() async {
    final db = await database;
    final sales = await db.query('sales', where: "sync_state='pending'", orderBy: 'id');
    final result = <Map<String, Object?>>[];
    for (final sale in sales) {
      final lines = await db.query('sale_lines', where: 'sale_id=?', whereArgs: [sale['id']]);
      result.add({'sale': sale, 'lines': lines});
    }
    return result;
  }

  Future<void> markSaleSynced(int id) async {
    final db = await database;
    await db.update('sales', {'sync_state': 'synced'}, where: 'id=?', whereArgs: [id]);
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

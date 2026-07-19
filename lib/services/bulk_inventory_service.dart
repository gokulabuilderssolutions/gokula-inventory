import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:excel/excel.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../models/inventory_item.dart';
import 'image_storage_service.dart';
import 'local_db.dart';

class BulkImportResult {
  final int added;
  final int updated;
  final int skipped;
  final List<String> errors;

  const BulkImportResult({
    required this.added,
    required this.updated,
    required this.skipped,
    required this.errors,
  });
}

class BulkImageResult {
  final int matched;
  final List<String> unmatched;

  const BulkImageResult({required this.matched, required this.unmatched});
}

class BulkInventoryService {
  BulkInventoryService._();

  static const headers = <String>[
    'client_uid',
    'tile_name',
    'size',
    'finish_texture',
    'stock',
    'price',
    'hsn_code',
    'image_file_name',
  ];

  static String _cellText(Data? cell) => cell?.value?.toString().trim() ?? '';

  static String normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'\.[a-z0-9]{2,5}$'), '')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '');

  static Future<File> createTemplate() async {
    final book = Excel.createExcel();
    final sheet = book['Inventory'];
    if (book.tables.containsKey('Sheet1')) book.delete('Sheet1');

    sheet.appendRow(headers.map(TextCellValue.new).toList());
    sheet.appendRow([
      TextCellValue(''),
      TextCellValue('Sample Wall Tile'),
      TextCellValue('12×18'),
      TextCellValue('Glossy'),
      const IntCellValue(25),
      const DoubleCellValue(120.00),
      TextCellValue('6907'),
      TextCellValue('sample_wall_tile.jpg'),
    ]);
    sheet.appendRow([
      TextCellValue(''),
      TextCellValue('Sample Floor Tile'),
      TextCellValue('2×2'),
      TextCellValue('Matt'),
      const IntCellValue(40),
      const DoubleCellValue(95.00),
      TextCellValue('6907'),
      TextCellValue('sample_floor_tile.png'),
    ]);

    sheet.setColumnWidth(0, 38);
    sheet.setColumnWidth(1, 28);
    sheet.setColumnWidth(2, 14);
    sheet.setColumnWidth(3, 20);
    sheet.setColumnWidth(4, 12);
    sheet.setColumnWidth(5, 12);
    sheet.setColumnWidth(6, 14);
    sheet.setColumnWidth(7, 30);

    final notes = book['Instructions'];
    notes.appendRow([TextCellValue('Gokula Inventory Bulk Upload Instructions')]);
    notes.appendRow([TextCellValue('1. Do not change the column headings in the Inventory sheet.')]);
    notes.appendRow([TextCellValue('2. tile_name, size and finish_texture are required.')]);
    notes.appendRow([TextCellValue('3. stock must be a whole number and price may contain decimals.')]);
    notes.appendRow([TextCellValue('4. Keep client_uid blank for new products. The app creates it automatically.')]);
    notes.appendRow([TextCellValue('5. For image matching, enter the exact image filename, for example tile101.jpg.')]);
    notes.appendRow([TextCellValue('6. After importing the Excel file, use Bulk Images and select all product photos together.')]);
    notes.appendRow([TextCellValue('7. Existing rows are updated when client_uid matches. Otherwise a matching tile name + size + finish is updated.')]);

    final bytes = book.encode();
    if (bytes == null) throw StateError('Could not create Excel template.');
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'Gokula_Inventory_Bulk_Template.xlsx'));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static Future<void> shareTemplate() async {
    final file = await createTemplate();
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')],
      subject: 'Gokula Inventory Excel Template',
      text: 'Save this Excel template, fill the inventory data, and upload it from Inventory > Bulk Upload.',
    );
  }

  static Future<BulkImportResult> importExcel(Uint8List bytes) async {
    final book = Excel.decodeBytes(bytes);
    final sheet = book.tables['Inventory'] ?? (book.tables.isEmpty ? null : book.tables.values.first);
    if (sheet == null || sheet.rows.isEmpty) {
      throw const FormatException('The Excel file does not contain inventory rows.');
    }

    final first = sheet.rows.first;
    final column = <String, int>{};
    for (var i = 0; i < first.length; i++) {
      final key = _cellText(first[i]).toLowerCase().replaceAll(' ', '_');
      column[key] = i;
    }

    String at(List<Data?> row, String name) {
      final index = column[name];
      if (index == null || index >= row.length) return '';
      return _cellText(row[index]);
    }

    for (final required in ['tile_name', 'size', 'finish_texture']) {
      if (!column.containsKey(required)) {
        throw FormatException('Required column "$required" is missing. Please use the downloaded template.');
      }
    }

    var added = 0;
    var updated = 0;
    var skipped = 0;
    final errors = <String>[];

    for (var rowIndex = 1; rowIndex < sheet.rows.length; rowIndex++) {
      final row = sheet.rows[rowIndex];
      final tileName = at(row, 'tile_name');
      final size = at(row, 'size');
      final texture = at(row, 'finish_texture');
      final uidFromFile = at(row, 'client_uid');
      final imageFileName = at(row, 'image_file_name');

      if ([tileName, size, texture, at(row, 'stock'), at(row, 'price')].every((e) => e.isEmpty)) continue;
      if (tileName.isEmpty || size.isEmpty || texture.isEmpty) {
        skipped++;
        errors.add('Row ${rowIndex + 1}: tile name, size and finish are required.');
        continue;
      }

      final stockText = at(row, 'stock');
      final priceText = at(row, 'price');
      final stock = int.tryParse(stockText.replaceAll(',', ''));
      final price = double.tryParse(priceText.replaceAll(',', ''));
      if (stockText.isNotEmpty && stock == null) {
        skipped++;
        errors.add('Row ${rowIndex + 1}: invalid stock "$stockText".');
        continue;
      }
      if (priceText.isNotEmpty && price == null) {
        skipped++;
        errors.add('Row ${rowIndex + 1}: invalid price "$priceText".');
        continue;
      }

      final existing = await LocalDb.instance.findInventoryForBulk(
        clientUid: uidFromFile,
        tileName: tileName,
        size: size,
        texture: texture,
      );
      final uid = existing?.clientUid ?? (uidFromFile.isEmpty ? const Uuid().v4() : uidFromFile);
      final now = DateTime.now().toIso8601String();
      final item = InventoryItem(
        id: existing?.id,
        clientUid: uid,
        cloudId: existing?.cloudId,
        tileName: tileName,
        size: size,
        texture: texture,
        stock: stock ?? 0,
        price: price ?? 0,
        hsnCode: at(row, 'hsn_code').isEmpty ? (existing?.hsnCode ?? '6907') : at(row, 'hsn_code'),
        imageUrl: existing?.imageUrl ?? '',
        localImage: existing?.localImage ?? '',
        syncState: 'pending',
        deleted: false,
        updatedAt: now,
      );

      if (existing == null) {
        await LocalDb.instance.saveInventory(item);
        added++;
      } else {
        await LocalDb.instance.updateInventory(item);
        updated++;
      }
      if (imageFileName.isNotEmpty) {
        await LocalDb.instance.setBulkImageName(uid, imageFileName);
      }
    }

    return BulkImportResult(added: added, updated: updated, skipped: skipped, errors: errors);
  }

  static Future<BulkImageResult> attachImages(List<String> paths) async {
    final items = await LocalDb.instance.inventory();
    final imageNames = await LocalDb.instance.bulkImageNames();
    final byKey = <String, InventoryItem>{};
    for (final item in items) {
      byKey[normalize(item.clientUid)] = item;
      byKey[normalize(item.tileName)] = item;
      final mappedName = imageNames[item.clientUid] ?? '';
      if (mappedName.isNotEmpty) byKey[normalize(mappedName)] = item;
    }

    var matched = 0;
    final unmatched = <String>[];
    for (final path in paths) {
      final fileName = p.basename(path);
      final item = byKey[normalize(fileName)];
      if (item == null) {
        unmatched.add(fileName);
        continue;
      }
      final persistent = await ImageStorageService.persistPickedImage(sourcePath: path, clientUid: item.clientUid);
      if (persistent.isEmpty) {
        unmatched.add(fileName);
        continue;
      }
      await LocalDb.instance.updateInventory(InventoryItem(
        id: item.id,
        clientUid: item.clientUid,
        cloudId: item.cloudId,
        tileName: item.tileName,
        size: item.size,
        texture: item.texture,
        stock: item.stock,
        price: item.price,
        hsnCode: item.hsnCode,
        imageUrl: '',
        localImage: persistent,
        syncState: 'pending',
        deleted: item.deleted,
        updatedAt: DateTime.now().toIso8601String(),
      ));
      await LocalDb.instance.setBulkImageName(item.clientUid, '');
      matched++;
    }
    return BulkImageResult(matched: matched, unmatched: unmatched);
  }
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:printing/printing.dart';
import '../models/inventory_item.dart';
import '../services/local_db.dart';
import '../services/stock_report_service.dart';
import '../services/image_storage_service.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  List<InventoryItem> items = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    items = await LocalDb.instance.inventory();
    if (mounted) setState(() => loading = false);
  }


  Future<void> exportImageWiseReport() async {
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No inventory available to export.')));
      return;
    }
    try {
      final file = await StockReportService.createImageWiseReport(items);
      await Printing.sharePdf(bytes: await file.readAsBytes(), filename: 'Gokula_Image_Wise_Stock_Report.pdf');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not create report: $e')));
    }
  }

  Future<void> addItem() async {
    final name = TextEditingController();
    final size = TextEditingController();
    final texture = TextEditingController();
    final stock = TextEditingController();
    final price = TextEditingController();
    String imagePath = '';
    await showDialog<void>(context: context, builder: (context) => StatefulBuilder(builder: (context, setLocal) {
      return AlertDialog(
        title: const Text('Add Tile'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Tile name')),
          TextField(controller: size, decoration: const InputDecoration(labelText: 'Size')),
          TextField(controller: texture, decoration: const InputDecoration(labelText: 'Texture')),
          TextField(controller: stock, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Stock')),
          TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Price')),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: () async {
            final picked = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 80);
            if (picked != null) setLocal(() => imagePath = picked.path);
          }, icon: const Icon(Icons.camera_alt), label: Text(imagePath.isEmpty ? 'Take photo' : 'Photo selected')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () async {
            if (name.text.trim().isEmpty) return;
            final clientUid = const Uuid().v4();
            final persistentImagePath = await ImageStorageService.persistPickedImage(
              sourcePath: imagePath,
              clientUid: clientUid,
            );
            await LocalDb.instance.saveInventory(InventoryItem(
              clientUid: clientUid,
              tileName: name.text.trim(),
              size: size.text.trim(),
              texture: texture.text.trim(),
              stock: int.tryParse(stock.text) ?? 0,
              price: double.tryParse(price.text) ?? 0,
              hsnCode: '6907',
              localImage: persistentImagePath,
              updatedAt: DateTime.now().toIso8601String(),
            ));
            if (context.mounted) Navigator.pop(context);
          }, child: const Text('Save Offline')),
        ],
      );
    }));
    await load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inventory'), actions: [IconButton(onPressed: exportImageWiseReport, tooltip: 'Export image-wise report', icon: const Icon(Icons.picture_as_pdf))]),
      floatingActionButton: FloatingActionButton.extended(onPressed: addItem, icon: const Icon(Icons.add), label: const Text('Add Tile')),
      body: loading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(onRefresh: load, child: ListView.builder(
        padding: const EdgeInsets.all(12), itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return Card(child: ListTile(
            leading: _InventoryImage(item: item),
            title: Text(item.tileName, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${item.size} • ${item.texture}\nStock: ${item.stock}  Price: ₹${item.price.toStringAsFixed(2)}'),
            trailing: Chip(label: Text(item.syncState)),
            isThreeLine: true,
          ));
        },
      )),
    );
  }
}


class _InventoryImage extends StatelessWidget {
  final InventoryItem item;
  const _InventoryImage({required this.item});

  @override
  Widget build(BuildContext context) {
    final localFile = item.localImage.isEmpty ? null : File(item.localImage);
    if (localFile != null && localFile.existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(localFile, width: 58, height: 58, fit: BoxFit.cover),
      );
    }
    if (item.imageUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          item.imageUrl,
          width: 58,
          height: 58,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const CircleAvatar(child: Icon(Icons.inventory_2)),
          loadingBuilder: (context, child, progress) => progress == null
              ? child
              : const SizedBox(width: 58, height: 58, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
        ),
      );
    }
    return const CircleAvatar(child: Icon(Icons.inventory_2));
  }
}

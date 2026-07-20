import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';
import 'package:uuid/uuid.dart';
import '../models/inventory_item.dart';
import '../models/master_option.dart';
import '../services/image_storage_service.dart';
import '../services/local_db.dart';
import '../services/stock_report_service.dart';
import 'master_data_screen.dart';
import 'bulk_inventory_screen.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  List<InventoryItem> items = [];
  bool loading = true;

  @override
  void initState() { super.initState(); load(); }

  Future<void> load() async {
    items = await LocalDb.instance.inventory();
    if (mounted) setState(() => loading = false);
  }

  Future<void> exportImageWiseReport() async {
    if (items.isEmpty) return;
    final file = await StockReportService.createImageWiseReport(items);
    await Printing.sharePdf(bytes: await file.readAsBytes(), filename: 'Gokula_Image_Wise_Stock_Report.pdf');
  }

  Future<String?> chooseMaster({required String type, String? current}) async {
    var options = await LocalDb.instance.masterOptions(type);
    final search = TextEditingController();
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(builder: (context, setLocal) {
        final q = search.text.trim().toLowerCase();
        final visible = options.where((e) => q.isEmpty || e.value.toLowerCase().contains(q) || e.category.toLowerCase().contains(q)).toList();
        return SafeArea(child: SizedBox(
          height: MediaQuery.of(context).size.height * .72,
          child: Column(children: [
            ListTile(title: Text('Select ${type == 'size' ? 'Size' : 'Finish'}', style: const TextStyle(fontWeight: FontWeight.bold)), trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context))),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: TextField(controller: search, onChanged: (_) => setLocal(() {}), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search', border: OutlineInputBorder()))),
            const SizedBox(height: 8),
            Expanded(child: ListView.builder(itemCount: visible.length + 1, itemBuilder: (_, index) {
              if (index == visible.length) {
                return ListTile(leading: const Icon(Icons.add_circle_outline), title: const Text('Other / Add new'), onTap: () async {
                  final added = await _quickAddMaster(type);
                  if (added != null && context.mounted) Navigator.pop(context, added);
                });
              }
              final option = visible[index];
              return ListTile(
                leading: Icon(option.favorite ? Icons.star : Icons.label_outline),
                title: Text(option.value),
                subtitle: Text(option.category),
                trailing: current == option.value ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, option.value),
              );
            })),
          ]),
        ));
      }),
    );
  }

  Future<String?> _quickAddMaster(String type) async {
    final value = TextEditingController();
    final category = TextEditingController(text: type == 'texture' ? 'Finish' : 'General');
    bool favorite = false;
    return showDialog<String>(context: context, builder: (context) => StatefulBuilder(builder: (_, setLocal) => AlertDialog(
      title: Text('Add ${type == 'size' ? 'Size' : 'Finish'}'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: value, autofocus: true, decoration: InputDecoration(labelText: type == 'size' ? 'Size (example: 12×18)' : 'Finish name')),
        TextField(controller: category, decoration: const InputDecoration(labelText: 'Category')),
        SwitchListTile(contentPadding: EdgeInsets.zero, value: favorite, onChanged: (v) => setLocal(() => favorite = v), title: const Text('Favourite')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () async {
          final text = value.text.trim();
          if (text.isEmpty) return;
          try {
            await LocalDb.instance.saveMasterOption(MasterOption(type: type, value: text, category: category.text.trim().isEmpty ? 'General' : category.text.trim(), favorite: favorite, sortOrder: 999));
            if (context.mounted) Navigator.pop(context, text);
          } catch (_) {
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This value already exists.')));
          }
        }, child: const Text('Add')),
      ],
    )));
  }

  Future<void> itemDialog([InventoryItem? item]) async {
    final name = TextEditingController(text: item?.tileName ?? '');
    final stock = TextEditingController(text: item?.stock.toString() ?? '');
    final price = TextEditingController(text: item == null ? '' : item.price.toStringAsFixed(2));
    String size = item?.size ?? '';
    String texture = item?.texture ?? '';
    String imagePath = item?.localImage ?? '';
    bool imageChanged = false;

    await showDialog<void>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, setLocal) => AlertDialog(
      title: Text(item == null ? 'Add Tile' : 'Edit Tile'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Tile name')),
        const SizedBox(height: 10),
        ListTile(contentPadding: EdgeInsets.zero, title: const Text('Size'), subtitle: Text(size.isEmpty ? 'Tap to select' : size), trailing: const Icon(Icons.arrow_drop_down), onTap: () async { final v = await chooseMaster(type: 'size', current: size); if (v != null) setLocal(() => size = v); }),
        ListTile(contentPadding: EdgeInsets.zero, title: const Text('Finish / Texture'), subtitle: Text(texture.isEmpty ? 'Tap to select' : texture), trailing: const Icon(Icons.arrow_drop_down), onTap: () async { final v = await chooseMaster(type: 'texture', current: texture); if (v != null) setLocal(() => texture = v); }),
        TextField(controller: stock, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Stock')),
        TextField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Price')),
        const SizedBox(height: 12),
        if (imagePath.isNotEmpty && File(imagePath).existsSync()) Image.file(File(imagePath), width: 120, height: 120, fit: BoxFit.cover)
        else if ((item?.imageUrl ?? '').isNotEmpty) Image.network(item!.imageUrl, width: 120, height: 120, fit: BoxFit.cover),
        Wrap(spacing: 8, children: [
          OutlinedButton.icon(onPressed: () async { final p = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 80); if (p != null) setLocal(() { imagePath = p.path; imageChanged = true; }); }, icon: const Icon(Icons.camera_alt), label: const Text('Camera')),
          OutlinedButton.icon(onPressed: () async { final p = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80); if (p != null) setLocal(() { imagePath = p.path; imageChanged = true; }); }, icon: const Icon(Icons.photo_library), label: const Text('Gallery')),
        ]),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () async {
          if (name.text.trim().isEmpty || size.isEmpty || texture.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter tile name, size and finish.')));
            return;
          }
          final uid = item?.clientUid ?? const Uuid().v4();
          var persistent = item?.localImage ?? '';
          if (imageChanged || (item == null && imagePath.isNotEmpty)) persistent = await ImageStorageService.persistPickedImage(sourcePath: imagePath, clientUid: uid);
          final value = InventoryItem(
            id: item?.id, clientUid: uid, cloudId: item?.cloudId, tileName: name.text.trim(), size: size, texture: texture,
            stock: int.tryParse(stock.text.trim()) ?? 0, price: double.tryParse(price.text.trim()) ?? 0, hsnCode: item?.hsnCode ?? '6907',
            imageUrl: imageChanged ? '' : (item?.imageUrl ?? ''), localImage: persistent, syncState: 'pending', deleted: item?.deleted ?? false,
            updatedAt: DateTime.now().toIso8601String(),
          );
          if (item == null) await LocalDb.instance.saveInventory(value); else await LocalDb.instance.updateInventory(value);
          if (context.mounted) Navigator.pop(context);
        }, child: Text(item == null ? 'Save Offline' : 'Save Changes')),
      ],
    )));
    await load();
  }

  Future<void> deleteItem(InventoryItem item) async {
    final ok = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('Delete inventory item?'), content: Text('Delete ${item.tileName}? Existing sales history will remain safe.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete'))]));
    if (ok == true) { await LocalDb.instance.deleteInventory(item); await load(); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Inventory'), actions: [
      IconButton(tooltip: 'Bulk inventory upload', icon: const Icon(Icons.upload_file), onPressed: () async { await Navigator.push(context, MaterialPageRoute(builder: (_) => const BulkInventoryScreen())); await load(); }),
      IconButton(tooltip: 'Manage sizes and finishes', icon: const Icon(Icons.tune), onPressed: () async { await Navigator.push(context, MaterialPageRoute(builder: (_) => const MasterDataScreen())); await load(); }),
      IconButton(onPressed: exportImageWiseReport, tooltip: 'Export image-wise report', icon: const Icon(Icons.picture_as_pdf)),
    ]),
    floatingActionButton: FloatingActionButton.extended(onPressed: () => itemDialog(), icon: const Icon(Icons.add), label: const Text('Add Tile')),
    body: loading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(onRefresh: load, child: ListView.builder(padding: const EdgeInsets.all(12), itemCount: items.length, itemBuilder: (_, index) {
      final item = items[index];
      return Card(child: ListTile(
        leading: _InventoryImage(item: item), title: Text(item.tileName, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${item.size} • ${item.texture}\nStock: ${item.stock}  Price: ₹${item.price.toStringAsFixed(2)}'), isThreeLine: true,
        onTap: () => itemDialog(item),
        trailing: PopupMenuButton<String>(onSelected: (v) { if (v == 'edit') itemDialog(item); if (v == 'delete') deleteItem(item); }, itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Text('Edit')), PopupMenuItem(value: 'delete', child: Text('Delete'))]),
      ));
    })),
  );
}

class _InventoryImage extends StatelessWidget {
  final InventoryItem item;
  const _InventoryImage({required this.item});
  @override
  Widget build(BuildContext context) {
    final file = item.localImage.isEmpty ? null : File(item.localImage);
    if (file != null && file.existsSync()) return ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(file, width: 58, height: 58, fit: BoxFit.cover));
    if (item.imageUrl.isNotEmpty) return ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(item.imageUrl, width: 58, height: 58, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const CircleAvatar(child: Icon(Icons.inventory_2))));
    return const CircleAvatar(child: Icon(Icons.inventory_2));
  }
}

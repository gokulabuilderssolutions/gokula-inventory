import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/bulk_inventory_service.dart';

class BulkInventoryScreen extends StatefulWidget {
  const BulkInventoryScreen({super.key});

  @override
  State<BulkInventoryScreen> createState() => _BulkInventoryScreenState();
}

class _BulkInventoryScreenState extends State<BulkInventoryScreen> {
  bool busy = false;
  String status = 'Download the template, fill it, and upload it here.';

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => status = 'Error: $error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> downloadTemplate() => run(() async {
        await BulkInventoryService.shareTemplate();
        if (mounted) setState(() => status = 'Template created. Choose Excel, Files, Drive, WhatsApp, or another app to save/share it.');
      });

  Future<void> uploadExcel() => run(() async {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['xlsx'],
          withData: true,
        );
        if (result == null) return;
        final picked = result.files.single;
        final bytes = picked.bytes ?? (picked.path == null ? null : await File(picked.path!).readAsBytes());
        if (bytes == null) throw StateError('Could not read the selected Excel file.');
        final imported = await BulkInventoryService.importExcel(bytes);
        final errorText = imported.errors.isEmpty
            ? ''
            : '\n${imported.errors.take(8).join('\n')}${imported.errors.length > 8 ? '\n…and ${imported.errors.length - 8} more.' : ''}';
        if (mounted) {
          setState(() => status = 'Excel upload completed. Added: ${imported.added}, Updated: ${imported.updated}, Skipped: ${imported.skipped}.$errorText');
        }
      });

  Future<void> uploadImages() => run(() async {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: true,
        );
        if (result == null) return;
        final paths = result.files.map((e) => e.path).whereType<String>().toList();
        if (paths.isEmpty) throw StateError('Could not access the selected images.');
        final attached = await BulkInventoryService.attachImages(paths);
        final unmatchedText = attached.unmatched.isEmpty
            ? ''
            : '\nUnmatched: ${attached.unmatched.take(12).join(', ')}${attached.unmatched.length > 12 ? '…' : ''}';
        if (mounted) setState(() => status = 'Bulk image upload completed. Matched: ${attached.matched}, Unmatched: ${attached.unmatched.length}.$unmatchedText');
      });

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Bulk Inventory Upload')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Step 1', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('Download the Excel template. Do not rename or remove its column headings.'),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: busy ? null : downloadTemplate,
              icon: const Icon(Icons.download),
              label: const Text('Download Excel Template'),
            ),
            const Divider(height: 36),
            const Text('Step 2', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('Fill tile name, size, finish, stock, price, HSN and image filename. Then upload the completed .xlsx file.'),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: busy ? null : uploadExcel,
              icon: const Icon(Icons.upload_file),
              label: const Text('Upload Inventory Excel'),
            ),
            const Divider(height: 36),
            const Text('Step 3', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('Select all product images together. Image names should match image_file_name in Excel. The app also tries to match the tile name or client UID.'),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: busy ? null : uploadImages,
              icon: const Icon(Icons.add_photo_alternate),
              label: const Text('Bulk Upload Images'),
            ),
            const SizedBox(height: 24),
            if (busy) const LinearProgressIndicator(),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: SelectableText(status),
              ),
            ),
          ],
        ),
      );
}

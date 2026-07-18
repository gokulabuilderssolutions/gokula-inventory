import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/inventory_item.dart';

class StockReportService {
  static Future<File> createImageWiseReport(List<InventoryItem> items) async {
    final document = pw.Document();
    final generated = DateFormat('dd-MM-yyyy hh:mm a').format(DateTime.now());
    final rows = <_ReportRow>[];

    for (final item in items) {
      pw.ImageProvider? image;
      try {
        if (item.localImage.isNotEmpty && File(item.localImage).existsSync()) {
          final bytes = await File(item.localImage).readAsBytes();
          image = pw.MemoryImage(bytes);
        } else if (item.imageUrl.isNotEmpty) {
          image = await networkImage(item.imageUrl);
        }
      } catch (_) {
        image = null;
      }
      rows.add(_ReportRow(item, image));
    }

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Gokula Ceramics', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.Text('Image-wise Stock Report', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.Text('Generated: $generated', style: const pw.TextStyle(fontSize: 9)),
            pw.SizedBox(height: 8),
            pw.Divider(),
          ],
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Page ${context.pageNumber} of ${context.pagesCount}', style: const pw.TextStyle(fontSize: 8)),
        ),
        build: (context) => [
          pw.Text('Total products: ${items.length}    Total stock: ${items.fold<int>(0, (sum, e) => sum + e.stock)}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 12),
          ...rows.map((row) => pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 10),
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400), borderRadius: pw.BorderRadius.circular(4)),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(
                      width: 90,
                      height: 80,
                      alignment: pw.Alignment.center,
                      decoration: pw.BoxDecoration(color: PdfColors.grey200, borderRadius: pw.BorderRadius.circular(3)),
                      child: row.image == null
                          ? pw.Text('No image', style: const pw.TextStyle(fontSize: 9))
                          : pw.Image(row.image!, fit: pw.BoxFit.cover),
                    ),
                    pw.SizedBox(width: 12),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(row.item.tileName, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
                          pw.SizedBox(height: 4),
                          pw.Text('Size: ${row.item.size.isEmpty ? '-' : row.item.size}'),
                          pw.Text('Texture: ${row.item.texture.isEmpty ? '-' : row.item.texture}'),
                          pw.Text('Available quantity: ${row.item.stock}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                          pw.Text('Price: Rs. ${row.item.price.toStringAsFixed(2)}'),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );

    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/image_wise_stock_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(await document.save());
    return file;
  }
}

class _ReportRow {
  final InventoryItem item;
  final pw.ImageProvider? image;
  const _ReportRow(this.item, this.image);
}

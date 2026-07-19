import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/inventory_item.dart';

class StockReportService {
  static Future<File> createImageWiseReport(List<InventoryItem> items) async {
    final document = pw.Document();
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

    rows.sort((a, b) {
      final sizeComparison = _compareSizes(a.item.size, b.item.size);
      if (sizeComparison != 0) return sizeComparison;
      return a.item.tileName.toLowerCase().compareTo(b.item.tileName.toLowerCase());
    });

    final groupedRows = <String, List<_ReportRow>>{};
    for (final row in rows) {
      final size = row.item.size.trim().isEmpty ? 'Unspecified size' : row.item.size.trim();
      groupedRows.putIfAbsent(size, () => <_ReportRow>[]).add(row);
    }

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Gokula Ceramics', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.Text('Tile Selection Catalogue', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Divider(),
          ],
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Page ${context.pageNumber} of ${context.pagesCount}', style: const pw.TextStyle(fontSize: 8)),
        ),
        build: (context) => [
          for (final group in groupedRows.entries) ...[
            pw.Header(
              level: 1,
              margin: const pw.EdgeInsets.only(top: 4, bottom: 8),
              child: pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                color: PdfColors.blueGrey100,
                child: pw.Text(
                  'Size: ${group.key}',
                  style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
                ),
              ),
            ),
            ..._buildProductRows(group.value),
            pw.SizedBox(height: 10),
          ],
        ],
      ),
    );

    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/image_wise_stock_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(await document.save());
    return file;
  }

  static pw.Widget _buildProductCard(_ReportRow row) {
    return pw.Container(
      width: 264,
      padding: const pw.EdgeInsets.all(7),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: pw.BorderRadius.circular(5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 250,
            height: 180,
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(
              color: PdfColors.grey200,
              borderRadius: pw.BorderRadius.circular(3),
            ),
            child: row.image == null
                ? pw.Text('No image available', style: const pw.TextStyle(fontSize: 10))
                : pw.Image(row.image!, fit: pw.BoxFit.contain),
          ),
          pw.SizedBox(height: 7),
          pw.Text(
            row.item.tileName,
            maxLines: 2,
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 3),
          pw.Text('Type: ${row.item.texture.trim().isEmpty ? '-' : row.item.texture.trim()}'),
          pw.Text(
            'Quantity: ${row.item.stock}',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );
  }

  static List<pw.Widget> _buildProductRows(List<_ReportRow> rows) {
    final widgets = <pw.Widget>[];
    for (var index = 0; index < rows.length; index += 2) {
      widgets.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 10),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildProductCard(rows[index]),
              pw.SizedBox(width: 10),
              if (index + 1 < rows.length)
                _buildProductCard(rows[index + 1])
              else
                pw.SizedBox(width: 264),
            ],
          ),
        ),
      );
    }
    return widgets;
  }

  static int _compareSizes(String first, String second) {
    final firstParts = _sizeNumbers(first);
    final secondParts = _sizeNumbers(second);
    final length = firstParts.length > secondParts.length ? firstParts.length : secondParts.length;

    for (var index = 0; index < length; index++) {
      final firstValue = index < firstParts.length ? firstParts[index] : -1;
      final secondValue = index < secondParts.length ? secondParts[index] : -1;
      final comparison = firstValue.compareTo(secondValue);
      if (comparison != 0) return comparison;
    }
    return first.toLowerCase().compareTo(second.toLowerCase());
  }

  static List<double> _sizeNumbers(String value) {
    return RegExp(r'\d+(?:\.\d+)?')
        .allMatches(value)
        .map((match) => double.tryParse(match.group(0) ?? '') ?? 0)
        .toList();
  }
}

class _ReportRow {
  final InventoryItem item;
  final pw.ImageProvider? image;
  const _ReportRow(this.item, this.image);
}

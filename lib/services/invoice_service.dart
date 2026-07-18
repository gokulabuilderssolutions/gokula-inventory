import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/sale.dart';

class InvoiceService {
  static Future<File> createInvoice(Sale sale, List<SaleLine> lines) async {
    final pdf = pw.Document();
    final date = DateTime.tryParse(sale.createdAt) ?? DateTime.now();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (_) => [
          pw.Text('GOKULA INVENTORY', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text('Tax Invoice', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.Divider(),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text('Invoice: ${sale.invoiceNo}'),
            pw.Text('Date: ${DateFormat('dd-MM-yyyy HH:mm').format(date)}'),
          ]),
          pw.SizedBox(height: 8),
          pw.Text('Customer: ${sale.customerName}'),
          pw.Text('Payment: ${sale.paymentMode}'),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: const ['Item', 'Qty', 'Rate', 'Amount'],
            data: lines.map((e) => [e.tileName, '${e.quantity}', e.unitPrice.toStringAsFixed(2), e.lineTotal.toStringAsFixed(2)]).toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellAlignment: pw.Alignment.centerRight,
            cellAlignments: {0: pw.Alignment.centerLeft},
          ),
          pw.SizedBox(height: 14),
          pw.Align(alignment: pw.Alignment.centerRight, child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text('Subtotal: Rs. ${sale.subtotal.toStringAsFixed(2)}'),
            pw.Text('GST (${sale.gstPercent.toStringAsFixed(2)}%): Rs. ${sale.gstAmount.toStringAsFixed(2)}'),
            pw.SizedBox(height: 4),
            pw.Text('Grand Total: Rs. ${sale.grandTotal.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
          ])),
          pw.SizedBox(height: 30),
          pw.Text('Thank you for your business.'),
        ],
      ),
    );
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/${sale.invoiceNo.replaceAll('/', '-')}.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }
}

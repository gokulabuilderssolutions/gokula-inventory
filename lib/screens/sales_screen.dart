import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../models/customer.dart';
import '../models/inventory_item.dart';
import '../models/sale.dart';
import '../services/invoice_service.dart';
import '../services/local_db.dart';

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  List<Sale> sales = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    sales = await LocalDb.instance.sales();
    if (mounted) setState(() => loading = false);
  }

  Future<void> newSale() async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const NewSaleScreen()));
    if (saved == true) await load();
  }

  Future<void> openInvoice(Sale sale) async {
    if (sale.id == null) return;
    final lines = await LocalDb.instance.saleLines(sale.id!);
    final file = await InvoiceService.createInvoice(sale, lines);
    if (!mounted) return;
    await Printing.sharePdf(bytes: await file.readAsBytes(), filename: '${sale.invoiceNo.replaceAll('/', '-')}.pdf');
  }

  @override
  Widget build(BuildContext context) {
    final total = sales.fold<double>(0, (sum, sale) => sum + sale.grandTotal);
    return Scaffold(
      appBar: AppBar(title: const Text('Sales')),
      floatingActionButton: FloatingActionButton.extended(onPressed: newSale, icon: const Icon(Icons.add_shopping_cart), label: const Text('New Sale')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: load,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Total Sales', style: TextStyle(fontWeight: FontWeight.bold)),
                          Text('${sales.length} invoices'),
                        ]),
                        Text('₹${total.toStringAsFixed(2)}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                      ]),
                    ),
                  ),
                  if (sales.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 80),
                      child: Center(child: Text('No sales yet. Tap New Sale to create your first invoice.')),
                    )
                  else
                    ...sales.map((sale) {
                      final dt = DateTime.tryParse(sale.createdAt);
                      return Card(
                        child: ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.receipt_long)),
                          title: Text(sale.invoiceNo, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('${sale.customerName}\n${dt == null ? sale.createdAt : DateFormat('dd-MM-yyyy hh:mm a').format(dt)} • ${sale.paymentMode}'),
                          isThreeLine: true,
                          trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text('₹${sale.grandTotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                            Text(sale.syncState, style: Theme.of(context).textTheme.labelSmall),
                          ]),
                          onTap: () => openInvoice(sale),
                        ),
                      );
                    }),
                  const SizedBox(height: 90),
                ],
              ),
            ),
    );
  }
}

class _CartRow {
  final InventoryItem item;
  int quantity;
  double unitPrice;

  _CartRow(this.item, {this.quantity = 1, required this.unitPrice});
  double get total => quantity * unitPrice;
}

class NewSaleScreen extends StatefulWidget {
  const NewSaleScreen({super.key});

  @override
  State<NewSaleScreen> createState() => _NewSaleScreenState();
}

class _NewSaleScreenState extends State<NewSaleScreen> {
  List<InventoryItem> inventory = [];
  List<Customer> customers = [];
  final List<_CartRow> cart = [];
  Customer? customer;
  double gstPercent = 18;
  String paymentMode = 'Cash';
  bool loading = true;
  bool saving = false;

  double get subtotal => cart.fold(0, (sum, row) => sum + row.total);
  double get gstAmount => subtotal * gstPercent / 100;
  double get grandTotal => subtotal + gstAmount;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    inventory = (await LocalDb.instance.inventory()).where((e) => e.stock > 0 && e.id != null).toList();
    customers = await LocalDb.instance.customers();
    if (mounted) setState(() => loading = false);
  }

  Future<void> addCustomer() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final address = TextEditingController();
    final gstin = TextEditingController();
    final created = await showDialog<Customer>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Customer'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Customer name *')),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone')),
            TextField(controller: address, decoration: const InputDecoration(labelText: 'Address')),
            TextField(controller: gstin, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'GSTIN')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty) return;
              final newCustomer = Customer(name: name.text.trim(), phone: phone.text.trim(), address: address.text.trim(), gstin: gstin.text.trim());
              final id = await LocalDb.instance.saveCustomer(newCustomer);
              if (context.mounted) Navigator.pop(context, Customer(id: id, name: newCustomer.name, phone: newCustomer.phone, address: newCustomer.address, gstin: newCustomer.gstin));
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (created != null) {
      await load();
      Customer selected = created;
      for (final item in customers) {
        if (item.id == created.id) { selected = item; break; }
      }
      setState(() => customer = selected);
    }
  }

  Future<void> addProduct() async {
    final available = inventory.where((item) => !cart.any((row) => row.item.id == item.id)).toList();
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No more stock items available to add.')));
      return;
    }
    InventoryItem selected = available.first;
    final qty = TextEditingController(text: '1');
    final price = TextEditingController(text: selected.price.toStringAsFixed(2));
    final result = await showDialog<_CartRow>(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setLocal) {
        return AlertDialog(
          title: const Text('Add Product'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<InventoryItem>(
                initialValue: selected,
                decoration: const InputDecoration(labelText: 'Product'),
                items: available.map((item) => DropdownMenuItem(value: item, child: Text('${item.tileName} (Stock ${item.stock})'))).toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setLocal(() {
                    selected = value;
                    price.text = value.price.toStringAsFixed(2);
                    qty.text = '1';
                  });
                },
              ),
              TextField(controller: qty, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Quantity (available ${selected.stock})')),
              TextField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Selling price')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final q = int.tryParse(qty.text) ?? 0;
                final p = double.tryParse(price.text) ?? 0;
                if (q <= 0 || q > selected.stock || p < 0) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Enter quantity between 1 and ${selected.stock}.')));
                  return;
                }
                Navigator.pop(context, _CartRow(selected, quantity: q, unitPrice: p));
              },
              child: const Text('Add'),
            ),
          ],
        );
      }),
    );
    if (result != null) setState(() => cart.add(result));
  }

  Future<void> saveSale() async {
    if (cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add at least one product.')));
      return;
    }
    setState(() => saving = true);
    try {
      final invoiceNo = await LocalDb.instance.nextInvoiceNo();
      final createdAt = DateTime.now().toIso8601String();
      final sale = Sale(
        invoiceNo: invoiceNo,
        customerId: customer?.id,
        customerName: customer?.name ?? 'Walk-in Customer',
        subtotal: subtotal,
        gstPercent: gstPercent,
        gstAmount: gstAmount,
        grandTotal: grandTotal,
        paymentMode: paymentMode,
        createdAt: createdAt,
      );
      final lines = cart.map((row) => SaleLine(
            inventoryId: row.item.id!,
            tileName: row.item.tileName,
            quantity: row.quantity,
            unitPrice: row.unitPrice,
            lineTotal: row.total,
          )).toList();
      final id = await LocalDb.instance.createSale(sale: sale, lines: lines);
      final savedSale = Sale(
        id: id,
        invoiceNo: sale.invoiceNo,
        customerId: sale.customerId,
        customerName: sale.customerName,
        subtotal: sale.subtotal,
        gstPercent: sale.gstPercent,
        gstAmount: sale.gstAmount,
        grandTotal: sale.grandTotal,
        paymentMode: sale.paymentMode,
        createdAt: sale.createdAt,
      );
      final file = await InvoiceService.createInvoice(savedSale, lines);
      if (!mounted) return;
      await Printing.sharePdf(bytes: await file.readAsBytes(), filename: '${invoiceNo.replaceAll('/', '-')}.pdf');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save sale: $e')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: const Text('New Sale')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<Customer?>(
                      initialValue: customer,
                      decoration: const InputDecoration(labelText: 'Customer'),
                      items: [
                        const DropdownMenuItem<Customer?>(value: null, child: Text('Walk-in Customer')),
                        ...customers.map((e) => DropdownMenuItem<Customer?>(value: e, child: Text(e.name))),
                      ],
                      onChanged: (value) => setState(() => customer = value),
                    ),
                  ),
                  IconButton(onPressed: addCustomer, tooltip: 'Add customer', icon: const Icon(Icons.person_add)),
                ]),
                DropdownButtonFormField<String>(
                  initialValue: paymentMode,
                  decoration: const InputDecoration(labelText: 'Payment mode'),
                  items: const ['Cash', 'UPI', 'Card', 'Credit', 'Bank Transfer'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  onChanged: (value) => setState(() => paymentMode = value ?? 'Cash'),
                ),
                DropdownButtonFormField<double>(
                  initialValue: gstPercent,
                  decoration: const InputDecoration(labelText: 'GST'),
                  items: const [0.0, 5.0, 12.0, 18.0, 28.0].map((e) => DropdownMenuItem(value: e, child: Text('${e.toStringAsFixed(0)}%'))).toList(),
                  onChanged: (value) => setState(() => gstPercent = value ?? 18),
                ),
              ]),
            ),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Products', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            FilledButton.tonalIcon(onPressed: addProduct, icon: const Icon(Icons.add), label: const Text('Add Product')),
          ]),
          const SizedBox(height: 8),
          if (cart.isEmpty)
            const Card(child: Padding(padding: EdgeInsets.all(22), child: Center(child: Text('No products added'))))
          else
            ...cart.asMap().entries.map((entry) {
              final index = entry.key;
              final row = entry.value;
              return Card(
                child: ListTile(
                  title: Text(row.item.tileName, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('${row.quantity} × ₹${row.unitPrice.toStringAsFixed(2)}  •  Stock ${row.item.stock}'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('₹${row.total.toStringAsFixed(2)}'),
                    IconButton(onPressed: () => setState(() => cart.removeAt(index)), icon: const Icon(Icons.delete_outline)),
                  ]),
                ),
              );
            }),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                _totalRow('Subtotal', subtotal),
                _totalRow('GST (${gstPercent.toStringAsFixed(0)}%)', gstAmount),
                const Divider(),
                _totalRow('Grand Total', grandTotal, bold: true),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: saving ? null : saveSale,
              icon: saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
              label: Text(saving ? 'Saving...' : 'Save Sale & Create Invoice'),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _totalRow(String label, double amount, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: bold ? const TextStyle(fontWeight: FontWeight.bold, fontSize: 16) : null),
          Text('₹${amount.toStringAsFixed(2)}', style: bold ? const TextStyle(fontWeight: FontWeight.bold, fontSize: 16) : null),
        ]),
      );
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/sale.dart';
import '../services/local_db.dart';

class ReturnsScreen extends StatefulWidget {
  const ReturnsScreen({super.key});

  @override
  State<ReturnsScreen> createState() => _ReturnsScreenState();
}

class _ReturnsScreenState extends State<ReturnsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _qtyController = TextEditingController(text: '1');
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();

  List<Sale> _sales = [];
  List<Map<String, Object?>> _returnableLines = [];
  List<Map<String, Object?>> _history = [];

  String _searchMode = 'invoice';
  String? _selectedCustomer;
  Sale? _selectedSale;
  int? _selectedSaleLineId;

  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
    _searchController.addListener(_refreshSuggestions);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_refreshSuggestions)
      ..dispose();
    _qtyController.dispose();
    _priceController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  void _refreshSuggestions() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final sales = await LocalDb.instance.sales();
    final history = await LocalDb.instance.returnsHistory();
    if (!mounted) return;
    setState(() {
      _sales = sales;
      _history = history;
      _loading = false;
    });
  }

  List<String> get _suggestions {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return const [];

    final values = <String>{};
    if (_searchMode == 'invoice') {
      for (final sale in _sales) {
        if (sale.invoiceNo.toLowerCase().contains(q)) {
          values.add(sale.invoiceNo);
        }
      }
    } else {
      for (final sale in _sales) {
        if (sale.customerName.toLowerCase().contains(q)) {
          values.add(sale.customerName);
        }
      }
    }

    final list = values.toList();
    list.sort((a, b) {
      final aLower = a.toLowerCase();
      final bLower = b.toLowerCase();
      final aStarts = aLower.startsWith(q);
      final bStarts = bLower.startsWith(q);
      if (aStarts != bStarts) return aStarts ? -1 : 1;
      return aLower.compareTo(bLower);
    });
    return list.take(12).toList();
  }

  List<Sale> get _customerSales {
    final name = _selectedCustomer;
    if (name == null) return const [];
    return _sales.where((sale) => sale.customerName == name).toList();
  }

  Map<String, Object?>? get _selectedLine {
    final id = _selectedSaleLineId;
    if (id == null) return null;
    for (final line in _returnableLines) {
      if ((line['sale_line_id'] as num?)?.toInt() == id) return line;
    }
    return null;
  }

  int _asInt(Object? value) => (value as num?)?.toInt() ?? 0;
  double _asDouble(Object? value) => (value as num?)?.toDouble() ?? 0;

  Future<void> _chooseSuggestion(String value) async {
    _searchController.text = value;
    _searchController.selection =
        TextSelection.collapsed(offset: _searchController.text.length);

    if (_searchMode == 'invoice') {
      Sale? found;
      for (final sale in _sales) {
        if (sale.invoiceNo == value) {
          found = sale;
          break;
        }
      }
      if (found != null) await _selectSale(found);
    } else {
      setState(() {
        _selectedCustomer = value;
        _selectedSale = null;
        _returnableLines = [];
        _selectedSaleLineId = null;
        _priceController.clear();
      });

      final matches =
          _sales.where((sale) => sale.customerName == value).toList();
      if (matches.length == 1) {
        await _selectSale(matches.first);
      }
    }
  }

  Future<void> _selectSale(Sale sale) async {
    if (sale.id == null) return;
    final lines = await LocalDb.instance.returnableLinesForSale(sale.id!);
    if (!mounted) return;

    final availableLines = lines.where((line) {
      final sold = _asInt(line['sold_quantity']);
      final returned = _asInt(line['returned_quantity']);
      return sold - returned > 0;
    }).toList();

    setState(() {
      _selectedSale = sale;
      _selectedCustomer = sale.customerName;
      _returnableLines = availableLines;
      _selectedSaleLineId = null;
      _qtyController.text = '1';
      _priceController.clear();
    });
  }

  void _selectMaterial(int? saleLineId) {
    setState(() {
      _selectedSaleLineId = saleLineId;
      _qtyController.text = '1';

      final line = _selectedLine;
      if (line == null) {
        _priceController.clear();
      } else {
        _priceController.text =
            _asDouble(line['original_unit_price']).toStringAsFixed(2);
      }
    });
  }

  Future<void> _saveReturn() async {
    final sale = _selectedSale;
    final line = _selectedLine;
    if (sale == null || sale.id == null) {
      _showMessage('Select an invoice first.');
      return;
    }
    if (line == null) {
      _showMessage('Select a material to return.');
      return;
    }

    final sold = _asInt(line['sold_quantity']);
    final alreadyReturned = _asInt(line['returned_quantity']);
    final remaining = sold - alreadyReturned;
    final qty = int.tryParse(_qtyController.text.trim()) ?? 0;
    final price = double.tryParse(_priceController.text.trim()) ?? -1;

    if (qty <= 0) {
      _showMessage('Enter the number of boxes being returned.');
      return;
    }
    if (qty > remaining) {
      _showMessage('Maximum return quantity is $remaining box(es).');
      return;
    }
    if (price < 0) {
      _showMessage('Enter a valid return price.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm Return'),
        content: Text(
          '${line['tile_name']}\n'
          'Return: $qty box(es)\n'
          'Price: ₹${price.toStringAsFixed(2)} per box\n'
          'Amount: ₹${(qty * price).toStringAsFixed(2)}\n\n'
          'Returned stock will be added back to inventory.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await LocalDb.instance.createReturn(
        saleId: sale.id!,
        invoiceNo: sale.invoiceNo,
        customerId: sale.customerId,
        customerName: sale.customerName,
        saleLineId: _asInt(line['sale_line_id']),
        inventoryId: _asInt(line['inventory_id']),
        tileName: (line['tile_name'] ?? '').toString(),
        quantity: qty,
        unitPrice: price,
        reason: _reasonController.text,
      );

      _reasonController.clear();
      await _selectSale(sale);
      final history = await LocalDb.instance.returnsHistory();

      if (!mounted) return;
      setState(() => _history = history);
      _showMessage(
        'Return saved. $qty box(es) added back to inventory.',
      );
    } catch (error) {
      if (mounted) _showMessage('Could not save return: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Widget _buildSearchCard() {
    final suggestions = _suggestions;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Find Original Sale',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'invoice',
                  icon: Icon(Icons.receipt_long),
                  label: Text('Invoice'),
                ),
                ButtonSegment(
                  value: 'customer',
                  icon: Icon(Icons.person_search),
                  label: Text('Customer'),
                ),
              ],
              selected: {_searchMode},
              onSelectionChanged: (value) {
                setState(() {
                  _searchMode = value.first;
                  _searchController.clear();
                  _selectedCustomer = null;
                  _selectedSale = null;
                  _returnableLines = [];
                  _selectedSaleLineId = null;
                  _priceController.clear();
                });
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: _searchMode == 'invoice'
                    ? 'Type invoice number'
                    : 'Type customer name',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.clear),
                      ),
              ),
            ),
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: 4),
              Container(
                constraints: const BoxConstraints(maxHeight: 220),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).dividerColor,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: suggestions.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final value = suggestions[index];
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        _searchMode == 'invoice'
                            ? Icons.receipt
                            : Icons.person,
                      ),
                      title: Text(value),
                      onTap: () => _chooseSuggestion(value),
                    );
                  },
                ),
              ),
            ],
            if (_searchMode == 'customer' &&
                _selectedCustomer != null &&
                _customerSales.length > 1) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<Sale>(
                initialValue: _selectedSale,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Select invoice',
                  border: OutlineInputBorder(),
                ),
                items: _customerSales.map((sale) {
                  final dt = DateTime.tryParse(sale.createdAt);
                  final date = dt == null
                      ? sale.createdAt
                      : DateFormat('dd-MM-yyyy').format(dt);
                  return DropdownMenuItem(
                    value: sale,
                    child: Text('${sale.invoiceNo} • $date'),
                  );
                }).toList(),
                onChanged: (sale) {
                  if (sale != null) _selectSale(sale);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildReturnForm() {
    final sale = _selectedSale;
    if (sale == null) return const SizedBox.shrink();

    final line = _selectedLine;
    final sold = line == null ? 0 : _asInt(line['sold_quantity']);
    final returned = line == null ? 0 : _asInt(line['returned_quantity']);
    final returnable = sold - returned;
    final qty = int.tryParse(_qtyController.text.trim()) ?? 0;
    final price = double.tryParse(_priceController.text.trim()) ?? 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Return Details',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
            const SizedBox(height: 8),
            Text('Invoice: ${sale.invoiceNo}'),
            Text('Customer: ${sale.customerName}'),
            Text('Sale date: ${_formatDate(sale.createdAt)}'),
            const Divider(height: 24),
            if (_returnableLines.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'All materials on this invoice have already been fully returned.',
                ),
              )
            else ...[
              DropdownButtonFormField<int>(
                initialValue: _selectedSaleLineId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Material',
                  border: OutlineInputBorder(),
                ),
                items: _returnableLines.map((item) {
                  final soldQty = _asInt(item['sold_quantity']);
                  final returnedQty = _asInt(item['returned_quantity']);
                  final available = soldQty - returnedQty;
                  return DropdownMenuItem(
                    value: _asInt(item['sale_line_id']),
                    child: Text(
                      '${item['tile_name']} • $available box(es) returnable',
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: _selectMaterial,
              ),
              if (line != null) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(label: Text('Sold: $sold boxes')),
                    Chip(label: Text('Returned: $returned boxes')),
                    Chip(label: Text('Can return: $returnable boxes')),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _qtyController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Return boxes (max $returnable)',
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _priceController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Return price per box',
                    helperText:
                        'Original selling price is filled automatically. You can edit it.',
                    prefixText: '₹ ',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _reasonController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Return reason',
                    hintText: 'Damaged / excess / wrong design / other',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Return Amount'),
                  trailing: Text(
                    '₹${(qty * price).toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _saveReturn,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.assignment_return),
                    label: Text(_saving ? 'Saving...' : 'Confirm Return'),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHistory() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Return History',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
            const SizedBox(height: 8),
            if (_history.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: Text('No returns recorded yet.')),
              )
            else
              ..._history.take(30).map((row) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    child: Icon(Icons.assignment_return),
                  ),
                  title: Text(
                    (row['return_no'] ?? '').toString(),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '${row['customer_name']}\n'
                    '${row['invoice_no']} • ${row['total_boxes']} box(es)\n'
                    '${_formatDate((row['return_date'] ?? '').toString())}',
                  ),
                  isThreeLine: true,
                  trailing: Text(
                    '₹${_asDouble(row['total_amount']).toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  String _formatDate(String raw) {
    final dt = DateTime.tryParse(raw);
    return dt == null ? raw : DateFormat('dd-MM-yyyy').format(dt.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales Returns'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  _buildSearchCard(),
                  _buildReturnForm(),
                  _buildHistory(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }
}

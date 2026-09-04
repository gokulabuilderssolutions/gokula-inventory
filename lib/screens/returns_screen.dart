import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/sale.dart';
import '../services/auth_service.dart';
import '../services/local_db.dart';

class ReturnsScreen extends StatefulWidget {
  const ReturnsScreen({super.key});

  @override
  State<ReturnsScreen> createState() => _ReturnsScreenState();
}

class _ReturnsScreenState extends State<ReturnsScreen> {
  final TextEditingController _searchController =
      TextEditingController();

  final TextEditingController _reasonController =
      TextEditingController();

  List<Sale> _sales = [];
  List<Map<String, Object?>> _returnableLines = [];
  List<Map<String, Object?>> _history = [];

  final Set<int> _selectedLineIds = {};

  final Map<int, TextEditingController>
      _quantityControllers = {};

  final Map<int, TextEditingController>
      _priceControllers = {};

  String _searchMode = 'invoice';
  String? _selectedCustomer;
  Sale? _selectedSale;

  bool _loading = true;
  bool _saving = false;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();

    _load();
    _loadPermissions();

    _searchController.addListener(
      _refreshSuggestions,
    );
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_refreshSuggestions)
      ..dispose();

    _reasonController.dispose();

    _disposeLineControllers();

    super.dispose();
  }

  void _disposeLineControllers() {
    for (final controller
        in _quantityControllers.values) {
      controller.dispose();
    }

    for (final controller
        in _priceControllers.values) {
      controller.dispose();
    }

    _quantityControllers.clear();
    _priceControllers.clear();
  }

  void _refreshSuggestions() {
    if (mounted) setState(() {});
  }

  int _asInt(Object? value) =>
      (value as num?)?.toInt() ?? 0;

  double _asDouble(Object? value) =>
      (value as num?)?.toDouble() ?? 0;

  Future<void> _loadPermissions() async {
    final admin =
        await AuthService().isAdmin();

    if (mounted) {
      setState(() => _isAdmin = admin);
    }
  }

  Future<void> _load() async {
    final sales =
        await LocalDb.instance.sales();

    final history =
        await LocalDb.instance.returnsHistory();

    if (!mounted) return;

    setState(() {
      _sales = sales;
      _history = history;
      _loading = false;
    });
  }

  List<String> get _suggestions {
    final q =
        _searchController.text.trim().toLowerCase();

    if (q.isEmpty) return const [];

    final values = <String>{};

    if (_searchMode == 'invoice') {
      for (final sale in _sales) {
        if (sale.invoiceNo
            .toLowerCase()
            .contains(q)) {
          values.add(sale.invoiceNo);
        }
      }
    } else {
      for (final sale in _sales) {
        if (sale.customerName
            .toLowerCase()
            .contains(q)) {
          values.add(sale.customerName);
        }
      }
    }

    final list = values.toList();

    list.sort(
      (a, b) =>
          a.toLowerCase().compareTo(
                b.toLowerCase(),
              ),
    );

    return list.take(15).toList();
  }

  List<Sale> get _customerSales {
    final name = _selectedCustomer;

    if (name == null) return const [];

    return _sales
        .where(
          (sale) =>
              sale.customerName == name,
        )
        .toList();
  }

  Future<void> _chooseSuggestion(
    String value,
  ) async {
    _searchController.text = value;

    _searchController.selection =
        TextSelection.collapsed(
      offset: value.length,
    );

    if (_searchMode == 'invoice') {
      for (final sale in _sales) {
        if (sale.invoiceNo == value) {
          await _selectSale(sale);
          return;
        }
      }
    } else {
      setState(() {
        _selectedCustomer = value;
        _selectedSale = null;
        _returnableLines = [];
        _selectedLineIds.clear();
      });

      final matches = _sales
          .where(
            (sale) =>
                sale.customerName == value,
          )
          .toList();

      if (matches.length == 1) {
        await _selectSale(
          matches.first,
        );
      }
    }
  }

  Future<void> _selectSale(
    Sale sale,
  ) async {
    if (sale.id == null) return;

    final lines =
        await LocalDb.instance
            .returnableLinesForSale(
      sale.id!,
    );

    if (!mounted) return;

    final available = lines.where(
      (line) {
        final sold =
            _asInt(line['sold_quantity']);

        final returned =
            _asInt(
          line['returned_quantity'],
        );

        return sold - returned > 0;
      },
    ).toList();

    _disposeLineControllers();

    for (final line in available) {
      final id =
          _asInt(line['sale_line_id']);

      _quantityControllers[id] =
          TextEditingController(
        text: '1',
      );

      _priceControllers[id] =
          TextEditingController(
        text: _asDouble(
          line['original_unit_price'],
        ).toStringAsFixed(2),
      );
    }

    setState(() {
      _selectedSale = sale;
      _selectedCustomer =
          sale.customerName;

      _returnableLines = available;

      _selectedLineIds.clear();
    });
  }

  Future<void> _saveReturn() async {
    final sale = _selectedSale;

    if (sale == null ||
        sale.id == null) {
      _showMessage(
        'Select an invoice first.',
      );

      return;
    }

    if (_selectedLineIds.isEmpty) {
      _showMessage(
        'Select at least one design to return.',
      );

      return;
    }

    final selected =
        <Map<String, Object?>>[];

    var totalBoxes = 0;
    var totalAmount = 0.0;

    for (final line
        in _returnableLines) {
      final saleLineId =
          _asInt(
        line['sale_line_id'],
      );

      if (!_selectedLineIds
          .contains(saleLineId)) {
        continue;
      }

      final sold =
          _asInt(
        line['sold_quantity'],
      );

      final alreadyReturned =
          _asInt(
        line['returned_quantity'],
      );

      final available =
          sold - alreadyReturned;

      final qty =
          int.tryParse(
                _quantityControllers[
                        saleLineId]
                    ?.text
                    .trim() ??
                '',
              ) ??
              0;

      final price =
          double.tryParse(
                _priceControllers[
                        saleLineId]
                    ?.text
                    .trim() ??
                '',
              ) ??
              -1;

      final design =
          (line['tile_name'] ?? '')
              .toString();

      if (qty <= 0) {
        _showMessage(
          'Enter return quantity for $design.',
        );

        return;
      }

      if (qty > available) {
        _showMessage(
          'Only $available box(es) of $design can be returned.',
        );

        return;
      }

      if (price < 0) {
        _showMessage(
          'Enter a valid price for $design.',
        );

        return;
      }

      totalBoxes += qty;
      totalAmount += qty * price;

      selected.add({
        'sale_line_id': saleLineId,
        'inventory_id':
            _asInt(
          line['inventory_id'],
        ),
        'tile_name': design,
        'quantity': qty,
        'unit_price': price,
      });
    }

    final summary = selected
        .map(
          (line) =>
              '${line['tile_name']} - '
              '${line['quantity']} box(es)',
        )
        .join('\n');

    final confirmed =
        await showDialog<bool>(
      context: context,
      builder: (
        dialogContext,
      ) =>
          AlertDialog(
        title: const Text(
          'Confirm Return',
        ),
        content:
            SingleChildScrollView(
          child: Text(
            '$summary\n\n'
            'Total: $totalBoxes box(es)\n'
            'Amount: ₹${totalAmount.toStringAsFixed(2)}\n\n'
            'Returned stock will be added back to inventory.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(
              dialogContext,
              false,
            ),
            child:
                const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(
              dialogContext,
              true,
            ),
            child:
                const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed != true ||
        !mounted) {
      return;
    }

    setState(
      () => _saving = true,
    );

    try {
      await LocalDb.instance
          .createReturnMulti(
        saleId: sale.id!,
        invoiceNo: sale.invoiceNo,
        customerId: sale.customerId,
        customerName:
            sale.customerName,
        lines: selected,
        reason:
            _reasonController.text,
      );

      _reasonController.clear();

      await _selectSale(sale);

      final history =
          await LocalDb.instance
              .returnsHistory();

      if (!mounted) return;

      setState(
        () => _history = history,
      );

      _showMessage(
        'Return saved. $totalBoxes box(es) added back to inventory.',
      );
    } catch (error) {
      if (mounted) {
        _showMessage(
          'Could not save return: $error',
        );
      }
    } finally {
      if (mounted) {
        setState(
          () => _saving = false,
        );
      }
    }
  }

  Future<void> _showReturnDetails(
    Map<String, Object?> row,
  ) async {
    final returnId =
        _asInt(row['id']);

    final lines =
        await LocalDb.instance
            .returnLinesForReturn(
      returnId,
    );

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (
        bottomContext,
      ) {
        return SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.65,
            minChildSize: 0.35,
            maxChildSize: 0.9,
            builder: (
              context,
              scrollController,
            ) {
              return ListView(
                controller:
                    scrollController,
                padding:
                    const EdgeInsets.all(
                  16,
                ),
                children: [
                  Text(
                    (row['return_no'] ??
                            '')
                        .toString(),
                    style: Theme.of(
                      context,
                    )
                        .textTheme
                        .titleLarge
                        ?.copyWith(
                          fontWeight:
                              FontWeight
                                  .bold,
                        ),
                  ),
                  const SizedBox(
                    height: 8,
                  ),
                  Text(
                    'Invoice: ${row['invoice_no']}',
                  ),
                  Text(
                    'Customer: ${row['customer_name']}',
                  ),
                  Text(
                    'Date: ${_formatDate((row['return_date'] ?? '').toString())}',
                  ),
                  if ((row['reason'] ?? '')
                      .toString()
                      .trim()
                      .isNotEmpty)
                    Text(
                      'Reason: ${row['reason']}',
                    ),
                  const Divider(
                    height: 28,
                  ),
                  const Text(
                    'Returned Designs',
                    style: TextStyle(
                      fontWeight:
                          FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(
                    height: 6,
                  ),
                  if (lines.isEmpty)
                    const Padding(
                      padding:
                          EdgeInsets.all(
                        16,
                      ),
                      child: Text(
                        'No return line details available.',
                      ),
                    )
                  else
                    ...lines.map(
                      (line) =>
                          Card(
                        child: ListTile(
                          title: Text(
                            (line['tile_name'] ??
                                    '')
                                .toString(),
                            style:
                                const TextStyle(
                              fontWeight:
                                  FontWeight
                                      .bold,
                            ),
                          ),
                          subtitle: Text(
                            'Quantity: ${_asInt(line['quantity'])} box(es)\n'
                            'Rate: ₹${_asDouble(line['unit_price']).toStringAsFixed(2)}',
                          ),
                          isThreeLine:
                              true,
                          trailing: Text(
                            '₹${_asDouble(line['line_total']).toStringAsFixed(2)}',
                            style:
                                const TextStyle(
                              fontWeight:
                                  FontWeight
                                      .bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  const Divider(),
                  ListTile(
                    title: const Text(
                      'Return Total',
                      style: TextStyle(
                        fontWeight:
                            FontWeight
                                .bold,
                      ),
                    ),
                    trailing: Text(
                      '₹${_asDouble(row['total_amount']).toStringAsFixed(2)}',
                      style:
                          const TextStyle(
                        fontWeight:
                            FontWeight
                                .bold,
                        fontSize: 17,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _editReturn(
    Map<String, Object?> row,
  ) async {
    if (!_isAdmin) return;

    final designCount =
        _asInt(
      row['design_count'],
    );

    if (designCount > 1) {
      _showMessage(
        'This return contains multiple designs. Delete and recreate it if correction is required.',
      );

      return;
    }

    final id =
        _asInt(row['id']);

    final qty =
        TextEditingController(
      text: _asInt(
        row['line_quantity'],
      ).toString(),
    );

    final price =
        TextEditingController(
      text: _asDouble(
        row['unit_price'],
      ).toStringAsFixed(2),
    );

    final reason =
        TextEditingController(
      text:
          (row['reason'] ?? '')
              .toString(),
    );

    final ok =
        await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) =>
              AlertDialog(
        title: Text(
          'Edit ${row['return_no']}',
        ),
        content:
            SingleChildScrollView(
          child: Column(
            mainAxisSize:
                MainAxisSize.min,
            children: [
              TextField(
                controller: qty,
                keyboardType:
                    TextInputType
                        .number,
                decoration:
                    const InputDecoration(
                  labelText:
                      'Return quantity',
                ),
              ),
              TextField(
                controller: price,
                keyboardType:
                    const TextInputType
                        .numberWithOptions(
                  decimal: true,
                ),
                decoration:
                    const InputDecoration(
                  labelText:
                      'Return price',
                ),
              ),
              TextField(
                controller: reason,
                maxLines: 2,
                decoration:
                    const InputDecoration(
                  labelText: 'Reason',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(
              dialogContext,
              false,
            ),
            child:
                const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(
              dialogContext,
              true,
            ),
            child:
                const Text('Update'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await LocalDb.instance
          .updateReturnAdmin(
        returnId: id,
        quantity:
            int.tryParse(
                  qty.text.trim(),
                ) ??
                0,
        unitPrice:
            double.tryParse(
                  price.text.trim(),
                ) ??
                -1,
        reason: reason.text,
      );

      await _load();
    } catch (e) {
      if (mounted) {
        _showMessage(
          'Could not update return: $e',
        );
      }
    }
  }

  Future<void> _deleteReturn(
    Map<String, Object?> row,
  ) async {
    if (!_isAdmin) return;

    final ok =
        await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) =>
              AlertDialog(
        title: const Text(
          'Delete return?',
        ),
        content: Text(
          'Delete ${row['return_no']}? Returned stock will be reversed.',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(
              dialogContext,
              false,
            ),
            child:
                const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(
              dialogContext,
              true,
            ),
            child:
                const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await LocalDb.instance
          .deleteReturnAdmin(
        _asInt(row['id']),
      );

      await _load();
    }
  }

  void _showMessage(
    String text,
  ) {
    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(text),
      ),
    );
  }

  Widget _buildSearchCard() {
    final suggestions =
        _suggestions;

    return Card(
      child: Padding(
        padding:
            const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            const Text(
              'Find Original Sale',
              style: TextStyle(
                fontWeight:
                    FontWeight.bold,
                fontSize: 17,
              ),
            ),
            const SizedBox(
              height: 10,
            ),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'invoice',
                  icon: Icon(
                    Icons.receipt_long,
                  ),
                  label:
                      Text('Invoice'),
                ),
                ButtonSegment(
                  value: 'customer',
                  icon: Icon(
                    Icons.person_search,
                  ),
                  label:
                      Text('Customer'),
                ),
              ],
              selected: {
                _searchMode,
              },
              onSelectionChanged:
                  (value) {
                _disposeLineControllers();

                setState(() {
                  _searchMode =
                      value.first;

                  _searchController
                      .clear();

                  _selectedCustomer =
                      null;

                  _selectedSale =
                      null;

                  _returnableLines =
                      [];

                  _selectedLineIds
                      .clear();
                });
              },
            ),
            const SizedBox(
              height: 12,
            ),
            TextField(
              controller:
                  _searchController,
              decoration:
                  InputDecoration(
                labelText:
                    _searchMode ==
                            'invoice'
                        ? 'Type invoice number'
                        : 'Type customer name',
                prefixIcon:
                    const Icon(
                  Icons.search,
                ),
                border:
                    const OutlineInputBorder(),
              ),
            ),
            if (suggestions
                .isNotEmpty) ...[
              const SizedBox(
                height: 6,
              ),
              Container(
                constraints:
                    const BoxConstraints(
                  maxHeight: 220,
                ),
                decoration:
                    BoxDecoration(
                  border: Border.all(
                    color:
                        Theme.of(context)
                            .dividerColor,
                  ),
                  borderRadius:
                      BorderRadius.circular(
                    10,
                  ),
                ),
                child:
                    ListView.separated(
                  shrinkWrap: true,
                  itemCount:
                      suggestions.length,
                  separatorBuilder:
                      (_, __) =>
                          const Divider(
                    height: 1,
                  ),
                  itemBuilder:
                      (_, index) {
                    final value =
                        suggestions[
                            index];

                    return ListTile(
                      dense: true,
                      title:
                          Text(value),
                      onTap: () =>
                          _chooseSuggestion(
                        value,
                      ),
                    );
                  },
                ),
              ),
            ],
            if (_searchMode ==
                    'customer' &&
                _selectedCustomer !=
                    null &&
                _customerSales
                        .length >
                    1) ...[
              const SizedBox(
                height: 12,
              ),
              DropdownButtonFormField<
                  Sale>(
                isExpanded: true,
                decoration:
                    const InputDecoration(
                  labelText:
                      'Select invoice',
                  border:
                      OutlineInputBorder(),
                ),
                items:
                    _customerSales
                        .map(
                  (sale) {
                    return DropdownMenuItem(
                      value: sale,
                      child: Text(
                        sale.invoiceNo,
                      ),
                    );
                  },
                ).toList(),
                onChanged: (sale) {
                  if (sale != null) {
                    _selectSale(
                      sale,
                    );
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildReturnForm() {
    final sale =
        _selectedSale;

    if (sale == null) {
      return const SizedBox
          .shrink();
    }

    return Card(
      child: Padding(
        padding:
            const EdgeInsets.all(
          14,
        ),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            const Text(
              'Return Designs',
              style: TextStyle(
                fontWeight:
                    FontWeight.bold,
                fontSize: 17,
              ),
            ),
            const SizedBox(
              height: 8,
            ),
            Text(
              'Invoice: ${sale.invoiceNo}',
            ),
            Text(
              'Customer: ${sale.customerName}',
            ),
            Text(
              'Sale Date: ${_formatDate(sale.createdAt)}',
            ),
            const Divider(
              height: 24,
            ),
            if (_returnableLines
                .isEmpty)
              const Padding(
                padding:
                    EdgeInsets.all(
                  12,
                ),
                child: Text(
                  'All designs on this invoice have already been fully returned.',
                ),
              )
            else ...[
              const Text(
                'Select one or more designs:',
              ),
              const SizedBox(
                height: 8,
              ),
              ..._returnableLines.map(
                (line) {
                  final id =
                      _asInt(
                    line[
                        'sale_line_id'],
                  );

                  final sold =
                      _asInt(
                    line[
                        'sold_quantity'],
                  );

                  final returned =
                      _asInt(
                    line[
                        'returned_quantity'],
                  );

                  final available =
                      sold - returned;

                  final selected =
                      _selectedLineIds
                          .contains(id);

                  return Card(
                    child: Column(
                      children: [
                        CheckboxListTile(
                          value:
                              selected,
                          title: Text(
                            (line['tile_name'] ??
                                    '')
                                .toString(),
                            style:
                                const TextStyle(
                              fontWeight:
                                  FontWeight
                                      .bold,
                            ),
                          ),
                          subtitle:
                              Text(
                            'Sold $sold • Returned $returned • Can return $available box(es)',
                          ),
                          onChanged:
                              (value) {
                            setState(
                              () {
                                if (value ==
                                    true) {
                                  _selectedLineIds
                                      .add(
                                    id,
                                  );
                                } else {
                                  _selectedLineIds
                                      .remove(
                                    id,
                                  );
                                }
                              },
                            );
                          },
                        ),
                        if (selected)
                          Padding(
                            padding:
                                const EdgeInsets
                                    .fromLTRB(
                              16,
                              0,
                              16,
                              14,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child:
                                      TextField(
                                    controller:
                                        _quantityControllers[
                                            id],
                                    keyboardType:
                                        TextInputType
                                            .number,
                                    decoration:
                                        InputDecoration(
                                      labelText:
                                          'Return Qty (max $available)',
                                      border:
                                          const OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                const SizedBox(
                                  width: 10,
                                ),
                                Expanded(
                                  child:
                                      TextField(
                                    controller:
                                        _priceControllers[
                                            id],
                                    keyboardType:
                                        const TextInputType
                                            .numberWithOptions(
                                      decimal:
                                          true,
                                    ),
                                    decoration:
                                        const InputDecoration(
                                      labelText:
                                          'Rate',
                                      prefixText:
                                          '₹ ',
                                      border:
                                          OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(
                height: 10,
              ),
              TextField(
                controller:
                    _reasonController,
                maxLines: 2,
                decoration:
                    const InputDecoration(
                  labelText:
                      'Return reason',
                  hintText:
                      'Damaged / excess / wrong design / other',
                  border:
                      OutlineInputBorder(),
                ),
              ),
              const SizedBox(
                height: 12,
              ),
              SizedBox(
                width:
                    double.infinity,
                child:
                    FilledButton.icon(
                  onPressed:
                      _saving
                          ? null
                          : _saveReturn,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child:
                              CircularProgressIndicator(
                            strokeWidth:
                                2,
                          ),
                        )
                      : const Icon(
                          Icons
                              .assignment_return,
                        ),
                  label: Text(
                    _saving
                        ? 'Saving...'
                        : 'Confirm Selected Returns',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHistory() {
    return Card(
      child: Padding(
        padding:
            const EdgeInsets.all(
          14,
        ),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            const Text(
              'Return History',
              style: TextStyle(
                fontWeight:
                    FontWeight.bold,
                fontSize: 17,
              ),
            ),
            const SizedBox(
              height: 8,
            ),
            if (_history.isEmpty)
              const Padding(
                padding:
                    EdgeInsets.all(
                  16,
                ),
                child: Center(
                  child: Text(
                    'No returns recorded yet.',
                  ),
                ),
              )
            else
              ..._history
                  .take(50)
                  .map(
                (row) {
                  final count =
                      _asInt(
                    row[
                        'design_count'],
                  );

                  final totalBoxes =
                      _asInt(
                    row[
                        'total_boxes'],
                  );

                  return ListTile(
                    contentPadding:
                        EdgeInsets.zero,
                    leading:
                        const CircleAvatar(
                      child: Icon(
                        Icons
                            .assignment_return,
                      ),
                    ),
                    title: Text(
                      (row['return_no'] ??
                              '')
                          .toString(),
                      style:
                          const TextStyle(
                        fontWeight:
                            FontWeight
                                .bold,
                      ),
                    ),
                    subtitle: Text(
                      '${row['customer_name']}\n'
                      '${row['invoice_no']} • '
                      '$count design(s) • '
                      '$totalBoxes box(es)\n'
                      '${_formatDate((row['return_date'] ?? '').toString())}',
                    ),
                    isThreeLine: true,
                    onTap: () =>
                        _showReturnDetails(
                      row,
                    ),
                    trailing:
                        _isAdmin
                            ? PopupMenuButton<
                                String>(
                                onSelected:
                                    (value) {
                                  if (value ==
                                      'view') {
                                    _showReturnDetails(
                                      row,
                                    );
                                  }

                                  if (value ==
                                      'edit') {
                                    _editReturn(
                                      row,
                                    );
                                  }

                                  if (value ==
                                      'delete') {
                                    _deleteReturn(
                                      row,
                                    );
                                  }
                                },
                                itemBuilder:
                                    (_) => [
                                  const PopupMenuItem(
                                    value:
                                        'view',
                                    child:
                                        ListTile(
                                      leading:
                                          Icon(
                                        Icons
                                            .visibility,
                                      ),
                                      title:
                                          Text(
                                        'View designs',
                                      ),
                                    ),
                                  ),
                                  if (count <=
                                      1)
                                    const PopupMenuItem(
                                      value:
                                          'edit',
                                      child:
                                          ListTile(
                                        leading:
                                            Icon(
                                          Icons
                                              .edit,
                                        ),
                                        title:
                                            Text(
                                          'Edit return',
                                        ),
                                      ),
                                    ),
                                  const PopupMenuItem(
                                    value:
                                        'delete',
                                    child:
                                        ListTile(
                                      leading:
                                          Icon(
                                        Icons
                                            .delete_outline,
                                      ),
                                      title:
                                          Text(
                                        'Delete return',
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : const Icon(
                                Icons
                                    .chevron_right,
                              ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  String _formatDate(
    String raw,
  ) {
    final dt =
        DateTime.tryParse(raw);

    return dt == null
        ? raw
        : DateFormat(
            'dd-MM-yyyy',
          ).format(
            dt.toLocal(),
          );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text(
          'Sales Returns',
        ),
      ),
      body: _loading
          ? const Center(
              child:
                  CircularProgressIndicator(),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding:
                    const EdgeInsets.all(
                  12,
                ),
                children: [
                  _buildSearchCard(),
                  _buildReturnForm(),
                  _buildHistory(),
                  const SizedBox(
                    height: 40,
                  ),
                ],
              ),
            ),
    );
  }
}

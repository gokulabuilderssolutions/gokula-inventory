import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/local_db.dart';

class SalesSearchPanel extends StatefulWidget {
  const SalesSearchPanel({super.key});

  @override
  State<SalesSearchPanel> createState() => _SalesSearchPanelState();
}

class _SalesSearchPanelState extends State<SalesSearchPanel> {
  final TextEditingController _searchController = TextEditingController();

  String _mode = 'design';
  List<String> _designs = [];
  List<String> _customers = [];
  List<Map<String, Object?>> _history = [];

  bool _loadingMasters = true;
  bool _loadingHistory = false;
  String? _selectedValue;

  @override
  void initState() {
    super.initState();
    _loadMasters();
    _searchController.addListener(_onTyping);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onTyping)
      ..dispose();
    super.dispose();
  }

  Future<void> _loadMasters() async {
    final designs = await LocalDb.instance.salesDesignNames();
    final customers = await LocalDb.instance.salesCustomerNames();
    if (!mounted) return;

    setState(() {
      _designs = designs;
      _customers = customers;
      _loadingMasters = false;
    });
  }

  void _onTyping() {
    if (!mounted) return;
    if (_selectedValue != null &&
        _searchController.text.trim() != _selectedValue) {
      _selectedValue = null;
      _history = [];
    }
    setState(() {});
  }

  List<String> get _suggestions {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty || _selectedValue != null) return const [];

    final source = _mode == 'design' ? _designs : _customers;
    final matches = source
        .where((value) => value.toLowerCase().contains(q))
        .toList();

    matches.sort((a, b) {
      final aa = a.toLowerCase();
      final bb = b.toLowerCase();
      final aStarts = aa.startsWith(q);
      final bStarts = bb.startsWith(q);

      if (aStarts != bStarts) return aStarts ? -1 : 1;
      return aa.compareTo(bb);
    });

    return matches.take(12).toList();
  }

  int _asInt(Object? value) => (value as num?)?.toInt() ?? 0;
  double _asDouble(Object? value) => (value as num?)?.toDouble() ?? 0;

  Future<void> _selectSuggestion(String value) async {
    _searchController.text = value;
    _searchController.selection =
        TextSelection.collapsed(offset: value.length);

    setState(() {
      _selectedValue = value;
      _loadingHistory = true;
      _history = [];
    });

    final result = _mode == 'design'
        ? await LocalDb.instance.salesHistoryByDesign(value)
        : await LocalDb.instance.salesHistoryByCustomer(value);

    if (!mounted) return;

    setState(() {
      _history = result;
      _loadingHistory = false;
    });
  }

  void _changeMode(String mode) {
    setState(() {
      _mode = mode;
      _selectedValue = null;
      _history = [];
      _searchController.clear();
    });
  }

  Widget _summaryCard() {
    final totalSold = _history.fold<int>(
      0,
      (sum, row) => sum + _asInt(row['boxes_sold']),
    );
    final totalReturned = _history.fold<int>(
      0,
      (sum, row) => sum + _asInt(row['boxes_returned']),
    );
    final netSold = totalSold - totalReturned;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        spacing: 18,
        runSpacing: 8,
        children: [
          _summaryValue('Sold', totalSold),
          _summaryValue('Returned', totalReturned),
          _summaryValue('Net Sold', netSold),
        ],
      ),
    );
  }

  Widget _summaryValue(String label, int value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(
          '$value boxes',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _historyCard(Map<String, Object?> row) {
    final sold = _asInt(row['boxes_sold']);
    final returned = _asInt(row['boxes_returned']);
    final net = sold - returned;
    final stock = _asInt(row['stock_remaining']);
    final price = _asDouble(row['unit_price']);

    final rawDate = (row['created_at'] ?? '').toString();
    final parsed = DateTime.tryParse(rawDate);
    final date = parsed == null
        ? rawDate
        : DateFormat('dd-MM-yyyy').format(parsed.toLocal());

    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              (row['tile_name'] ?? '').toString(),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text('Customer: ${row['customer_name']}'),
            Text('Invoice: ${row['invoice_no']}'),
            if (date.isNotEmpty) Text('Date: $date'),
            const Divider(height: 18),
            Wrap(
              spacing: 14,
              runSpacing: 8,
              children: [
                Text('Sold: $sold boxes'),
                Text('Returned: $returned boxes'),
                Text(
                  'Net: $net boxes',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  'Stock remaining: $stock boxes',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Selling price: ₹${price.toStringAsFixed(2)} / box'),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = _suggestions;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Search Sales History',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'design',
                  icon: Icon(Icons.grid_view),
                  label: Text('Design'),
                ),
                ButtonSegment(
                  value: 'customer',
                  icon: Icon(Icons.person_search),
                  label: Text('Customer'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (selection) {
                _changeMode(selection.first);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              enabled: !_loadingMasters,
              decoration: InputDecoration(
                labelText: _mode == 'design'
                    ? 'Type design name'
                    : 'Type customer name',
                hintText: _mode == 'design'
                    ? 'Example: A...'
                    : 'Example: Ramesh...',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                            _selectedValue = null;
                            _history = [];
                          });
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
                        _mode == 'design'
                            ? Icons.inventory_2_outlined
                            : Icons.person_outline,
                      ),
                      title: Text(value),
                      onTap: () => _selectSuggestion(value),
                    );
                  },
                ),
              ),
            ],
            if (_loadingHistory)
              const Padding(
                padding: EdgeInsets.all(18),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (!_loadingHistory &&
                _selectedValue != null &&
                _history.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('No sales history found.'),
              ),
            if (_history.isNotEmpty) ...[
              _summaryCard(),
              const SizedBox(height: 4),
              ..._history.map(_historyCard),
            ],
          ],
        ),
      ),
    );
  }
}

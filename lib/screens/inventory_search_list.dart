import 'dart:io';

import 'package:flutter/material.dart';

import '../models/inventory_item.dart';

class InventorySearchList extends StatefulWidget {
  final List<InventoryItem> items;
  final Future<void> Function() onRefresh;
  final Future<void> Function(InventoryItem item) onEdit;
  final Future<void> Function(InventoryItem item) onDelete;

  const InventorySearchList({
    super.key,
    required this.items,
    required this.onRefresh,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<InventorySearchList> createState() => _InventorySearchListState();
}

class _InventorySearchListState extends State<InventorySearchList> {
  final TextEditingController _searchController = TextEditingController();
  String? _selectedDesign;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onTyping);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onTyping)
      ..dispose();
    super.dispose();
  }

  void _onTyping() {
    if (_selectedDesign != null &&
        _searchController.text.trim() != _selectedDesign) {
      _selectedDesign = null;
    }
    if (mounted) setState(() {});
  }

  List<String> get _suggestions {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty || _selectedDesign != null) return const [];

    final unique = <String>{};
    for (final item in widget.items) {
      if (item.tileName.toLowerCase().contains(q)) {
        unique.add(item.tileName);
      }
    }

    final list = unique.toList();
    list.sort((a, b) {
      final aa = a.toLowerCase();
      final bb = b.toLowerCase();
      final aStarts = aa.startsWith(q);
      final bStarts = bb.startsWith(q);

      if (aStarts != bStarts) return aStarts ? -1 : 1;
      return aa.compareTo(bb);
    });

    return list.take(12).toList();
  }

  List<InventoryItem> get _visibleItems {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return widget.items;

    return widget.items
        .where((item) => item.tileName.toLowerCase().contains(q))
        .toList();
  }

  void _selectDesign(String design) {
    setState(() {
      _selectedDesign = design;
      _searchController.text = design;
      _searchController.selection =
          TextSelection.collapsed(offset: design.length);
    });
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = _suggestions;
    final visible = _visibleItems;

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: 'Search design name',
              hintText: 'Start typing, for example A...',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        setState(() {
                          _searchController.clear();
                          _selectedDesign = null;
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
                  final design = suggestions[index];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.inventory_2_outlined),
                    title: Text(design),
                    onTap: () => _selectDesign(design),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 8),
          if (visible.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 50),
              child: Center(
                child: Text('No matching design found.'),
              ),
            )
          else
            ...visible.map(
              (item) => Card(
                child: ListTile(
                  leading: _SearchInventoryImage(item: item),
                  title: Text(
                    item.tileName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '${item.size} • ${item.texture}\n'
                    'Stock: ${item.stock}  '
                    'Price: ₹${item.price.toStringAsFixed(2)}',
                  ),
                  isThreeLine: true,
                  onTap: () => widget.onEdit(item),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') widget.onEdit(item);
                      if (value == 'delete') widget.onDelete(item);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'edit',
                        child: Text('Edit'),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 90),
        ],
      ),
    );
  }
}

class _SearchInventoryImage extends StatelessWidget {
  final InventoryItem item;

  const _SearchInventoryImage({required this.item});

  @override
  Widget build(BuildContext context) {
    final file =
        item.localImage.isEmpty ? null : File(item.localImage);

    if (file != null && file.existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          file,
          width: 58,
          height: 58,
          fit: BoxFit.cover,
        ),
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
          errorBuilder: (_, __, ___) =>
              const CircleAvatar(child: Icon(Icons.broken_image)),
        ),
      );
    }

    return const CircleAvatar(
      child: Icon(Icons.inventory_2),
    );
  }
}

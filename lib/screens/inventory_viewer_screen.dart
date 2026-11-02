import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';

/// Viewer uses cloud-only reads: never opens the shared offline SQLite database,
/// never calls SyncService, and never exposes any write controls.
class InventoryViewerScreen extends StatefulWidget {
  const InventoryViewerScreen({super.key});
  @override
  State<InventoryViewerScreen> createState() => _InventoryViewerScreenState();
}

class _InventoryViewerScreenState extends State<InventoryViewerScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  String _search = '';
  String _size = 'All Sizes';
  String _finish = 'All Finishes';
  String _minStock = '';
  String _maxStock = '';

  Future<void> _refresh() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final profile = await AuthService().currentProfile();
      final role = (profile?['role'] ?? '').toString().trim().toLowerCase();
      if (profile == null || profile['is_active'] != true ||
          (role != 'viewer' && role != 'inventory_viewer')) {
        throw StateError('Viewer access not authorized');
      }
      // Supabase defaults to a 1,000-row response; page to include all designs.
      final rows = <Map<String, dynamic>>[];
      const pageSize = 500;
      for (var offset = 0; ; offset += pageSize) {
        final page = await Supabase.instance.client.from('inventory')
            .select('id, tile_name, size, texture, stock, image_url')
            .order('id').range(offset, offset + pageSize - 1);
        rows.addAll(page.map((row) => Map<String, dynamic>.from(row)));
        if (page.length < pageSize) break;
      }
      if (mounted) setState(() { _items = rows; _loading = false; });
    } catch (error) {
      debugPrint('INVENTORY_VIEWER_ERROR: $error');
      if (mounted) {
        setState(() {
          _error = 'Unable to load inventory. Please retry.';
          _loading = false;
        });
      }
    }
  }

  @override
  void initState() { super.initState(); _refresh(); }

  @override
  Widget build(BuildContext context) {
    final sizes = _items.map((e) => (e['size'] ?? '').toString()).where((s) => s.isNotEmpty).toSet().toList()..sort();
    final finishes = _items.map((e) => (e['texture'] ?? '').toString()).where((s) => s.isNotEmpty).toSet().toList()..sort();
    final minStock = int.tryParse(_minStock.trim());
    final maxStock = int.tryParse(_maxStock.trim());
    final visible = _items.where((e) =>
      (e['tile_name'] ?? '').toString().toLowerCase().contains(_search.toLowerCase()) &&
      (_size == 'All Sizes' || e['size'] == _size) &&
      (_finish == 'All Finishes' || e['texture'] == _finish) &&
      (minStock == null || (num.tryParse((e['stock'] ?? 0).toString()) ?? 0) >= minStock) &&
      (maxStock == null || (num.tryParse((e['stock'] ?? 0).toString()) ?? 0) <= maxStock)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Inventory - View Only'), actions: [
        IconButton(tooltip: 'Refresh inventory', onPressed: _refresh, icon: const Icon(Icons.refresh)),
        IconButton(tooltip: 'Logout', icon: const Icon(Icons.logout), onPressed: () async {
          await AuthService().logout();
        }),
      ]),
      body: _loading ? const Center(child: CircularProgressIndicator()) :
        _error != null ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!), TextButton(onPressed: _refresh, child: const Text('Retry')),
        ])) : RefreshIndicator(onRefresh: _refresh, child: ListView(
          padding: const EdgeInsets.all(12), children: [
          TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Search designs'),
            onChanged: (v) => setState(() => _search = v)),
          DropdownButtonFormField<String>(value: _size, isExpanded: true,
            decoration: const InputDecoration(labelText: 'Size'),
            items: ['All Sizes', ...sizes].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: (v) => setState(() => _size = v ?? 'All Sizes')),
          DropdownButtonFormField<String>(value: _finish, isExpanded: true,
            decoration: const InputDecoration(labelText: 'Finish'),
            items: ['All Finishes', ...finishes].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: (v) => setState(() => _finish = v ?? 'All Finishes')),
          Row(children: [
            Expanded(child: TextField(
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Minimum quantity', hintText: 'Example: 1'),
              onChanged: (v) => setState(() => _minStock = v),
            )),
            const SizedBox(width: 10),
            Expanded(child: TextField(
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Maximum quantity', hintText: 'Example: 100'),
              onChanged: (v) => setState(() => _maxStock = v),
            )),
          ]),
          Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('${visible.length} designs')),
          for (final item in visible) Card(child: ListTile(
            leading: (item['image_url'] ?? '').toString().isEmpty
              ? const Icon(Icons.image_not_supported_outlined)
              : Image.network((item['image_url']).toString(), width: 62, height: 62,
                  fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image)),
            title: Text((item['tile_name'] ?? '').toString()),
            subtitle: Text('${item['size'] ?? ''}  •  ${item['texture'] ?? ''}'),
            trailing: Text('Stock: ${item['stock'] ?? 0}', style: const TextStyle(fontWeight: FontWeight.bold)),
            onTap: () => showDialog<void>(context: context, builder: (_) => AlertDialog(
              title: Text((item['tile_name'] ?? '').toString()),
              content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
                if ((item['image_url'] ?? '').toString().isNotEmpty)
                  Image.network((item['image_url']).toString(), errorBuilder: (_, __, ___) => const Icon(Icons.broken_image)),
                Text('Size: ${item['size'] ?? ''}'),
                Text('Finish: ${item['texture'] ?? ''}'),
                Text('Stock: ${item['stock'] ?? 0}'),
              ])),
              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
            )),
          )),
        ])),
    );
  }
}

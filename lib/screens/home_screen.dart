import 'package:flutter/material.dart';
import '../services/local_db.dart';
import '../services/sync_service.dart';
import 'inventory_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool online = false;
  int pending = 0;
  String lastSync = 'Never';
  bool syncing = false;

  @override
  void initState() {
    super.initState();
    refreshStatus();
    SyncService.instance.startAutoSync();
    SyncService.instance.onlineStream.listen((value) {
      if (mounted) setState(() => online = value);
      refreshStatus();
    });
  }

  Future<void> refreshStatus() async {
    final o = await SyncService.instance.isOnline();
    final p = await LocalDb.instance.pendingCount();
    final l = await LocalDb.instance.getLastSync();
    if (mounted) setState(() { online = o; pending = p; lastSync = l; });
  }

  Future<void> sync() async {
    setState(() => syncing = true);
    final message = await SyncService.instance.syncNow();
    await refreshStatus();
    if (mounted) {
      setState(() => syncing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gokula Inventory'), actions: [
        IconButton(onPressed: syncing ? null : sync, icon: syncing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync)),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Center(child: ClipRRect(borderRadius: BorderRadius.circular(22), child: Image.asset('assets/images/logo.jpg', height: 180, fit: BoxFit.cover))),
        const SizedBox(height: 18),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(Icons.circle, size: 14, color: online ? Colors.green : Colors.red), const SizedBox(width: 8), Text(online ? 'Online' : 'Offline', style: const TextStyle(fontWeight: FontWeight.bold))]),
          const SizedBox(height: 8),
          Text('Pending Sync: $pending'),
          Text('Last Sync: $lastSync'),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: syncing ? null : sync, icon: const Icon(Icons.sync), label: const Text('Sync Now'))),
        ]))),
        const SizedBox(height: 12),
        Card(child: ListTile(leading: const Icon(Icons.inventory_2), title: const Text('Inventory'), subtitle: const Text('Add tiles and stock, even without internet'), trailing: const Icon(Icons.chevron_right), onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const InventoryScreen()));
          refreshStatus();
        })),
        Card(child: const ListTile(leading: Icon(Icons.receipt_long), title: Text('Sales'), subtitle: Text('Sales module can be added in the next build'))),
      ]),
    );
  }
}

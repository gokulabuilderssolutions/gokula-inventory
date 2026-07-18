import 'package:flutter/material.dart';
import '../models/master_option.dart';
import '../services/local_db.dart';

class MasterDataScreen extends StatefulWidget {
  const MasterDataScreen({super.key});
  @override
  State<MasterDataScreen> createState() => _MasterDataScreenState();
}

class _MasterDataScreenState extends State<MasterDataScreen> with SingleTickerProviderStateMixin {
  late final TabController tabs;
  final search = TextEditingController();
  List<MasterOption> sizes = [];
  List<MasterOption> textures = [];

  @override
  void initState() {
    super.initState();
    tabs = TabController(length: 2, vsync: this);
    load();
  }

  Future<void> load() async {
    sizes = await LocalDb.instance.masterOptions('size');
    textures = await LocalDb.instance.masterOptions('texture');
    if (mounted) setState(() {});
  }

  Future<void> edit([MasterOption? current, String? forcedType]) async {
    final value = TextEditingController(text: current?.value ?? '');
    final category = TextEditingController(text: current?.category ?? (forcedType == 'texture' ? 'Finish' : 'General'));
    bool favorite = current?.favorite ?? false;
    final type = current?.type ?? forcedType ?? (tabs.index == 0 ? 'size' : 'texture');
    await showDialog<void>(context: context, builder: (context) => StatefulBuilder(builder: (context, localSet) => AlertDialog(
      title: Text(current == null ? 'Add ${type == 'size' ? 'Size' : 'Finish'}' : 'Edit ${type == 'size' ? 'Size' : 'Finish'}'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: value, autofocus: true, decoration: InputDecoration(labelText: type == 'size' ? 'Size (example: 12×18)' : 'Finish name')),
        TextField(controller: category, decoration: const InputDecoration(labelText: 'Category')),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Show in favourites'), value: favorite, onChanged: (v) => localSet(() => favorite = v)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () async {
          final clean = value.text.trim();
          if (clean.isEmpty) return;
          try {
            await LocalDb.instance.saveMasterOption(MasterOption(id: current?.id, type: type, value: clean, category: category.text.trim().isEmpty ? 'General' : category.text.trim(), favorite: favorite, sortOrder: current?.sortOrder ?? 999));
            if (context.mounted) Navigator.pop(context);
          } catch (_) {
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This value already exists.')));
          }
        }, child: const Text('Save')),
      ],
    )));
    await load();
  }

  Future<void> remove(MasterOption option) async {
    final ok = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Delete master value?'),
      content: Text('Delete “${option.value}”? Values already used in inventory cannot be deleted.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete'))],
    ));
    if (ok != true) return;
    try {
      await LocalDb.instance.deleteMasterOption(option);
      await load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Bad state: ', ''))));
    }
  }

  Widget list(String type, List<MasterOption> source) {
    final q = search.text.trim().toLowerCase();
    final data = source.where((e) => q.isEmpty || e.value.toLowerCase().contains(q) || e.category.toLowerCase().contains(q)).toList();
    if (data.isEmpty) return const Center(child: Text('No values found.'));
    return ListView.builder(padding: const EdgeInsets.all(12), itemCount: data.length, itemBuilder: (_, i) {
      final item = data[i];
      return Card(child: ListTile(
        leading: Icon(item.favorite ? Icons.star : Icons.star_border),
        title: Text(item.value, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(item.category),
        trailing: Wrap(mainAxisSize: MainAxisSize.min, children: [
          IconButton(icon: const Icon(Icons.edit), onPressed: () => edit(item)),
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => remove(item)),
        ]),
      ));
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Master Data'), bottom: TabBar(controller: tabs, tabs: const [Tab(text: 'Tile Sizes'), Tab(text: 'Finishes')])),
    floatingActionButton: FloatingActionButton.extended(onPressed: () => edit(null, tabs.index == 0 ? 'size' : 'texture'), icon: const Icon(Icons.add), label: const Text('Add')),
    body: Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: TextField(controller: search, onChanged: (_) => setState(() {}), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Search master values', border: OutlineInputBorder()))),
      Expanded(child: TabBarView(controller: tabs, children: [list('size', sizes), list('texture', textures)])),
    ]),
  );
}

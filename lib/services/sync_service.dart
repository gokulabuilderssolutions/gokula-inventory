import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config.dart';
import 'local_db.dart';

class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();
  final _status = StreamController<bool>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _syncing = false;

  Stream<bool> get onlineStream => _status.stream;

  Future<bool> isOnline() async {
    final result = await Connectivity().checkConnectivity();
    if (result.every((e) => e == ConnectivityResult.none)) return false;
    try {
      await Supabase.instance.client.from('inventory').select('id').limit(1);
      return true;
    } catch (_) {
      return false;
    }
  }

  void startAutoSync() {
    _subscription ??= Connectivity().onConnectivityChanged.listen((_) async {
      final online = await isOnline();
      _status.add(online);
      if (online) await syncNow();
    });
  }

  Future<String> syncNow() async {
    if (_syncing) return 'Sync already running';
    _syncing = true;
    try {
      if (!await isOnline()) {
        _status.add(false);
        return 'Offline. Data remains safe on this phone.';
      }
      _status.add(true);
      final client = Supabase.instance.client;
      final pending = await LocalDb.instance.pendingInventory();
      var uploaded = 0;
      for (final item in pending) {
        String imageUrl = item.imageUrl;
        if (item.localImage.isNotEmpty && File(item.localImage).existsSync() && imageUrl.isEmpty) {
          final file = File(item.localImage);
          final remote = 'mobile/${item.clientUid}.jpg';
          await client.storage.from(AppConfig.storageBucket).upload(remote, file, fileOptions: const FileOptions(upsert: true));
          imageUrl = client.storage.from(AppConfig.storageBucket).getPublicUrl(remote);
        }
        final existing = await client.from('inventory').select('id').eq('client_uid', item.clientUid).limit(1);
        int? cloudId;
        final payload = item.toCloudMap()..['image_url'] = imageUrl;
        if (existing.isNotEmpty) {
          cloudId = existing.first['id'] as int?;
          await client.from('inventory').update(payload).eq('id', cloudId!);
        } else {
          final inserted = await client.from('inventory').insert(payload).select('id').single();
          cloudId = inserted['id'] as int?;
        }
        if (item.id != null) await LocalDb.instance.markSynced(item.id!, cloudId, imageUrl: imageUrl);
        uploaded++;
      }
      final cloudRows = await client.from('inventory').select('*');
      for (final row in cloudRows) {
        await LocalDb.instance.upsertCloud(Map<String, dynamic>.from(row));
      }
      final now = DateTime.now().toLocal().toString().split('.').first;
      await LocalDb.instance.setLastSync(now);
      return 'Sync complete: $uploaded uploaded, ${cloudRows.length} checked';
    } catch (e) {
      return 'Sync error: $e';
    } finally {
      _syncing = false;
    }
  }

  void dispose() {
    _subscription?.cancel();
    _status.close();
  }
}

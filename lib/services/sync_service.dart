import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'image_storage_service.dart';
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
    if (result.every((e) => e == ConnectivityResult.none)) {
      return false;
    }

    try {
      await Supabase.instance.client
          .from('inventory')
          .select('id')
          .limit(1);
      return true;
    } catch (_) {
      return false;
    }
  }

  void startAutoSync() {
    _subscription ??=
        Connectivity().onConnectivityChanged.listen((_) async {
      final online = await isOnline();
      _status.add(online);
      if (online) {
        await syncNow();
      }
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

      var inventoryUploaded = 0;
      var salesUploaded = 0;
      var returnsUploaded = 0;

      final pendingInventory = await LocalDb.instance.pendingInventory();

      for (final item in pendingInventory) {
        if (item.deleted) {
          final existing = await client
              .from('inventory')
              .select('id')
              .eq('client_uid', item.clientUid)
              .limit(1);

          if (existing.isNotEmpty) {
            await client
                .from('inventory')
                .delete()
                .eq('client_uid', item.clientUid);
          }

          if (item.id != null) {
            await LocalDb.instance.markSynced(
              item.id!,
              item.cloudId,
              imageUrl: item.imageUrl,
            );
          }
          inventoryUploaded++;
          continue;
        }

        String imageUrl = item.imageUrl;

        if (item.localImage.isNotEmpty &&
            File(item.localImage).existsSync() &&
            imageUrl.isEmpty) {
          final file = File(item.localImage);
          final remote = 'mobile/${item.clientUid}.jpg';

          await client.storage
              .from(AppConfig.storageBucket)
              .upload(
                remote,
                file,
                fileOptions: const FileOptions(upsert: true),
              );

          imageUrl = client.storage
              .from(AppConfig.storageBucket)
              .getPublicUrl(remote);
        }

        // Find existing cloud inventory robustly for cross-phone photo sync.
        var existing = await client
            .from('inventory')
            .select('id')
            .eq('client_uid', item.clientUid)
            .limit(1);

        if (existing.isEmpty && item.cloudId != null) {
          existing = await client
              .from('inventory')
              .select('id')
              .eq('id', item.cloudId!)
              .limit(1);
        }

        if (existing.isEmpty) {
          existing = await client
              .from('inventory')
              .select('id')
              .eq('tile_name', item.tileName)
              .eq('size', item.size)
              .eq('texture', item.texture)
              .limit(1);
        }

        int? cloudId;
        final payload = item.toCloudMap()
          ..['image_url'] = imageUrl;

        if (existing.isNotEmpty) {
          cloudId = existing.first['id'] as int?;
          await client
              .from('inventory')
              .update(payload)
              .eq('id', cloudId!);
        } else {
          final inserted = await client
              .from('inventory')
              .insert(payload)
              .select('id')
              .single();
          cloudId = inserted['id'] as int?;
        }

        if (item.id != null) {
          await LocalDb.instance.markSynced(
            item.id!,
            cloudId,
            imageUrl: imageUrl,
          );
        }

        inventoryUploaded++;
      }

      final cloudRows = await client.from('inventory').select('*');
      final localItems = await LocalDb.instance.inventory();
      final localByUid = {
        for (final item in localItems) item.clientUid: item,
      };

      for (final row in cloudRows) {
        final cloud = Map<String, dynamic>.from(row);
        final uid =
            (cloud['client_uid'] ?? 'cloud-${cloud['id']}').toString();
        final imageUrl = (cloud['image_url'] ?? '').toString();
        final existingLocal = localByUid[uid]?.localImage ?? '';

        final cachedPath =
            await ImageStorageService.cacheRemoteImage(
          imageUrl: imageUrl,
          clientUid: uid,
          existingLocalPath: existingLocal,
        );

        await LocalDb.instance.upsertCloud(
          cloud,
          cachedLocalImage: cachedPath,
        );
      }

      try {
        final pendingSales =
            await LocalDb.instance.pendingSalesWithLines();

        for (final bundle in pendingSales) {
          final sale =
              Map<String, Object?>.from(bundle['sale'] as Map);
          final lines = (bundle['lines'] as List)
              .map(
                (e) =>
                    Map<String, Object?>.from(e as Map),
              )
              .toList();

          final localId = sale['id'] as int;
          sale.remove('id');
          sale.remove('sync_state');

          final cloudLines = <Map<String, Object?>>[];

          for (final line in lines) {
            final copy = Map<String, Object?>.from(line);
            copy.remove('id');
            copy.remove('sale_id');

            final inventoryId =
                (copy['inventory_id'] as num?)?.toInt();

            if (inventoryId != null) {
              final inventoryItem =
                  await LocalDb.instance.inventoryById(inventoryId);

              if (inventoryItem != null) {
                copy['inventory_client_uid'] =
                    inventoryItem.clientUid;
              }
            }

            cloudLines.add(copy);
          }

          sale['lines'] = cloudLines;

          await client
              .from('sales')
              .upsert(sale, onConflict: 'invoice_no');

          await LocalDb.instance.markSaleSynced(localId);
          salesUploaded++;
        }

        final cloudSales = await client
            .from('sales')
            .select('*')
            .order('created_at');

        for (final row in cloudSales) {
          await LocalDb.instance.upsertCloudSale(
            Map<String, dynamic>.from(row),
          );
        }
      } catch (_) {
        // Sales stay pending if the sales cloud schema is unavailable.
      }

      try {
        final pendingReturns =
            await LocalDb.instance.pendingReturnsWithLines();

        for (final bundle in pendingReturns) {
          final localHeader =
              Map<String, Object?>.from(bundle['return'] as Map);
          final localLines = (bundle['lines'] as List)
              .map(
                (e) =>
                    Map<String, Object?>.from(e as Map),
              )
              .toList();

          final localReturnId = localHeader['id'] as int;
          final returnNo =
              (localHeader['return_no'] ?? '').toString();

          final headerPayload = <String, Object?>{
            'return_no': returnNo,
            'sale_invoice_no':
                (localHeader['invoice_no'] ?? '').toString(),
            'customer_name':
                (localHeader['customer_name'] ?? '').toString(),
            'return_date':
                (localHeader['return_date'] ?? '').toString(),
            'reason':
                (localHeader['reason'] ?? '').toString(),
            'total_amount':
                (localHeader['total_amount'] as num?)?.toDouble() ??
                    0,
            'created_by': client.auth.currentUser?.id,
          };

          final existingHeader = await client
              .from('returns')
              .select('id')
              .eq('return_no', returnNo)
              .limit(1);

          int cloudReturnId;

          if (existingHeader.isEmpty) {
            final inserted = await client
                .from('returns')
                .insert(headerPayload)
                .select('id')
                .single();

            cloudReturnId = (inserted['id'] as num).toInt();
          } else {
            cloudReturnId =
                (existingHeader.first['id'] as num).toInt();

            await client
                .from('returns')
                .update(headerPayload)
                .eq('id', cloudReturnId);
          }

          final existingCloudLines = await client
              .from('return_lines')
              .select('id')
              .eq('return_id', cloudReturnId)
              .limit(1);

          if (existingCloudLines.isEmpty) {
            for (final line in localLines) {
              final linePayload = <String, Object?>{
                'return_id': cloudReturnId,
                'inventory_client_uid':
                    (line['inventory_client_uid'] ?? '')
                        .toString(),
                'tile_name':
                    (line['tile_name'] ?? '').toString(),
                'quantity':
                    (line['quantity'] as num?)?.toInt() ?? 0,
                'unit_price':
                    (line['unit_price'] as num?)?.toDouble() ?? 0,
                'line_total':
                    (line['line_total'] as num?)?.toDouble() ?? 0,
              };

              await client
                  .from('return_lines')
                  .insert(linePayload);
            }
          }

          await LocalDb.instance.markReturnSynced(
            localReturnId,
          );
          returnsUploaded++;
        }
      } catch (_) {
        // Returns remain safely pending if the return cloud schema is unavailable.
      }

      final now =
          DateTime.now().toLocal().toString().split('.').first;
      await LocalDb.instance.setLastSync(now);

      return 'Sync complete: '
          '$inventoryUploaded inventory, '
          '$salesUploaded sales, '
          '$returnsUploaded returns uploaded.';
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

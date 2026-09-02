import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'image_storage_service.dart';
import 'auth_service.dart';
import 'local_db.dart';

class SyncService {
  SyncService._();

  static final SyncService instance = SyncService._();

  final _status = StreamController<bool>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _syncing = false;
  DateTime? _syncStartedAt;

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
    final now = DateTime.now();
    if (_syncing) {
      final started = _syncStartedAt;
      if (started != null && now.difference(started) > const Duration(minutes: 2)) {
        _syncing = false;
        _syncStartedAt = null;
      } else {
        return 'Sync already running';
      }
    }
    _syncing = true;
    _syncStartedAt = now;
    try {
      return await _runSync().timeout(const Duration(minutes: 2));
    } on TimeoutException {
      return 'Sync timed out. Please check internet and try Sync Now again.';
    } finally {
      _syncing = false;
      _syncStartedAt = null;
    }
  }

  Future<String> _runSync() async {
    try {
      if (!await isOnline()) {
        _status.add(false);
        return 'Offline. Data remains safe on this phone.';
      }

      _status.add(true);
      final client = Supabase.instance.client;
      final isAdmin = await AuthService().isAdmin();
      await LocalDb.instance.ensureLegacySyncColumns();

      var inventoryUploaded = 0;
      var salesUploaded = 0;
      var returnsUploaded = 0;
      var inventoryDownloaded = 0;
      var salesDownloaded = 0;
      var returnsDownloaded = 0;

      final pendingInventory = await LocalDb.instance.pendingInventory();

      for (final item in pendingInventory) {
        if (item.deleted) {
          if (!isAdmin) return 'Inventory sync error: only Admin can delete inventory.';
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
          final updatePayload = isAdmin
              ? payload
              : <String, Object?>{
                  'stock': item.stock,
                  'image_url': imageUrl,
                  'updated_at': item.updatedAt,
                };
          await client
              .from('inventory')
              .update(updatePayload)
              .eq('id', cloudId!);
        } else {
          if (!isAdmin) {
            return 'Inventory sync error: only Admin can create inventory.';
          }
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

      // Process durable Admin deletion queue before downloading cloud data.
      final pendingDeletions = await LocalDb.instance.pendingDeletions();
      for (final deletion in pendingDeletions) {
        if (!isAdmin) break;
        final deletionId = (deletion['id'] as num).toInt();
        final type = (deletion['entity_type'] ?? '').toString();
        final key = (deletion['entity_key'] ?? '').toString();
        final uid = (deletion['entity_uid'] ?? '').toString();

        // Persist a deletion tombstone before deleting the cloud row. Every
        // phone reads these tombstones, so old local copies cannot reappear.
        await client.from('sync_tombstones').upsert(
          {
            'entity_type': type,
            'entity_uid': uid.isEmpty ? null : uid,
            'entity_key': key,
            'deleted_at': DateTime.now().toUtc().toIso8601String(),
            'created_by': client.auth.currentUser?.id,
          },
          onConflict: 'entity_type,entity_key',
        );

        if (type == 'return') {
          final rows = uid.isNotEmpty
              ? await client.from('returns').select('id').eq('sync_uid', uid).limit(1)
              : await client.from('returns').select('id').eq('return_no', key).limit(1);
          if (rows.isNotEmpty) {
            final returnId = (rows.first['id'] as num).toInt();
            await client.from('return_lines').delete().eq('return_id', returnId);
            await client.from('returns').delete().eq('id', returnId);
          }
        } else if (type == 'sale') {
          if (uid.isNotEmpty) {
            await client.from('sales').delete().eq('sync_uid', uid);
          } else {
            await client.from('sales').delete().eq('invoice_no', key);
          }
        }
        await LocalDb.instance.markDeletionSynced(deletionId);
      }

      // Apply cloud deletions on every phone before any Sales/Returns upload
      // or download. The display key fallback removes legacy v1.6.18 copies
      // which may have different sync_uid values on different phones.
      final tombstones = await client
          .from('sync_tombstones')
          .select('entity_type, entity_uid, entity_key');
      for (final raw in tombstones) {
        final tombstone = Map<String, dynamic>.from(raw);
        final type = (tombstone['entity_type'] ?? '').toString();
        final uid = (tombstone['entity_uid'] ?? '').toString();
        final key = (tombstone['entity_key'] ?? '').toString();
        if (type == 'sale') {
          await LocalDb.instance.applyRemoteSaleDeletion(
            syncUid: uid,
            invoiceNo: key,
          );
        } else if (type == 'return') {
          await LocalDb.instance.applyRemoteReturnDeletion(
            syncUid: uid,
            returnNo: key,
          );
        }
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
        inventoryDownloaded++;
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

          final localId = (sale['id'] as num).toInt();
          var saleSyncUid = (sale['sync_uid'] ?? '').toString();
          if (saleSyncUid.isEmpty) {
            saleSyncUid = await LocalDb.instance.ensureSaleSyncUid(localId);
            sale['sync_uid'] = saleSyncUid;
          }
          sale.remove('id');
          sale.remove('sync_state');
          sale.remove('customer_id');

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

          final originalInvoiceNo =
              (sale['invoice_no'] ?? '').toString();

          // Supabase is the single authority for final invoice numbering.
          // The RPC is atomic and idempotent by sync_uid, so simultaneous
          // offline phones receive different sequential numbers.
          final allocatedInvoice = await client.rpc(
            'allocate_document_number',
            params: {
              'p_kind': 'sale',
              'p_sync_uid': saleSyncUid,
              'p_created_at': (sale['created_at'] ?? '').toString(),
            },
          );
          final candidateInvoiceNo = allocatedInvoice.toString();
          if (candidateInvoiceNo.isEmpty) {
            throw StateError('Supabase did not allocate an invoice number.');
          }
          if (candidateInvoiceNo != originalInvoiceNo) {
            await LocalDb.instance.renameSaleInvoiceForSync(
              localId,
              candidateInvoiceNo,
            );
            sale['invoice_no'] = candidateInvoiceNo;
          }

          await client
              .from('sales')
              .upsert(sale, onConflict: 'sync_uid');

          await LocalDb.instance.markSaleSynced(localId);
          salesUploaded++;
        }

        final cloudSales = await client
            .from('sales')
            .select('*')
            .order('created_at');

        final cloudSaleUids = <String>{};
        for (final row in cloudSales) {
          final cloudSale = Map<String, dynamic>.from(row);
          final uid = (cloudSale['sync_uid'] ?? '').toString();
          if (uid.isNotEmpty) cloudSaleUids.add(uid);
          final changed = await LocalDb.instance.upsertCloudSale(cloudSale);
          if (changed) salesDownloaded++;
        }
        await LocalDb.instance.pruneSyncedSales(cloudSaleUids);
      } catch (e) {
        return 'Sales sync error: $e';
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
          var returnSyncUid = (localHeader['sync_uid'] ?? '').toString();
          if (returnSyncUid.isEmpty) {
            returnSyncUid =
                await LocalDb.instance.ensureReturnSyncUid(localReturnId);
          }
          final localSaleId = (localHeader['sale_id'] as num).toInt();
          final saleSyncUid =
              await LocalDb.instance.ensureSaleSyncUid(localSaleId);
          final originalReturnNo =
              (localHeader['return_no'] ?? '').toString();
          final localInvoiceNo =
              (localHeader['invoice_no'] ?? '').toString();

          // Final return number is also allocated centrally during sync.
          final allocatedReturn = await client.rpc(
            'allocate_document_number',
            params: {
              'p_kind': 'return',
              'p_sync_uid': returnSyncUid,
              'p_created_at': (localHeader['return_date'] ?? '').toString(),
            },
          );
          final returnNo = allocatedReturn.toString();
          if (returnNo.isEmpty) {
            throw StateError('Supabase did not allocate a return number.');
          }
          if (returnNo != originalReturnNo) {
            await LocalDb.instance.renameReturnNoForSync(
              localReturnId,
              returnNo,
            );
          }

          final headerPayload = <String, Object?>{
            'sync_uid': returnSyncUid,
            'sale_sync_uid': saleSyncUid,
            'return_no': returnNo,
            'sale_invoice_no':
                localInvoiceNo,
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

          var existingHeader = await client
              .from('returns')
              .select('id')
              .eq('sync_uid', returnSyncUid)
              .limit(1);
          if (existingHeader.isEmpty) {
            existingHeader = await client
                .from('returns')
                .select('id')
                .eq('return_no', returnNo)
                .limit(1);
          }

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

          // Replace cloud return lines so Admin edits sync correctly.
          await client.from('return_lines').delete().eq('return_id', cloudReturnId);
          for (final line in localLines) {
            final linePayload = <String, Object?>{
              'return_id': cloudReturnId,
              'inventory_client_uid': (line['inventory_client_uid'] ?? '').toString(),
              'tile_name': (line['tile_name'] ?? '').toString(),
              'quantity': (line['quantity'] as num?)?.toInt() ?? 0,
              'unit_price': (line['unit_price'] as num?)?.toDouble() ?? 0,
              'line_total': (line['line_total'] as num?)?.toDouble() ?? 0,
            };
            await client.from('return_lines').insert(linePayload);
          }

          await LocalDb.instance.markReturnSynced(
            localReturnId,
          );
          returnsUploaded++;
        }

        // Pull cloud returns so returns created on another phone
        // become visible on this phone after Sync Now.
        final cloudReturns = await client
            .from('returns')
            .select('*')
            .order('return_date');

        final cloudReturnUids = <String>{};
        for (final row in cloudReturns) {
          final header = Map<String, dynamic>.from(row);
          final uid = (header['sync_uid'] ?? '').toString();
          if (uid.isNotEmpty) cloudReturnUids.add(uid);
          final cloudReturnId = (header['id'] as num?)?.toInt();
          if (cloudReturnId == null) continue;

          final lineRows = await client
              .from('return_lines')
              .select('*')
              .eq('return_id', cloudReturnId);

          final lines = lineRows
              .map((e) => Map<String, dynamic>.from(e))
              .toList();

          final changed = await LocalDb.instance.upsertCloudReturn(
            header,
            lines,
          );
          if (changed) returnsDownloaded++;
        }
        await LocalDb.instance.pruneSyncedReturns(cloudReturnUids);
      } catch (e) {
        return 'Returns sync error: $e';
      }

      final now =
          DateTime.now().toLocal().toString().split('.').first;
      await LocalDb.instance.setLastSync(now);

      return 'Sync complete: '
          'Inventory $inventoryUploaded up / $inventoryDownloaded down, '
          'Sales $salesUploaded up / $salesDownloaded down, '
          'Returns $returnsUploaded up / $returnsDownloaded down.';
    } catch (e) {
      return 'Sync error: $e';
    }
  }

  void dispose() {
    _subscription?.cancel();
    _status.close();
  }
}

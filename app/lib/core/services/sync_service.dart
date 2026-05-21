import 'package:dio/dio.dart';
import 'package:gg_store_cashier/core/services/offline_queue.dart';
import 'package:gg_store_cashier/core/services/pending_operations_queue.dart';
import 'package:gg_store_cashier/core/services/auth_service.dart';
import 'package:gg_store_cashier/core/config/api_config.dart';
import 'package:gg_store_cashier/shared/utils/snackbar_service.dart';

class SyncService {
  static final _dio = Dio(BaseOptions(
    connectTimeout: ApiConfig.connectTimeout,
    receiveTimeout: ApiConfig.receiveTimeout,
    sendTimeout: ApiConfig.sendTimeout,
    headers: ApiConfig.defaultHeaders,
  ));

  /// Syncs all pending items: generic operations first, then transactions.
  static Future<void> syncAll() async {
    await _syncPendingOperations();
    await _syncTransactions();
  }

  // ── Generic pending operations (branch edits, user CRUD) ──────────────────

  static Future<void> _syncPendingOperations() async {
    final pending = PendingOperationsQueue.getPending();
    for (final op in pending) {
      await _submitOperation(op);
    }
  }

  static Future<void> _submitOperation(PendingOperation op) async {
    try {
      final token = await AuthService.getToken();
      final options = Options(
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
      final url = '${ApiConfig.apiUrl}${op.path}';
      final body = Map<String, dynamic>.from(op.body);

      switch (op.method) {
        case 'PUT':
          await _dio.put(url, data: body, options: options);
        case 'POST':
          await _dio.post(url, data: body, options: options);
        case 'DELETE':
          await _dio.delete(url, options: options);
        default:
          await _dio.put(url, data: body, options: options);
      }

      await PendingOperationsQueue.remove(op.id);
      SnackBarService.show('${op.description} berhasil disinkronkan');
    } catch (_) {
      op.retryCount += 1;
      if (op.retryCount >= 3) {
        await PendingOperationsQueue.markFailed(op.id);
        SnackBarService.error('${op.description} gagal dikirim setelah 3 percobaan');
      } else {
        await op.save();
      }
    }
  }

  // ── Cashier transactions ───────────────────────────────────────────────────

  static Future<void> _syncTransactions() async {
    final pending = OfflineQueue.getPending();
    for (final entry in pending) {
      await _submitEntry(entry);
    }
  }

  static Future<void> _submitEntry(OfflineTransactionEntry entry) async {
    try {
      final token = await AuthService.getToken();
      await _dio.post(
        '${ApiConfig.apiUrl}/api/transactions',
        data: Map<String, dynamic>.from(entry.payload),
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        ),
      );

      await OfflineQueue.remove(entry.uuid);
      SnackBarService.show('Transaksi berhasil disinkronkan');
    } catch (_) {
      entry.retryCount += 1;
      if (entry.retryCount >= 3) {
        await OfflineQueue.markFailed(entry.uuid);
        SnackBarService.error('Transaksi gagal dikirim setelah 3 percobaan');
      } else {
        await entry.save();
      }
    }
  }
}

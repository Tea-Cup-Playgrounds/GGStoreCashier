import 'dart:async';

import 'package:dio/dio.dart';
import 'package:gg_store_cashier/core/services/offline_queue.dart';
import 'package:gg_store_cashier/core/services/pending_operations_queue.dart';
import 'package:gg_store_cashier/core/services/auth_service.dart';
import 'package:gg_store_cashier/core/config/api_config.dart';
import 'package:gg_store_cashier/shared/utils/snackbar_service.dart';

/// Thrown to stop a sync run without counting an attempt against the item: the server couldn't be
/// reached, or asked us to slow down (429). [retryAfter] is set for the latter.
class _SyncPaused implements Exception {
  final Duration? retryAfter;
  const _SyncPaused([this.retryAfter]);
}

class SyncService {
  static final _dio = Dio(BaseOptions(
    connectTimeout: ApiConfig.connectTimeout,
    receiveTimeout: ApiConfig.receiveTimeout,
    sendTimeout: ApiConfig.sendTimeout,
    headers: ApiConfig.defaultHeaders,
  ));

  static bool _running = false;
  static Timer? _retryTimer;

  /// Syncs all pending items: generic operations first, then transactions. Runs one at a time;
  /// when the server rate-limits, it stops and tries again after the server's Retry-After.
  static Future<void> syncAll() async {
    if (_running) return;
    _running = true;
    _retryTimer?.cancel();
    try {
      await _syncPendingOperations();
      await _syncTransactions();
    } on _SyncPaused catch (pause) {
      if (pause.retryAfter != null) _retryTimer = Timer(pause.retryAfter!, syncAll);
    } finally {
      _running = false;
    }
  }

  /// Rethrows network failures and 429s as [_SyncPaused]; other errors (the server rejected the
  /// item) are left to the caller, which counts them as a failed attempt.
  static void _pauseIfTransient(Object error) {
    if (error is! DioException) return;
    final status = error.response?.statusCode;
    if (status == 429) {
      final seconds = int.tryParse(error.response?.headers.value('retry-after') ?? '') ?? 30;
      throw _SyncPaused(Duration(seconds: seconds.clamp(1, 300)));
    }
    if (error.response == null) throw const _SyncPaused();
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
    } catch (e) {
      _pauseIfTransient(e);
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
        // The payload is a full POST /api/sales body with its own id, so a retry after a lost
        // response returns the stored sale instead of creating a second one.
        '${ApiConfig.apiUrl}/api/sales',
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
    } catch (e) {
      _pauseIfTransient(e);
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

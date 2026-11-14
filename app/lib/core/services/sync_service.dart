import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:gg_store_cashier/core/services/offline_queue.dart';
import 'package:gg_store_cashier/core/services/pending_operations_queue.dart';
import 'package:gg_store_cashier/core/services/auth_service.dart';
import 'package:gg_store_cashier/core/config/api_config.dart';
import 'package:gg_store_cashier/shared/utils/snackbar_service.dart';

/// Thrown to stop a sync run without counting an attempt against the item: the server couldn't be
/// reached, is having trouble (5xx), asked us to slow down (429), or the login expired (401).
/// [retryAfter] schedules the next run.
class _SyncPaused implements Exception {
  final Duration? retryAfter;
  const _SyncPaused([this.retryAfter]);
}

/// Sends what was saved on this device while offline: queued sales and other queued changes.
///
/// - Runs when the app opens (after login), every minute while something is waiting, and when the
///   connection comes back.
/// - "The server couldn't be reached / had a problem / the login expired" never counts against a
///   sale: it just waits. Only a refusal from the server (4xx) counts; after 3 the sale is marked
///   failed and shown on the sync screen. Nothing is ever deleted automatically.
class SyncService {
  static final _dio = Dio(BaseOptions(
    connectTimeout: ApiConfig.connectTimeout,
    receiveTimeout: ApiConfig.receiveTimeout,
    sendTimeout: ApiConfig.sendTimeout,
    headers: ApiConfig.defaultHeaders,
  ));

  static bool _running = false;
  static Timer? _retryTimer;
  static Timer? _periodic;
  static int _sentThisRun = 0;

  /// True after the server answered 401: the saved login expired (or the account was switched
  /// off). Queued sales keep waiting until someone logs in again.
  static final ValueNotifier<bool> needsLogin = ValueNotifier(false);

  /// True while a sync run is in progress.
  static final ValueNotifier<bool> isRunning = ValueNotifier(false);

  /// Syncs now, and then every minute while anything is waiting. Safe to call more than once:
  /// every call (e.g. after logging in again) triggers a run.
  static void start() {
    _periodic ??= Timer.periodic(const Duration(minutes: 1), (_) {
      if (OfflineQueue.pendingCount > 0 || PendingOperationsQueue.pendingCount > 0) syncAll();
    });
    syncAll();
  }

  /// Syncs all pending items: generic operations first, then sales, one at a time.
  static Future<void> syncAll() async {
    if (_running) return;
    if (await AuthService.getToken() == null) return; // nobody logged in: wait for a login
    _running = true;
    isRunning.value = true;
    _retryTimer?.cancel();
    _sentThisRun = 0;
    try {
      await _syncPendingOperations();
      await _syncTransactions();
      needsLogin.value = false;
    } on _SyncPaused catch (pause) {
      if (pause.retryAfter != null) _retryTimer = Timer(pause.retryAfter!, syncAll);
    } finally {
      _running = false;
      isRunning.value = false;
      if (_sentThisRun > 0) {
        SnackBarService.success(_sentThisRun == 1 ? '1 transaksi offline terkirim' : '$_sentThisRun transaksi offline terkirim');
      }
    }
  }

  /// Stops the run for errors that aren't the item's fault (see [_SyncPaused]). Anything else is
  /// left to the caller as "the server refused this item".
  static void _pauseIfTransient(Object error) {
    if (error is! DioException) return;
    final response = error.response;
    if (response == null) throw const _SyncPaused(); // server not reached; the next run retries
    final status = response.statusCode ?? 0;
    if (status == 401) {
      needsLogin.value = true;
      throw const _SyncPaused();
    }
    if (status == 429) {
      final seconds = int.tryParse(response.headers.value('retry-after') ?? '') ?? 30;
      throw _SyncPaused(Duration(seconds: seconds.clamp(1, 300)));
    }
    if (status >= 500) throw const _SyncPaused(Duration(minutes: 1));
  }

  /// 403: the person logged in now may not sell at that location (another cashier's sale). Not a
  /// problem with the sale itself, so it waits for someone who may, without counting an attempt.
  static bool _isForbidden(Object error) => error is DioException && error.response?.statusCode == 403;

  static String _messageOf(Object error) {
    if (error is DioException) {
      final body = error.response?.data;
      if (body is Map && body['error'] != null) return body['error'].toString();
      return 'Ditolak server (${error.response?.statusCode ?? error.type.name})';
    }
    return error.toString();
  }

  static Future<Options> _authOptions() async {
    final token = await AuthService.getToken();
    return Options(headers: {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    });
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
      final options = await _authOptions();
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
      if (_isForbidden(e)) return;
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
      await _dio.post(
        // The payload is a full POST /api/sales body with its own id, so a retry after a lost
        // response returns the stored sale instead of creating a second one. It is marked
        // offline, so the server records it as it happened and flags differences for review.
        '${ApiConfig.apiUrl}/api/sales',
        data: Map<String, dynamic>.from(entry.payload),
        options: await _authOptions(),
      );

      await OfflineQueue.remove(entry.uuid);
      _sentThisRun++;
    } catch (e) {
      _pauseIfTransient(e);
      entry
        ..lastAttemptAt = DateTime.now()
        ..lastError = _messageOf(e);
      if (_isForbidden(e)) {
        await entry.save();
        return;
      }
      entry.retryCount += 1;
      if (entry.retryCount >= 3) {
        entry.status = 'failed';
        SnackBarService.error('Server menolak transaksi offline — lihat menu Sinkronisasi');
      }
      await entry.save();
    }
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:developer' as dev;
import 'dart:async';
import '../services/socket_service.dart';
import '../database/product_dao.dart';
import '../database/voucher_dao.dart';
import '../database/user_dao.dart';
import '../database/live_transaction_dao.dart';
import '../models/product.dart';
import '../models/voucher.dart';
import '../models/user.dart';
import '../models/superadmin_dashboard.dart' show LiveTransaction;

// ═══════════════════════════════════════════════════════════════════════════
// Architecture
// ───────────────────────────────────────────────────────────────────────────
// SQLite is the single source of truth for ALL high-frequency data.
// WS event → SQLite write → 500 ms poll tick → StateNotifier state → Widget
//
// Low-frequency data (categories, branches) is NOT here.
// Those use pull-to-refresh + HTTP cache only.
// ═══════════════════════════════════════════════════════════════════════════

Map<String, dynamic> _toMap(dynamic raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is! Map) return {};
  return raw.map((k, v) => MapEntry(k.toString(), v));
}

// ─────────────────────────────────────────────────────────────────────────────
// Product Store  (inventory + cashier)
// ─────────────────────────────────────────────────────────────────────────────

class ProductStoreNotifier extends StateNotifier<List<Product>> {
  ProductStoreNotifier({this.branchId}) : super(const []) {
    _init();
  }

  final int? branchId;
  Timer? _pollTimer;

  Future<void> _init() async {
    SocketService.subscribe('products');
    SocketService.on('product-created', _onCreate);
    SocketService.on('product-updated', _onUpdate);
    SocketService.on('product-deleted', _onDelete);
    await _poll();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => _poll());
  }

  void _onCreate(dynamic data) async {
    if (!mounted) return;
    try {
      await ProductDao.upsert(Product.fromJson(_toMap(data)));
    } catch (e) {
      dev.log('product-created error: $e', name: 'PRODUCT_STORE');
    }
  }

  void _onUpdate(dynamic data) async {
    if (!mounted) return;
    try {
      await ProductDao.upsert(Product.fromJson(_toMap(data)));
    } catch (e) {
      dev.log('product-updated error: $e', name: 'PRODUCT_STORE');
    }
  }

  void _onDelete(dynamic data) async {
    if (!mounted) return;
    try {
      final map = _toMap(data);
      await ProductDao.delete((map['id'] ?? '').toString());
    } catch (e) {
      dev.log('product-deleted error: $e', name: 'PRODUCT_STORE');
    }
  }

  Future<void> _poll() async {
    if (!mounted) return;
    try {
      final products = await ProductDao.getAll(branchId: branchId);
      if (mounted) state = products;
    } catch (e) {
      dev.log('ProductStore poll error: $e', name: 'PRODUCT_STORE');
    }
  }

  /// Seed the DB from an HTTP response (called after initial network fetch).
  Future<void> seedFromHttp(List<Product> products) async {
    await ProductDao.upsertBatch(products);
    await _poll();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    SocketService.off('product-created', _onCreate);
    SocketService.off('product-updated', _onUpdate);
    SocketService.off('product-deleted', _onDelete);
    SocketService.unsubscribe('products');
    super.dispose();
  }
}

final productStoreProvider = StateNotifierProvider.family<ProductStoreNotifier, List<Product>, int?>(
  (ref, branchId) => ProductStoreNotifier(branchId: branchId),
);

// ─────────────────────────────────────────────────────────────────────────────
// Voucher Store
// ─────────────────────────────────────────────────────────────────────────────

class VoucherStoreNotifier extends StateNotifier<List<Voucher>> {
  VoucherStoreNotifier() : super(const []) {
    _init();
  }

  Timer? _pollTimer;

  Future<void> _init() async {
    SocketService.subscribe('vouchers');
    SocketService.on('voucher-created', _onCreate);
    SocketService.on('voucher-updated', _onUpdate);
    SocketService.on('voucher-deleted', _onDelete);
    await _poll();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => _poll());
  }

  void _onCreate(dynamic data) async {
    if (!mounted) return;
    try {
      await VoucherDao.upsert(Voucher.fromJson(_toMap(data)));
    } catch (e) {
      dev.log('voucher-created error: $e', name: 'VOUCHER_STORE');
    }
  }

  void _onUpdate(dynamic data) async {
    if (!mounted) return;
    try {
      await VoucherDao.upsert(Voucher.fromJson(_toMap(data)));
    } catch (e) {
      dev.log('voucher-updated error: $e', name: 'VOUCHER_STORE');
    }
  }

  void _onDelete(dynamic data) async {
    if (!mounted) return;
    try {
      final map = _toMap(data);
      final id = map['id'];
      if (id != null) {
        await VoucherDao.delete(id is int ? id : int.tryParse(id.toString()) ?? 0);
      }
    } catch (e) {
      dev.log('voucher-deleted error: $e', name: 'VOUCHER_STORE');
    }
  }

  Future<void> _poll() async {
    if (!mounted) return;
    try {
      final vouchers = await VoucherDao.getAll();
      if (mounted) state = vouchers;
    } catch (e) {
      dev.log('VoucherStore poll error: $e', name: 'VOUCHER_STORE');
    }
  }

  /// Seed DB from an HTTP response (called after initial fetch).
  Future<void> seedFromHttp(List<Voucher> vouchers) async {
    await VoucherDao.upsertBatch(vouchers);
    await _poll();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    SocketService.off('voucher-created', _onCreate);
    SocketService.off('voucher-updated', _onUpdate);
    SocketService.off('voucher-deleted', _onDelete);
    SocketService.unsubscribe('vouchers');
    super.dispose();
  }
}

final voucherStoreProvider = StateNotifierProvider<VoucherStoreNotifier, List<Voucher>>(
  (ref) => VoucherStoreNotifier(),
);

// ─────────────────────────────────────────────────────────────────────────────
// User Store
// ─────────────────────────────────────────────────────────────────────────────

class UserStoreNotifier extends StateNotifier<List<User>> {
  UserStoreNotifier({this.branchId}) : super(const []) {
    _init();
  }

  final int? branchId;
  Timer? _pollTimer;

  Future<void> _init() async {
    SocketService.subscribe('users');
    SocketService.on('user-created', _onCreate);
    SocketService.on('user-updated', _onUpdate);
    SocketService.on('user-deleted', _onDelete);
    await _poll();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => _poll());
  }

  void _onCreate(dynamic data) async {
    if (!mounted) return;
    try {
      await UserDao.upsert(User.fromJson(_toMap(data)));
    } catch (e) {
      dev.log('user-created error: $e', name: 'USER_STORE');
    }
  }

  void _onUpdate(dynamic data) async {
    if (!mounted) return;
    try {
      await UserDao.upsert(User.fromJson(_toMap(data)));
    } catch (e) {
      dev.log('user-updated error: $e', name: 'USER_STORE');
    }
  }

  void _onDelete(dynamic data) async {
    if (!mounted) return;
    try {
      final map = _toMap(data);
      final id = map['id'];
      if (id != null) {
        await UserDao.delete(id is int ? id : int.tryParse(id.toString()) ?? 0);
      }
    } catch (e) {
      dev.log('user-deleted error: $e', name: 'USER_STORE');
    }
  }

  Future<void> _poll() async {
    if (!mounted) return;
    try {
      final users = await UserDao.getAll(branchId: branchId);
      if (mounted) state = users;
    } catch (e) {
      dev.log('UserStore poll error: $e', name: 'USER_STORE');
    }
  }

  /// Seed DB from an HTTP response (called after initial fetch).
  Future<void> seedFromHttp(List<User> users) async {
    await UserDao.upsertBatch(users);
    await _poll();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    SocketService.off('user-created', _onCreate);
    SocketService.off('user-updated', _onUpdate);
    SocketService.off('user-deleted', _onDelete);
    SocketService.unsubscribe('users');
    super.dispose();
  }
}

final userStoreProvider = StateNotifierProvider.family<UserStoreNotifier, List<User>, int?>(
  (ref, branchId) => UserStoreNotifier(branchId: branchId),
);

// ─────────────────────────────────────────────────────────────────────────────
// Live Transaction Store  (dashboard feed — 500 ms poll, no refresh needed)
// ─────────────────────────────────────────────────────────────────────────────

class LiveTransactionStoreNotifier extends StateNotifier<List<LiveTransaction>> {
  LiveTransactionStoreNotifier() : super(const []) {
    _init();
  }

  Timer? _pollTimer;

  Future<void> _init() async {
    // Listen for both transaction events — the server emits transaction-created
    // with the full transaction row AND payment-completed when payment is recorded.
    SocketService.subscribe('live_transactions');
    SocketService.on('transaction-created', _onCreated);
    SocketService.on('payment-completed', _onCompleted);
    // Also listen for the superadmin live-update which embeds newTransaction
    SocketService.on('dashboard:live-update', _onDashboardUpdate);
    await _poll();
    // 500 ms poll keeps the UI feeling live regardless of socket state
    _pollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => _poll());
  }

  void _onCreated(dynamic data) async {
    if (!mounted) return;
    try {
      final map = _toMap(data);
      // Server sends final_amount; normalise item_count from nested field too
      await LiveTransactionDao.upsertFromJson(map);
    } catch (e) {
      dev.log('transaction-created error: $e', name: 'LIVE_TX_STORE');
    }
  }

  void _onCompleted(dynamic data) async {
    if (!mounted) return;
    try {
      final map = _toMap(data);
      // payment-completed carries transactionId but not the full row —
      // only upsert if it has enough fields (final_amount present)
      if (map.containsKey('final_amount') || map.containsKey('finalAmount')) {
        await LiveTransactionDao.upsertFromJson(map);
      }
    } catch (e) {
      dev.log('payment-completed error: $e', name: 'LIVE_TX_STORE');
    }
  }

  void _onDashboardUpdate(dynamic data) async {
    if (!mounted) return;
    try {
      final map = _toMap(data);
      final txMap = map['newTransaction'];
      if (txMap != null) {
        await LiveTransactionDao.upsertFromJson(_toMap(txMap));
      }
    } catch (e) {
      dev.log('dashboard:live-update tx extract error: $e', name: 'LIVE_TX_STORE');
    }
  }

  Future<void> _poll() async {
    if (!mounted) return;
    try {
      final txs = await LiveTransactionDao.getRecent(limit: 20);
      if (mounted) state = txs;
    } catch (e) {
      dev.log('LiveTxStore poll error: $e', name: 'LIVE_TX_STORE');
    }
  }

  /// Seed the local DB from an HTTP payload (called after initial load or refresh).
  Future<void> seedFromHttp(List<LiveTransaction> txs) async {
    for (final tx in txs) {
      await LiveTransactionDao.upsert(tx);
    }
    await _poll();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    SocketService.off('transaction-created', _onCreated);
    SocketService.off('payment-completed', _onCompleted);
    SocketService.off('dashboard:live-update', _onDashboardUpdate);
    SocketService.unsubscribe('live_transactions');
    super.dispose();
  }
}

final liveTransactionStoreProvider = StateNotifierProvider<LiveTransactionStoreNotifier, List<LiveTransaction>>(
  (ref) => LiveTransactionStoreNotifier(),
);

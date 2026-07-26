import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:developer' as dev;
import '../services/socket_service.dart';
import '../services/cache_manager.dart';
import '../models/product.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Real-time product state
// ─────────────────────────────────────────────────────────────────────────────

class RealtimeProductState {
  final Product? lastCreated;
  final Product? lastUpdated;
  final String? lastDeleted;
  final DateTime? lastUpdateTime;

  const RealtimeProductState({
    this.lastCreated,
    this.lastUpdated,
    this.lastDeleted,
    this.lastUpdateTime,
  });

  RealtimeProductState copyWith({
    Product? lastCreated,
    Product? lastUpdated,
    String? lastDeleted,
    DateTime? lastUpdateTime,
  }) {
    return RealtimeProductState(
      lastCreated: lastCreated ?? this.lastCreated,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      lastDeleted: lastDeleted ?? this.lastDeleted,
      lastUpdateTime: lastUpdateTime ?? this.lastUpdateTime,
    );
  }

  /// Apply the latest socket delta to [current] list without a network round-trip.
  ///
  /// - `lastCreated` → prepend if not already in list (by id).
  /// - `lastUpdated` → replace in-place by id, or append if missing.
  /// - `lastDeleted` → remove by id.
  ///
  /// Returns a new list; the original is unchanged.
  List<Product> applyDelta(List<Product> current) {
    List<Product> result = List.of(current);

    if (lastDeleted != null) {
      result.removeWhere((p) => p.id == lastDeleted);
    }

    if (lastUpdated != null) {
      final idx = result.indexWhere((p) => p.id == lastUpdated!.id);
      if (idx >= 0) {
        result[idx] = lastUpdated!;
      } else {
        result.insert(0, lastUpdated!);
      }
    }

    if (lastCreated != null) {
      final alreadyExists = result.any((p) => p.id == lastCreated!.id);
      if (!alreadyExists) {
        result.insert(0, lastCreated!);
      }
    }

    return result;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Real-time transaction state
// ─────────────────────────────────────────────────────────────────────────────

class RealtimeTransactionState {
  final Map<String, dynamic>? lastTransaction;
  final Map<String, dynamic>? lastPayment;
  final DateTime? lastUpdateTime;

  const RealtimeTransactionState({
    this.lastTransaction,
    this.lastPayment,
    this.lastUpdateTime,
  });

  RealtimeTransactionState copyWith({
    Map<String, dynamic>? lastTransaction,
    Map<String, dynamic>? lastPayment,
    DateTime? lastUpdateTime,
  }) {
    return RealtimeTransactionState(
      lastTransaction: lastTransaction ?? this.lastTransaction,
      lastPayment: lastPayment ?? this.lastPayment,
      lastUpdateTime: lastUpdateTime ?? this.lastUpdateTime,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Product real-time notifier
// ─────────────────────────────────────────────────────────────────────────────

class RealtimeProductNotifier extends StateNotifier<RealtimeProductState> {
  RealtimeProductNotifier() : super(const RealtimeProductState()) {
    _setupListeners();
  }

  void _setupListeners() {
    SocketService.on('product-created', _handleProductCreated);
    SocketService.on('product-updated', _handleProductUpdated);
    SocketService.on('product-deleted', _handleProductDeleted);
  }

  void _handleProductCreated(dynamic data) {
    if (!mounted) return;
    try {
      final product = Product.fromJson(_toStringDynamicMap(data));
      state = state.copyWith(
        lastCreated: product,
        lastUpdateTime: DateTime.now(),
      );
      // Invalidate cache to force fresh data on next load
      CacheManager.invalidate('products:branch_${product.branchId}');
    } catch (e) {
      dev.log('Error parsing product-created event: $e', name: 'REALTIME_PRODUCT');
    }
  }

  void _handleProductUpdated(dynamic data) {
    if (!mounted) return;
    try {
      final product = Product.fromJson(_toStringDynamicMap(data));
      state = state.copyWith(
        lastUpdated: product,
        lastUpdateTime: DateTime.now(),
      );
      // Invalidate cache to force fresh data on next load
      CacheManager.invalidate('products:branch_${product.branchId}');
    } catch (e) {
      dev.log('Error parsing product-updated event: $e', name: 'REALTIME_PRODUCT');
    }
  }

  void _handleProductDeleted(dynamic data) {
    if (!mounted) return;
    try {
      final map = _toStringDynamicMap(data);
      final productId = (map['id'] ?? '').toString();
      final branchId = (map['branch_id'] ?? map['branchId'] ?? '').toString();
      state = state.copyWith(
        lastDeleted: productId,
        lastUpdateTime: DateTime.now(),
      );
      // Invalidate cache to force fresh data on next load
      if (branchId.isNotEmpty) {
        CacheManager.invalidate('products:branch_$branchId');
      }
    } catch (e) {
      dev.log('Error parsing product-deleted event: $e', name: 'REALTIME_PRODUCT');
    }
  }

  /// Helper — socket.io sometimes delivers maps as Map<Object?, Object?>.
  static Map<String, dynamic> _toStringDynamicMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is! Map) return {};
    return raw.map((k, v) => MapEntry(k.toString(), v));
  }

  @override
  void dispose() {
    // Unbind all product event callbacks
    SocketService.off('product-created', _handleProductCreated);
    SocketService.off('product-updated', _handleProductUpdated);
    SocketService.off('product-deleted', _handleProductDeleted);

    dev.log('RealtimeProductNotifier disposed and listeners removed.', name: 'REALTIME_PRODUCT');
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Transaction real-time notifier
// ─────────────────────────────────────────────────────────────────────────────

class RealtimeTransactionNotifier extends StateNotifier<RealtimeTransactionState> {
  RealtimeTransactionNotifier() : super(const RealtimeTransactionState()) {
    _setupListeners();
  }

  void _setupListeners() {
    SocketService.on('transaction-created', _handleTransactionCreated);
    SocketService.on('payment-completed', _handlePaymentCompleted);
  }

  void _handleTransactionCreated(dynamic data) {
    if (!mounted) return;
    try {
      state = state.copyWith(
        lastTransaction: _toStringDynamicMap(data),
        lastUpdateTime: DateTime.now(),
      );
    } catch (e) {
      dev.log('Error parsing transaction-created event: $e', name: 'REALTIME_TX');
    }
  }

  void _handlePaymentCompleted(dynamic data) {
    if (!mounted) return;
    try {
      state = state.copyWith(
        lastPayment: _toStringDynamicMap(data),
        lastUpdateTime: DateTime.now(),
      );
    } catch (e) {
      dev.log('Error parsing payment-completed event: $e', name: 'REALTIME_TX');
    }
  }

  static Map<String, dynamic> _toStringDynamicMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is! Map) return {};
    return raw.map((k, v) => MapEntry(k.toString(), v));
  }

  @override
  void dispose() {
    // Clean up socket event listeners to prevent ghost updates and memory leaks
    SocketService.off('transaction-created', _handleTransactionCreated);
    SocketService.off('payment-completed', _handlePaymentCompleted);

    dev.log('RealtimeTransactionNotifier disposed and listeners removed.', name: 'REALTIME_TX');
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Providers
// ─────────────────────────────────────────────────────────────────────────────

final realtimeProductProvider = StateNotifierProvider<RealtimeProductNotifier, RealtimeProductState>(
  (ref) => RealtimeProductNotifier(),
);

final realtimeTransactionProvider = StateNotifierProvider<RealtimeTransactionNotifier, RealtimeTransactionState>(
  (ref) => RealtimeTransactionNotifier(),
);

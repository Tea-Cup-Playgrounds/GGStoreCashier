import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/socket_service.dart';
import '../models/product.dart';

// Real-time product updates state
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
}

// Real-time transaction updates state
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

// Product real-time notifier
class RealtimeProductNotifier extends StateNotifier<RealtimeProductState> {
  RealtimeProductNotifier() : super(const RealtimeProductState()) {
    _setupListeners();
  }

  void _setupListeners() {
    // Listen for product created events
    SocketService.on('product-created', (data) {
      try {
        final product = Product.fromJson(data);
        state = state.copyWith(
          lastCreated: product,
          lastUpdateTime: DateTime.now(),
        );
      } catch (e) {
        print('Error parsing product-created event: $e');
      }
    });

    // Listen for product updated events
    SocketService.on('product-updated', (data) {
      try {
        final product = Product.fromJson(data);
        state = state.copyWith(
          lastUpdated: product,
          lastUpdateTime: DateTime.now(),
        );
      } catch (e) {
        print('Error parsing product-updated event: $e');
      }
    });

    // Listen for product deleted events
    SocketService.on('product-deleted', (data) {
      try {
        final productId = data['id'].toString();
        state = state.copyWith(
          lastDeleted: productId,
          lastUpdateTime: DateTime.now(),
        );
      } catch (e) {
        print('Error parsing product-deleted event: $e');
      }
    });
  }

  @override
  void dispose() {
    // Clean up listeners if needed
    super.dispose();
  }
}

// Transaction real-time notifier
class RealtimeTransactionNotifier extends StateNotifier<RealtimeTransactionState> {
  RealtimeTransactionNotifier() : super(const RealtimeTransactionState()) {
    _setupListeners();
  }

  void _setupListeners() {
    // Listen for transaction created events
    SocketService.on('transaction-created', (data) {
      try {
        state = state.copyWith(
          lastTransaction: data as Map<String, dynamic>,
          lastUpdateTime: DateTime.now(),
        );
      } catch (e) {
        print('Error parsing transaction-created event: $e');
      }
    });

    // Listen for payment completed events
    SocketService.on('payment-completed', (data) {
      try {
        state = state.copyWith(
          lastPayment: data as Map<String, dynamic>,
          lastUpdateTime: DateTime.now(),
        );
      } catch (e) {
        print('Error parsing payment-completed event: $e');
      }
    });
  }

  @override
  void dispose() {
    // Clean up listeners if needed
    super.dispose();
  }
}

// Providers
final realtimeProductProvider = StateNotifierProvider<RealtimeProductNotifier, RealtimeProductState>(
  (ref) => RealtimeProductNotifier(),
);

final realtimeTransactionProvider = StateNotifierProvider<RealtimeTransactionNotifier, RealtimeTransactionState>(
  (ref) => RealtimeTransactionNotifier(),
);

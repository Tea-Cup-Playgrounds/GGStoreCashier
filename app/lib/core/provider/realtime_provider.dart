import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:developer' as dev;
import '../services/socket_service.dart';

// Live updates from the API's Socket.IO rooms (see SocketService). Pages watch lastUpdateTime and
// reload what they show.

/// Stock changed at a location (event `stock-changed`, e.g. after a sale).
class RealtimeProductState {
  final int? locationId;
  final List<int> variantIds;
  final DateTime? lastUpdateTime;

  const RealtimeProductState({this.locationId, this.variantIds = const [], this.lastUpdateTime});
}

/// A sale was recorded (event `sale-created`).
class RealtimeTransactionState {
  final Map<String, dynamic>? lastTransaction;
  final DateTime? lastUpdateTime;

  const RealtimeTransactionState({this.lastTransaction, this.lastUpdateTime});
}

class RealtimeProductNotifier extends StateNotifier<RealtimeProductState> {
  RealtimeProductNotifier() : super(const RealtimeProductState()) {
    SocketService.on('stock-changed', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        state = RealtimeProductState(
          locationId: map['location_id'] as int?,
          variantIds: ((map['variant_ids'] as List?) ?? const []).map((e) => e as int).toList(),
          lastUpdateTime: DateTime.now(),
        );
      } catch (e) {
        dev.log('Error parsing stock-changed event: $e');
      }
    });
  }
}

class RealtimeTransactionNotifier extends StateNotifier<RealtimeTransactionState> {
  RealtimeTransactionNotifier() : super(const RealtimeTransactionState()) {
    SocketService.on('sale-created', (data) {
      try {
        state = RealtimeTransactionState(
          lastTransaction: Map<String, dynamic>.from(data as Map),
          lastUpdateTime: DateTime.now(),
        );
      } catch (e) {
        dev.log('Error parsing sale-created event: $e');
      }
    });
  }
}

final realtimeProductProvider = StateNotifierProvider<RealtimeProductNotifier, RealtimeProductState>(
  (ref) => RealtimeProductNotifier(),
);

final realtimeTransactionProvider = StateNotifierProvider<RealtimeTransactionNotifier, RealtimeTransactionState>(
  (ref) => RealtimeTransactionNotifier(),
);

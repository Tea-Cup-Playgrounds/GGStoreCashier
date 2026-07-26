import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/socket_service.dart';

/// Provides the live Socket.IO connection status as a boolean stream.
///
/// `true`  → connected and receiving real-time events.
/// `false` → disconnected / reconnecting.
///
/// Usage in a widget:
/// ```dart
/// final isLive = ref.watch(socketConnectionProvider).valueOrNull ?? false;
/// ```
final socketConnectionProvider = StreamProvider<bool>((ref) {
  // Seed with the current connection state so widgets get an immediate value.
  return SocketService.connectionStream.map((status) => status);
});

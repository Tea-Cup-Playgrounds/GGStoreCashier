import '../models/sales.dart';
import 'api_client.dart';

/// Client for /api/sales, /api/customers and /api/cash-sessions (see API/src/routes).
class SalesService {
  static Future<List<PaymentMethod>> getPaymentMethods(int locationId) async {
    final body = await ApiClient.request('GET', '/api/sales/payment-methods', query: {'location_id': locationId});
    return ApiClient.list(body, 'paymentMethods', PaymentMethod.fromJson);
  }

  /// Server-side price of a cart (voucher, discounts, PPN) without saving it.
  /// [body]: location_id, lines, voucher_code?. Returns the API's JSON (grand_total, tax_total, ...).
  static Future<Map<String, dynamic>> quote(Map<String, dynamic> body) =>
      ApiClient.request('POST', '/api/sales/quote', data: body);

  /// [body] is the full POST /api/sales payload (see API/src/routes/sales.js). It carries its own
  /// `id`, so sending it again (e.g. from the offline queue) never creates a second sale.
  static Future<SaleResult> createSale(Map<String, dynamic> body) async =>
      ApiClient.one(await ApiClient.request('POST', '/api/sales', data: body), 'sale', SaleResult.fromJson);

  // ── customers ─────────────────────────────────────────────────────────────

  static Future<List<Customer>> searchCustomers(String query) async {
    final body = await ApiClient.request('GET', '/api/customers', query: {'search': query});
    return ApiClient.list(body, 'customers', Customer.fromJson);
  }

  // ── shifts ────────────────────────────────────────────────────────────────

  /// The signed-in cashier's open shift at [locationId], or null.
  static Future<CashSession?> currentShift(int locationId) async {
    final body = await ApiClient.request('GET', '/api/cash-sessions/current', query: {'location_id': locationId});
    return body['session'] is Map ? CashSession.fromJson(Map<String, dynamic>.from(body['session'] as Map)) : null;
  }

  static Future<CashSession> getShift(String id) async =>
      ApiClient.one(await ApiClient.request('GET', '/api/cash-sessions/$id'), 'session', CashSession.fromJson);

  static Future<CashSession> openShift({required int locationId, required double openingCash}) async {
    final body = await ApiClient.request('POST', '/api/cash-sessions', data: {'location_id': locationId, 'opening_cash': openingCash});
    return ApiClient.one(body, 'session', CashSession.fromJson);
  }

  /// Returns the closed shift (with its cash difference) and the API's message.
  static Future<(CashSession, String)> closeShift(String id, {required double countedCash, String? note}) async {
    final body = await ApiClient.request('POST', '/api/cash-sessions/$id/close', data: {
      'counted_cash': countedCash,
      if (note != null && note.isNotEmpty) 'note': note,
    });
    return (ApiClient.one(body, 'session', CashSession.fromJson), body['message']?.toString() ?? '');
  }
}

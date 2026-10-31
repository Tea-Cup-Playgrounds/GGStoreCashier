import '../models/warehouse.dart';
import 'api_client.dart';

/// Client for /api/purchasing, /api/transfers and /api/opnames (see API/src/routes).
class WarehouseService {
  // ── suppliers ─────────────────────────────────────────────────────────────

  static Future<List<Supplier>> getSuppliers({String? search, bool includeInactive = false}) async {
    final body = await ApiClient.request('GET', '/api/purchasing/suppliers', query: {
      if (search != null && search.isNotEmpty) 'search': search,
      if (includeInactive) 'include_inactive': 'true',
    });
    return ApiClient.list(body, 'suppliers', Supplier.fromJson);
  }

  /// [fields]: name, code (optional, generated), phone, email, address, notes, is_active.
  static Future<Supplier> createSupplier(Map<String, dynamic> fields) async =>
      ApiClient.one(await ApiClient.request('POST', '/api/purchasing/suppliers', data: fields), 'supplier', Supplier.fromJson);

  static Future<void> updateSupplier(int id, Map<String, dynamic> fields) =>
      ApiClient.request('PUT', '/api/purchasing/suppliers/$id', data: fields);

  // ── goods receipts ────────────────────────────────────────────────────────

  static Future<List<GoodsReceipt>> getReceipts({int? locationId, String? status, String? paymentStatus, int? supplierId}) async {
    final body = await ApiClient.request('GET', '/api/purchasing/receipts', query: {
      if (locationId != null) 'location_id': locationId,
      if (status != null) 'status': status,
      if (paymentStatus != null) 'payment_status': paymentStatus,
      if (supplierId != null) 'supplier_id': supplierId,
    });
    return ApiClient.list(body, 'receipts', GoodsReceipt.fromJson);
  }

  static Future<GoodsReceipt> getReceipt(String id) async =>
      ApiClient.one(await ApiClient.request('GET', '/api/purchasing/receipts/$id'), 'receipt', GoodsReceipt.fromJson);

  /// [data]: location_id (create only), supplier_id, invoice_no, invoice_date, due_date, note,
  /// items [{variant_id, qty, unit_cost, tax_rate, units?}]. Without [id] a new draft is created.
  static Future<GoodsReceipt> saveReceipt(Map<String, dynamic> data, {String? id}) async {
    final body = id == null
        ? await ApiClient.request('POST', '/api/purchasing/receipts', data: data)
        : await ApiClient.request('PUT', '/api/purchasing/receipts/$id', data: data);
    return ApiClient.one(body, 'receipt', GoodsReceipt.fromJson);
  }

  static Future<void> deleteReceipt(String id) => ApiClient.request('DELETE', '/api/purchasing/receipts/$id');

  static Future<GoodsReceipt> postReceipt(String id) async =>
      ApiClient.one(await ApiClient.request('POST', '/api/purchasing/receipts/$id/post'), 'receipt', GoodsReceipt.fromJson);

  /// Returns the amount still owed after this payment.
  static Future<double> paySupplier({
    required String receiptId,
    required double amount,
    required String method,
    String? reference,
    String? paidAt,
    String? note,
  }) async {
    final body = await ApiClient.request('POST', '/api/purchasing/payments', data: {
      'receipt_id': receiptId,
      'amount': amount,
      'method': method,
      if (reference != null && reference.isNotEmpty) 'reference': reference,
      if (paidAt != null) 'paid_at': paidAt,
      if (note != null && note.isNotEmpty) 'note': note,
    });
    return (body['outstanding'] as num).toDouble();
  }

  // ── transfers ─────────────────────────────────────────────────────────────

  /// [direction]: 'in', 'out' or null for both.
  static Future<List<StockTransfer>> getTransfers({required int locationId, String? direction, String? status}) async {
    final body = await ApiClient.request('GET', '/api/transfers', query: {
      'location_id': locationId,
      if (direction != null) 'direction': direction,
      if (status != null) 'status': status,
    });
    return ApiClient.list(body, 'transfers', StockTransfer.fromJson);
  }

  static Future<StockTransfer> getTransfer(String id) async =>
      ApiClient.one(await ApiClient.request('GET', '/api/transfers/$id'), 'transfer', StockTransfer.fromJson);

  /// [items]: [{variant_id, qty}] or [{variant_id, unit_ids}].
  static Future<StockTransfer> saveTransfer({
    String? id,
    required int fromLocationId,
    required int toLocationId,
    String? note,
    required List<Map<String, dynamic>> items,
  }) async {
    final data = {'from_location_id': fromLocationId, 'to_location_id': toLocationId, 'note': note, 'items': items};
    final body = id == null
        ? await ApiClient.request('POST', '/api/transfers', data: data)
        : await ApiClient.request('PUT', '/api/transfers/$id', data: data);
    return ApiClient.one(body, 'transfer', StockTransfer.fromJson);
  }

  static Future<StockTransfer> sendTransfer(String id) async =>
      ApiClient.one(await ApiClient.request('POST', '/api/transfers/$id/send'), 'transfer', StockTransfer.fromJson);

  static Future<void> cancelTransfer(String id) => ApiClient.request('POST', '/api/transfers/$id/cancel');

  /// [qtyReceived]: item id -> quantity for quantity items (omitted = all arrived);
  /// [missingUnitIds]: serialized units that did not arrive.
  static Future<StockTransfer> receiveTransfer(String id,
      {Map<String, int> qtyReceived = const {}, List<String> missingUnitIds = const [], String? note}) async {
    final body = await ApiClient.request('POST', '/api/transfers/$id/receive', data: {
      'items': qtyReceived.entries.map((e) => {'item_id': e.key, 'qty_received': e.value}).toList(),
      'missing_unit_ids': missingUnitIds,
      if (note != null && note.isNotEmpty) 'note': note,
    });
    return ApiClient.one(body, 'transfer', StockTransfer.fromJson);
  }

  /// [action]: 'return' (back to the source) or 'write_off'.
  static Future<StockTransfer> resolveTransfer(String id, {required String action, required String note}) async {
    final body = await ApiClient.request('POST', '/api/transfers/$id/resolve', data: {'action': action, 'note': note});
    return ApiClient.one(body, 'transfer', StockTransfer.fromJson);
  }

  // ── stock opname ──────────────────────────────────────────────────────────

  static Future<List<StockOpname>> getOpnames({required int locationId}) async {
    final body = await ApiClient.request('GET', '/api/opnames', query: {'location_id': locationId});
    return ApiClient.list(body, 'opnames', StockOpname.fromJson);
  }

  static Future<StockOpname> getOpname(String id) async =>
      ApiClient.one(await ApiClient.request('GET', '/api/opnames/$id'), 'opname', StockOpname.fromJson);

  static Future<StockOpname> startOpname({required int locationId, int? categoryId, String? note}) async {
    final body = await ApiClient.request('POST', '/api/opnames', data: {
      'location_id': locationId,
      if (categoryId != null) 'category_id': categoryId,
      if (note != null && note.isNotEmpty) 'note': note,
    });
    return ApiClient.one(body, 'opname', StockOpname.fromJson);
  }

  /// [counts]: variant id -> counted quantity (null clears the count).
  static Future<StockOpname> saveCounts(String id, Map<int, int?> counts) async {
    final body = await ApiClient.request('PUT', '/api/opnames/$id/counts', data: {
      'counts': counts.entries.map((e) => {'variant_id': e.key, 'counted_qty': e.value}).toList(),
    });
    return ApiClient.one(body, 'opname', StockOpname.fromJson);
  }

  static Future<OpnameScanResult> scanOpname(String id, String identifier) async {
    final body = await ApiClient.request('POST', '/api/opnames/$id/scan', data: {'identifier': identifier});
    return OpnameScanResult(result: body['result'].toString(), message: body['message']?.toString() ?? '');
  }

  static Future<void> unscanOpname(String id, String unitId) =>
      ApiClient.request('POST', '/api/opnames/$id/unscan', data: {'unit_id': unitId});

  /// Returns the API's summary: adjusted, unitsWrittenOff, qtyChange.
  static Future<Map<String, dynamic>> approveOpname(String id) async {
    final body = await ApiClient.request('POST', '/api/opnames/$id/approve');
    return Map<String, dynamic>.from(body['summary'] as Map);
  }

  static Future<void> cancelOpname(String id) => ApiClient.request('POST', '/api/opnames/$id/cancel');
}

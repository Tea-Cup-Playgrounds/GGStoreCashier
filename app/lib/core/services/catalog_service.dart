import 'dart:io';
import 'package:dio/dio.dart' show FormData, MultipartFile;
import 'package:http_parser/http_parser.dart';
import '../models/access.dart';
import '../models/catalog.dart';
import 'api_client.dart';
import 'auth_service.dart';

export 'api_client.dart' show ApiException;

/// Client for /api/locations, /api/catalog and /api/stock (see API/src/routes).
class CatalogService {
  // ── access & locations ────────────────────────────────────────────────────

  static Future<UserAccess> getAccess() async {
    final body = await ApiClient.request('GET', '/api/auth/me');
    final access = body['access'];
    return access is Map ? UserAccess.fromJson(Map<String, dynamic>.from(access)) : UserAccess.empty;
  }

  /// Locations the user is assigned to; with [destinations], every active location
  /// (for picking a transfer destination; needs transfers.create).
  /// Kept for offline use (per user, since the list depends on their assignments).
  static Future<List<Location>> getLocations({String? type, bool destinations = false}) async {
    final user = (await AuthService.getCurrentUser())?.id;
    final body = await ApiClient.getCached('/api/locations', 'locations:u$user:${type ?? 'all'}:$destinations', query: {
      if (type != null) 'type': type,
      if (destinations) 'scope': 'destinations',
    });
    return ApiClient.list(body, 'locations', Location.fromJson);
  }

  // ── catalog ───────────────────────────────────────────────────────────────

  /// True when the last [getProducts] call answered from the offline copy.
  static bool lastFromCache = false;

  /// The unfiltered list at a location is kept for offline selling; check [lastFromCache] after calling.
  static Future<List<CatalogProduct>> getProducts({int? locationId, String? search, int? categoryId}) async {
    final query = <String, dynamic>{
      'limit': 200,
      if (locationId != null) 'location_id': locationId,
      if (search != null && search.isNotEmpty) 'search': search,
      if (categoryId != null) 'category_id': categoryId,
    };
    final cacheable = (search == null || search.isEmpty) && categoryId == null;
    final user = (await AuthService.getCurrentUser())?.id;
    final body = cacheable
        ? await ApiClient.getCached('/api/catalog/products', 'catalog:u$user:l${locationId ?? 'all'}', query: query)
        : await ApiClient.request('GET', '/api/catalog/products', query: query);
    lastFromCache = cacheable && ApiClient.lastFromCache;
    return ApiClient.list(body, 'products', CatalogProduct.fromJson);
  }

  static Future<CatalogProduct> getProduct(int id) async {
    final body = await ApiClient.request('GET', '/api/catalog/products/$id');
    return CatalogProduct.fromJson(Map<String, dynamic>.from(body['product'] as Map));
  }

  /// [fields] uses API names (name, brand_id, is_serialized, ...); [variants] each
  /// {name, sku, barcode, base_price}. Returns the created product.
  static Future<CatalogProduct> createProduct(Map<String, dynamic> fields, List<Map<String, dynamic>> variants) async {
    final body = await ApiClient.request('POST', '/api/catalog/products', data: {...fields, 'variants': variants});
    return CatalogProduct.fromJson(Map<String, dynamic>.from(body['product'] as Map));
  }

  static Future<void> updateProduct(int id, Map<String, dynamic> fields) =>
      ApiClient.request('PUT', '/api/catalog/products/$id', data: fields);

  static Future<void> deleteProduct(int id) => ApiClient.request('DELETE', '/api/catalog/products/$id');

  static Future<void> uploadProductImage(int id, File file) async {
    final ext = file.path.split('.').last.toLowerCase();
    final form = FormData.fromMap({
      'image': await MultipartFile.fromFile(
        file.path,
        filename: file.path.split(Platform.pathSeparator).last,
        contentType: MediaType('image', ext == 'png' ? 'png' : 'jpeg'),
      ),
    });
    await ApiClient.request('POST', '/api/catalog/products/$id/image', data: form);
  }

  static Future<void> addVariant(int productId, Map<String, dynamic> fields) =>
      ApiClient.request('POST', '/api/catalog/products/$productId/variants', data: fields);

  static Future<void> updateVariant(int id, Map<String, dynamic> fields) =>
      ApiClient.request('PUT', '/api/catalog/variants/$id', data: fields);

  static Future<void> deleteVariant(int id) => ApiClient.request('DELETE', '/api/catalog/variants/$id');

  static Future<List<Brand>> getBrands() async => ApiClient.list(await ApiClient.request('GET', '/api/catalog/brands'), 'brands', Brand.fromJson);

  /// Categories as (id, name); managed on the Kategori tab via /api/categories.
  static Future<List<({int id, String name})>> getCategories() async {
    final body = await ApiClient.request('GET', '/api/categories');
    return ((body['categories'] as List?) ?? const [])
        .map((c) => (id: (c['id'] as num).toInt(), name: c['name'].toString()))
        .toList();
  }

  static Future<Brand> createBrand(String name) async {
    final body = await ApiClient.request('POST', '/api/catalog/brands', data: {'name': name});
    return Brand.fromJson(Map<String, dynamic>.from(body['brand'] as Map));
  }

  // ── stock ─────────────────────────────────────────────────────────────────

  /// [qtyChange] is signed; [unitCost] only matters for incoming stock.
  static Future<int> adjustStock({
    required int locationId,
    required int variantId,
    required int qtyChange,
    double? unitCost,
    required String note,
  }) async {
    final body = await ApiClient.request('POST', '/api/stock/adjust', data: {
      'location_id': locationId,
      'variant_id': variantId,
      'qty_change': qtyChange,
      if (unitCost != null) 'unit_cost': unitCost,
      'note': note,
    });
    return (body['qty'] as num).toInt();
  }

  /// [sellPrice] null removes the location override.
  static Future<void> setLocationPrice({required int locationId, required int variantId, double? sellPrice}) =>
      ApiClient.request('PUT', '/api/stock/price', data: {
        'location_id': locationId,
        'variant_id': variantId,
        'sell_price': sellPrice,
      });

  static Future<List<StockMovement>> getMovements({required int locationId, int? variantId, String? unitId}) async {
    final body = await ApiClient.request('GET', '/api/stock/movements', query: {
      'location_id': locationId,
      if (variantId != null) 'variant_id': variantId,
      if (unitId != null) 'unit_id': unitId,
      'limit': 100,
    });
    return ApiClient.list(body, 'movements', StockMovement.fromJson);
  }

  /// Either [locationId] or [search] (IMEI/serial lookup across visible locations) is required.
  static Future<List<ProductUnit>> getUnits({int? locationId, int? variantId, String? status, String? search}) async {
    final body = await ApiClient.request('GET', '/api/stock/units', query: {
      if (locationId != null) 'location_id': locationId,
      if (variantId != null) 'variant_id': variantId,
      if (status != null) 'status': status,
      if (search != null && search.isNotEmpty) 'search': search,
    });
    return ApiClient.list(body, 'units', ProductUnit.fromJson);
  }

  /// Each unit: {imei1, imei2, serial_number, unit_cost, condition_grade, sell_price, notes}.
  static Future<int> registerUnits({
    required int locationId,
    required int variantId,
    required List<Map<String, dynamic>> units,
    String? note,
  }) async {
    final body = await ApiClient.request('POST', '/api/stock/units', data: {
      'location_id': locationId,
      'variant_id': variantId,
      'units': units,
      if (note != null && note.isNotEmpty) 'note': note,
    });
    return ((body['units'] as List?) ?? const []).length;
  }

  static Future<void> updateUnit(String id, Map<String, dynamic> changes) =>
      ApiClient.request('PUT', '/api/stock/units/$id', data: changes);

  /// [status] is 'defective' or 'written_off'.
  static Future<void> writeOffUnit(String id, {required String status, required String note}) =>
      ApiClient.request('POST', '/api/stock/units/$id/write-off', data: {'status': status, 'note': note});
}

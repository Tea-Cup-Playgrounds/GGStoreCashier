import 'dart:io';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import '../config/api_config.dart';
import '../models/access.dart';
import '../models/catalog.dart';
import 'auth_service.dart';

/// Thrown with the API's own error message (Indonesian, user-facing).
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  const ApiException(this.message, [this.statusCode]);

  @override
  String toString() => message;
}

/// Client for /api/locations, /api/catalog and /api/stock (see API/src/routes).
class CatalogService {
  static final _dio = Dio(BaseOptions(
    baseUrl: ApiConfig.apiUrl,
    connectTimeout: ApiConfig.connectTimeout,
    receiveTimeout: ApiConfig.receiveTimeout,
    sendTimeout: ApiConfig.sendTimeout,
    headers: ApiConfig.defaultHeaders,
  ));

  static Future<Options> _auth() async {
    final token = await AuthService.getToken();
    if (token == null) throw const ApiException('Sesi berakhir, silakan login kembali', 401);
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  static Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? data,
  }) async {
    try {
      final options = (await _auth()).copyWith(method: method);
      final response = await _dio.request<dynamic>(path, queryParameters: query, data: data, options: options);
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (e) {
      final body = e.response?.data;
      final message = body is Map && body['error'] != null
          ? body['error'].toString()
          : e.type == DioExceptionType.connectionError || e.type == DioExceptionType.connectionTimeout
              ? 'Tidak dapat terhubung ke server'
              : 'Terjadi kesalahan (${e.response?.statusCode ?? e.type.name})';
      throw ApiException(message, e.response?.statusCode);
    }
  }

  static List<T> _list<T>(Map<String, dynamic> body, String key, T Function(Map<String, dynamic>) parse) =>
      ((body[key] as List?) ?? const []).map((e) => parse(Map<String, dynamic>.from(e as Map))).toList();

  // ── access & locations ────────────────────────────────────────────────────

  static Future<UserAccess> getAccess() async {
    final body = await _request('GET', '/api/auth/me');
    final access = body['access'];
    return access is Map ? UserAccess.fromJson(Map<String, dynamic>.from(access)) : UserAccess.empty;
  }

  static Future<List<Location>> getLocations({String? type}) async {
    final body = await _request('GET', '/api/locations', query: {if (type != null) 'type': type});
    return _list(body, 'locations', Location.fromJson);
  }

  // ── catalog ───────────────────────────────────────────────────────────────

  static Future<List<CatalogProduct>> getProducts({int? locationId, String? search, int? categoryId}) async {
    final body = await _request('GET', '/api/catalog/products', query: {
      'limit': 200,
      if (locationId != null) 'location_id': locationId,
      if (search != null && search.isNotEmpty) 'search': search,
      if (categoryId != null) 'category_id': categoryId,
    });
    return _list(body, 'products', CatalogProduct.fromJson);
  }

  static Future<CatalogProduct> getProduct(int id) async {
    final body = await _request('GET', '/api/catalog/products/$id');
    return CatalogProduct.fromJson(Map<String, dynamic>.from(body['product'] as Map));
  }

  /// [fields] uses API names (name, brand_id, is_serialized, ...); [variants] each
  /// {name, sku, barcode, base_price}. Returns the created product.
  static Future<CatalogProduct> createProduct(Map<String, dynamic> fields, List<Map<String, dynamic>> variants) async {
    final body = await _request('POST', '/api/catalog/products', data: {...fields, 'variants': variants});
    return CatalogProduct.fromJson(Map<String, dynamic>.from(body['product'] as Map));
  }

  static Future<void> updateProduct(int id, Map<String, dynamic> fields) =>
      _request('PUT', '/api/catalog/products/$id', data: fields);

  static Future<void> deleteProduct(int id) => _request('DELETE', '/api/catalog/products/$id');

  static Future<void> uploadProductImage(int id, File file) async {
    final ext = file.path.split('.').last.toLowerCase();
    final form = FormData.fromMap({
      'image': await MultipartFile.fromFile(
        file.path,
        filename: file.path.split(Platform.pathSeparator).last,
        contentType: MediaType('image', ext == 'png' ? 'png' : 'jpeg'),
      ),
    });
    await _request('POST', '/api/catalog/products/$id/image', data: form);
  }

  static Future<void> addVariant(int productId, Map<String, dynamic> fields) =>
      _request('POST', '/api/catalog/products/$productId/variants', data: fields);

  static Future<void> updateVariant(int id, Map<String, dynamic> fields) =>
      _request('PUT', '/api/catalog/variants/$id', data: fields);

  static Future<void> deleteVariant(int id) => _request('DELETE', '/api/catalog/variants/$id');

  static Future<List<Brand>> getBrands() async => _list(await _request('GET', '/api/catalog/brands'), 'brands', Brand.fromJson);

  /// Categories as (id, name); managed on the Kategori tab via /api/categories.
  static Future<List<({int id, String name})>> getCategories() async {
    final body = await _request('GET', '/api/categories');
    return ((body['categories'] as List?) ?? const [])
        .map((c) => (id: (c['id'] as num).toInt(), name: c['name'].toString()))
        .toList();
  }

  static Future<Brand> createBrand(String name) async {
    final body = await _request('POST', '/api/catalog/brands', data: {'name': name});
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
    final body = await _request('POST', '/api/stock/adjust', data: {
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
      _request('PUT', '/api/stock/price', data: {
        'location_id': locationId,
        'variant_id': variantId,
        'sell_price': sellPrice,
      });

  static Future<List<StockMovement>> getMovements({required int locationId, int? variantId, String? unitId}) async {
    final body = await _request('GET', '/api/stock/movements', query: {
      'location_id': locationId,
      if (variantId != null) 'variant_id': variantId,
      if (unitId != null) 'unit_id': unitId,
      'limit': 100,
    });
    return _list(body, 'movements', StockMovement.fromJson);
  }

  /// Either [locationId] or [search] (IMEI/serial lookup across visible locations) is required.
  static Future<List<ProductUnit>> getUnits({int? locationId, int? variantId, String? status, String? search}) async {
    final body = await _request('GET', '/api/stock/units', query: {
      if (locationId != null) 'location_id': locationId,
      if (variantId != null) 'variant_id': variantId,
      if (status != null) 'status': status,
      if (search != null && search.isNotEmpty) 'search': search,
    });
    return _list(body, 'units', ProductUnit.fromJson);
  }

  /// Each unit: {imei1, imei2, serial_number, unit_cost, condition_grade, sell_price, notes}.
  static Future<int> registerUnits({
    required int locationId,
    required int variantId,
    required List<Map<String, dynamic>> units,
    String? note,
  }) async {
    final body = await _request('POST', '/api/stock/units', data: {
      'location_id': locationId,
      'variant_id': variantId,
      'units': units,
      if (note != null && note.isNotEmpty) 'note': note,
    });
    return ((body['units'] as List?) ?? const []).length;
  }

  static Future<void> updateUnit(String id, Map<String, dynamic> changes) =>
      _request('PUT', '/api/stock/units/$id', data: changes);

  /// [status] is 'defective' or 'written_off'.
  static Future<void> writeOffUnit(String id, {required String status, required String note}) =>
      _request('POST', '/api/stock/units/$id/write-off', data: {'status': status, 'note': note});
}

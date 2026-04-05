import 'dart:io';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../models/product.dart';
import 'cache_manager.dart';

class ProductService {
  /// Set to `true` after a call to [getProducts] that returned stale cached data.
  static bool lastFetchWasStale = false;
  static final _dio = Dio(BaseOptions(
    baseUrl: ApiConfig.apiUrl,
    connectTimeout: ApiConfig.connectTimeout,
    receiveTimeout: ApiConfig.receiveTimeout,
    sendTimeout: ApiConfig.sendTimeout,
    headers: ApiConfig.defaultHeaders,
  ));

  static void _initializeDio() {
    if (ApiConfig.enableNetworkLogging) {
      _dio.interceptors.add(LogInterceptor(
        requestBody: true,
        responseBody: true,
        requestHeader: true,
        responseHeader: false,
        error: true,
        logPrint: (obj) {
          if (ApiConfig.enableLogging) {
            print('[PRODUCT SERVICE] $obj');
          }
        },
      ));
    }
  }

  static Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  /// Cache key scoped to the branch so different users never share cached lists.
  static String _cacheKey(int? branchId) =>
      branchId != null ? 'products:branch_$branchId' : 'products:all';

  static String getProductImageUrl(String? imageName) {
    if (imageName == null || imageName.isEmpty) {
      return '';
    }
    return '${ApiConfig.apiUrl}/uploads/products/$imageName';
  }

  static String getPlaceholderImage() {
    return 'assets/products/example.jpg';
  }

  static Future<List<Product>> getProducts({
    int? branchId,
    int? categoryId,
    String? search,
    bool forceRefresh = false,
  }) async {
    _initializeDio();

    // Reset stale flag at the start of every call.
    lastFetchWasStale = false;

    final bool noFilters =
        categoryId == null && (search == null || search.isEmpty);

    final cacheKey = _cacheKey(branchId);

    // --- Cache read (only when no extra filters are applied) ---
    if (noFilters && !forceRefresh && CacheManager.isValid(cacheKey)) {
      final entry = CacheManager.get(cacheKey);
      if (entry != null) {
        final cachedList = (entry.data as List)
            .map((json) => Product.fromJson(Map<String, dynamic>.from(json as Map)))
            .toList();
        return cachedList;
      }
    }

    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('No authentication token found');
      }

      final queryParams = <String, dynamic>{};
      if (branchId != null) queryParams['branch_id'] = branchId;
      if (categoryId != null) queryParams['category_id'] = categoryId;
      if (search != null && search.isNotEmpty) queryParams['search'] = search;

      final response = await _dio.get(
        '/api/products',
        queryParameters: queryParams,
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        final productsJson = data['products'] as List;
        final products =
            productsJson.map((json) => Product.fromJson(json)).toList();

        // Store raw JSON in cache (only when no extra filters).
        if (noFilters) {
          await CacheManager.put(cacheKey, productsJson);
        }

        return products;
      } else {
        throw Exception('Failed to load products: ${response.statusCode}');
      }
    } on DioException catch (e) {
      // Network failure — try to return stale cache if available.
      if (noFilters) {
        final staleEntry = CacheManager.get(cacheKey);
        if (staleEntry != null) {
          lastFetchWasStale = true;
          staleEntry.isStale = true;
          await staleEntry.save();
          return (staleEntry.data as List)
              .map((json) =>
                  Product.fromJson(Map<String, dynamic>.from(json as Map)))
              .toList();
        }
      }
      throw Exception('Network error: ${e.message}');
    } catch (e) {
      rethrow;
    }
  }

  static Future<Product> getProductDetail(int productId) async {
    _initializeDio();

    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('No authentication token found');
      }

      final response = await _dio.get(
        '/api/products/$productId',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data['product'] ?? response.data;
        return Product.fromJson(data);
      } else {
        throw Exception(
            'Failed to load product detail: ${response.statusCode}');
      }
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    } catch (e) {
      rethrow;
    }
  }
static Future<Product> updateProduct({
    required Product product, // Ubah parameter jadi objek Product utuh
    required String name,
    String? barcode,
    required int stock,
    required double sellPrice,
    String? description,
    File? imageFile,
  }) async {
    _initializeDio();
    try {
      final token = await _getToken();

      final formData = FormData.fromMap({
        'name': name,
        'barcode': barcode ?? product.barcode,
        'category_id': product.categoryId, // Kirim ID, bukan nama
        'stock': stock,
        'sell_price': sellPrice,
        'branch_id': product.branchId, // WAJIB DIKIRIM agar tidak error 500
        'description': description ?? '',
        if (imageFile != null)
          'product_image': await MultipartFile.fromFile(
            imageFile.path,
            filename: imageFile.path.split('/').last,
            contentType: MediaType('image', 'jpeg'),
          ),
      });

      final response = await _dio.put(
        '/api/products/${product.id}',
        data: formData,
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          contentType: 'multipart/form-data',
        ),
      );

      return Product.fromJson(response.data['product'] ?? response.data);
    } catch (e) {
      throw Exception('Network error updating product: $e');
    }
  }
}

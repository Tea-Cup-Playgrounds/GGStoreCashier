import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../models/product.dart';

class ProductService {
  static final _dio = Dio(BaseOptions(
    baseUrl: ApiConfig.apiUrl,
    connectTimeout: ApiConfig.connectTimeout,
    receiveTimeout: ApiConfig.receiveTimeout,
    sendTimeout: ApiConfig.sendTimeout,
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

  /// Fetch all products with optional filters
  static Future<List<Product>> getProducts({
    int? branchId,
    int? categoryId,
    String? search,
  }) async {
    _initializeDio();

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
        return productsJson.map((json) => Product.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load products: ${response.statusCode}');
      }
    } on DioException catch (e) {
      if (ApiConfig.enableLogging) {
        print('DioException in getProducts: ${e.message}');
        print('Response: ${e.response?.data}');
      }
      throw Exception('Network error: ${e.message}');
    } catch (e) {
      if (ApiConfig.enableLogging) {
        print('Error in getProducts: $e');
      }
      rethrow;
    }
  }

  /// Get product image URL
  static String getProductImageUrl(String? imageName) {
    if (imageName == null || imageName.isEmpty) {
      return '';
    }
    return '${ApiConfig.apiUrl}/uploads/products/$imageName';
  }

  /// Get a default placeholder image path
  static String getPlaceholderImage() {
    return 'assets/products/example.jpg';
  }
}

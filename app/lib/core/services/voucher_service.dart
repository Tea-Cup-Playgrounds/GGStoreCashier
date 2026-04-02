import 'package:dio/dio.dart';
import '../config/api_config.dart';
import '../models/voucher.dart';
import 'auth_service.dart';

class VoucherService {
  static Future<Dio> _dio() async {
    final token = await AuthService.getToken();
    return Dio(BaseOptions(
      baseUrl: ApiConfig.apiUrl,
      headers: {'Authorization': 'Bearer $token', ...ApiConfig.defaultHeaders},
      connectTimeout: ApiConfig.connectTimeout,
      receiveTimeout: ApiConfig.receiveTimeout,
    ));
  }

  /// Validate a code at the cashier — returns the voucher or throws.
  static Future<Voucher> validate(String code) async {
    final dio = await _dio();
    final response = await dio.get('/api/vouchers/validate/${Uri.encodeComponent(code)}');
    return Voucher.fromJson(response.data['voucher']);
  }

  /// List all vouchers (admin / superadmin).
  static Future<List<Voucher>> getAll() async {
    final dio = await _dio();
    final response = await dio.get('/api/vouchers');
    return (response.data['vouchers'] as List)
        .map((e) => Voucher.fromJson(e))
        .toList();
  }

  /// Create a new voucher.
  static Future<void> create(Map<String, dynamic> data) async {
    final dio = await _dio();
    await dio.post('/api/vouchers', data: data);
  }

  /// Update an existing voucher.
  static Future<void> update(int id, Map<String, dynamic> data) async {
    final dio = await _dio();
    await dio.put('/api/vouchers/$id', data: data);
  }

  /// Delete a voucher.
  static Future<void> delete(int id) async {
    final dio = await _dio();
    await dio.delete('/api/vouchers/$id');
  }
}

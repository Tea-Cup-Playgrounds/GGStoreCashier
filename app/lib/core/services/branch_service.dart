import 'package:dio/dio.dart';
import '../config/api_config.dart';
import '../models/branch.dart';
import 'auth_service.dart';

class BranchService {
  static Future<Dio> _dio() async {
    final token = await AuthService.getToken();
    return Dio(BaseOptions(
      baseUrl: ApiConfig.apiUrl,
      headers: {
        'Authorization': 'Bearer $token',
        ...ApiConfig.defaultHeaders,
      },
      connectTimeout: ApiConfig.connectTimeout,
      receiveTimeout: ApiConfig.receiveTimeout,
    ));
  }

  /// Fetch a single branch by id.
  static Future<Branch> getBranch(int id) async {
    final dio = await _dio();
    final response = await dio.get('/api/branches/$id');
    return Branch.fromJson(response.data['branch']);
  }

  /// Fetch all branches (superadmin).
  static Future<List<Branch>> getBranches() async {
    final dio = await _dio();
    final response = await dio.get('/api/branches');
    final list = response.data['branches'] as List;
    return list.map((e) => Branch.fromJson(e)).toList();
  }

  /// Update branch fields. Admin can only update their own branch.
  static Future<void> updateBranch(
      int id, String name, String? address, String? phone) async {
    final dio = await _dio();
    await dio.put('/api/branches/$id', data: {
      'name': name,
      if (address != null) 'address': address,
      if (phone != null) 'phone': phone,
    });
  }
}

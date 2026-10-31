import 'package:dio/dio.dart';
import '../config/api_config.dart';
import 'auth_service.dart';

/// Thrown with the API's own error message (Indonesian, user-facing).
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  const ApiException(this.message, [this.statusCode]);

  @override
  String toString() => message;
}

/// Authenticated JSON requests to the API, shared by the services for the newer endpoints.
class ApiClient {
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

  /// Sends the request and returns the decoded JSON body; failures become [ApiException]
  /// carrying the API's `error` message when there is one.
  static Future<Map<String, dynamic>> request(
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

  /// Parses `body[key]` as a list of objects.
  static List<T> list<T>(Map<String, dynamic> body, String key, T Function(Map<String, dynamic>) parse) =>
      ((body[key] as List?) ?? const []).map((e) => parse(Map<String, dynamic>.from(e as Map))).toList();

  /// Parses `body[key]` as one object.
  static T one<T>(Map<String, dynamic> body, String key, T Function(Map<String, dynamic>) parse) =>
      parse(Map<String, dynamic>.from(body[key] as Map));
}

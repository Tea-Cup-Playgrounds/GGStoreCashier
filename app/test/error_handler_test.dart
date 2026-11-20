import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gg_store_cashier/core/services/api_client.dart';
import 'package:gg_store_cashier/core/services/error_handler.dart';

void main() {
  final ro = RequestOptions(path: '/x');

  test('NotInitializedError from flutter_dotenv is humanized', () {
    final msg = ErrorHandler.describe(NotInitializedError());
    expect(msg, isNot(contains('Instance of')));
    expect(msg, contains('Konfigurasi aplikasi'));
  });

  test('API error message from the response body is shown as is', () {
    final e = DioException(
      requestOptions: ro,
      type: DioExceptionType.badResponse,
      response: Response(requestOptions: ro, statusCode: 400, data: {'error': 'Stok tidak cukup'}),
    );
    expect(ErrorHandler.describe(e), 'Stok tidak cukup');
  });

  test('connection problems read as connection problems', () {
    expect(ErrorHandler.describe(DioException(requestOptions: ro, type: DioExceptionType.connectionError)),
        contains('Tidak dapat terhubung'));
    expect(ErrorHandler.describe(const SocketException('refused')), contains('Tidak dapat terhubung'));
  });

  test('app messages pass through, Exception prefix stripped', () {
    expect(ErrorHandler.describe(const ApiException('Sesi berakhir', 401)), 'Sesi berakhir');
    expect(ErrorHandler.describe(const UserMessage('Gagal memuat')), 'Gagal memuat');
    expect(ErrorHandler.describe(Exception('Gagal simpan')), 'Gagal simpan');
  });

  test('unknown errors never leak "Instance of"', () {
    final msg = ErrorHandler.describe(_Weird());
    expect(msg, startsWith('Terjadi kesalahan'));
    expect(ErrorHandler.describe(_Weird(), fallback: 'Gagal X'), startsWith('Gagal X'));
  });

  test('dotenv loads as optional when .env content is empty', () {
    dotenv.loadFromString(envString: '', isOptional: true);
    expect(dotenv.isInitialized, isTrue);
    expect(dotenv.env['API_BASE_URL'], isNull);
  });
}

class _Weird {}

import 'package:dio/dio.dart';

enum AppErrorType { offline, serverError, maintenance, timeout, authError, unknown }

class AppError {
  final AppErrorType type;
  final String userMessage;
  final String? technicalDetail;

  const AppError({
    required this.type,
    required this.userMessage,
    this.technicalDetail,
  });
}

class ErrorHandler {
  ErrorHandler._();

  static AppError classify(dynamic error) {
    if (error is DioException) {
      return _classifyDioException(error);
    }
    return AppError(
      type: AppErrorType.unknown,
      userMessage: messageFor(AppErrorType.unknown),
      technicalDetail: error?.toString(),
    );
  }

  static AppError _classifyDioException(DioException error) {
    // Timeout types
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return AppError(
        type: AppErrorType.timeout,
        userMessage: messageFor(AppErrorType.timeout),
        technicalDetail: error.message,
      );
    }

    // Connection error → offline
    if (error.type == DioExceptionType.connectionError) {
      return AppError(
        type: AppErrorType.offline,
        userMessage: messageFor(AppErrorType.offline),
        technicalDetail: error.message,
      );
    }

    // HTTP status-based classification
    final statusCode = error.response?.statusCode;
    if (statusCode != null) {
      if (statusCode == 503) {
        return AppError(
          type: AppErrorType.maintenance,
          userMessage: messageFor(AppErrorType.maintenance),
          technicalDetail: error.message,
        );
      }
      if (statusCode >= 500 && statusCode < 600) {
        return AppError(
          type: AppErrorType.serverError,
          userMessage: messageFor(AppErrorType.serverError),
          technicalDetail: error.message,
        );
      }
      if (statusCode == 401 || statusCode == 403) {
        return AppError(
          type: AppErrorType.authError,
          userMessage: messageFor(AppErrorType.authError),
          technicalDetail: error.message,
        );
      }
    }

    return AppError(
      type: AppErrorType.unknown,
      userMessage: messageFor(AppErrorType.unknown),
      technicalDetail: error.message,
    );
  }

  static String messageFor(AppErrorType type) {
    switch (type) {
      case AppErrorType.offline:
        return 'Kamu Offline — Tidak Ada Koneksi Internet';
      case AppErrorType.serverError:
        return 'Terjadi Kesalahan pada Server — Coba lagi nanti';
      case AppErrorType.maintenance:
        return 'Aplikasi Sedang dalam Pemeliharaan — Silakan coba beberapa saat lagi';
      case AppErrorType.timeout:
        return 'Koneksi Lambat — Periksa jaringan Anda';
      case AppErrorType.authError:
        return 'Sesi Anda telah berakhir';
      case AppErrorType.unknown:
        return 'Terjadi Kesalahan — Silakan coba lagi';
    }
  }
}

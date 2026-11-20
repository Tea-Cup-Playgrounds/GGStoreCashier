import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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

/// An exception whose [message] is already written for the person using the app (Indonesian,
/// no technical detail). [ErrorHandler.describe] shows it as is.
abstract class UserFacingException implements Exception {
  String get message;
}

/// A ready-to-show message thrown by app code, e.g. `throw const UserMessage('Gagal memuat data')`.
class UserMessage implements UserFacingException {
  @override
  final String message;
  const UserMessage(this.message);

  @override
  String toString() => message;
}

class ErrorHandler {
  ErrorHandler._();

  static const _generic = 'Terjadi kesalahan. Silakan coba lagi.';

  /// Turns any caught error into a sentence fit to show on screen. Never returns raw
  /// `toString()` output such as "Instance of 'X'", stack traces or Dio dumps; the technical
  /// detail goes to the log instead (and is appended in debug builds to help development).
  static String describe(Object? error, {String? fallback}) {
    final message = _humanMessage(error);
    if (message != null) return message;

    dev.log('Unrecognised error shown to user: $error', name: 'ErrorHandler');
    final base = fallback ?? _generic;
    return kDebugMode && error != null ? '$base\n[debug] $error' : base;
  }

  /// [describe] with a short prefix naming what failed, e.g. `describeAs('Gagal mencetak', e)`
  /// gives "Gagal mencetak: Bluetooth HP sedang mati".
  static String describeAs(String action, Object? error) => '$action: ${describe(error)}';

  /// The human message for errors we recognise, or null when all we have is technical detail.
  static String? _humanMessage(Object? error) {
    if (error == null) return null;
    if (error is UserFacingException) return error.message;
    if (error is String) return error.trim().isEmpty ? null : error;
    if (error is DioException) return _dioMessage(error);
    if (error is SocketException || error is HttpException) {
      return 'Tidak dapat terhubung ke server. Periksa koneksi internet Anda.';
    }
    if (error is HandshakeException || error is TlsException) {
      return 'Koneksi aman ke server gagal. Periksa alamat server atau jaringan Anda.';
    }
    if (error is TimeoutException) return 'Koneksi lambat atau terputus. Coba lagi.';
    if (error is FormatException || error is TypeError || error is NoSuchMethodError) {
      return 'Data dari server tidak sesuai. Coba lagi atau hubungi admin.';
    }
    if (error is PlatformException) {
      if (error.code.toLowerCase().contains('permission')) {
        return 'Izin aplikasi belum diberikan. Aktifkan izinnya di Pengaturan HP.';
      }
      return 'Fitur perangkat gagal dijalankan. Coba lagi.';
    }
    if (error is MissingPluginException) return 'Fitur ini tidak tersedia di perangkat ini.';
    if (error.runtimeType.toString() == 'NotInitializedError') {
      return 'Konfigurasi aplikasi belum dimuat. Tutup lalu buka kembali aplikasi.';
    }
    // `throw Exception('pesan')` from app code: the text after the prefix is ours.
    final text = error.toString();
    if (error is Exception && text.startsWith('Exception: ')) {
      final inner = text.substring('Exception: '.length).trim();
      if (inner.isNotEmpty && !inner.startsWith('Instance of')) return inner;
    }
    return null;
  }

  static String _dioMessage(DioException error) {
    final body = error.response?.data;
    if (body is Map) {
      final apiMessage = body['error'] ?? body['message'];
      if (apiMessage is String && apiMessage.trim().isNotEmpty) return apiMessage;
    }
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Koneksi lambat atau terputus. Periksa jaringan Anda lalu coba lagi.';
      case DioExceptionType.connectionError:
        return 'Tidak dapat terhubung ke server. Periksa koneksi internet atau alamat server.';
      case DioExceptionType.badCertificate:
        return 'Sertifikat server tidak valid. Hubungi admin.';
      case DioExceptionType.cancel:
        return 'Permintaan dibatalkan.';
      case DioExceptionType.badResponse:
        return _statusMessage(error.response?.statusCode);
      case DioExceptionType.unknown:
        final inner = error.error;
        if (inner != null && inner is! DioException) {
          final m = _humanMessage(inner);
          if (m != null) return m;
        }
        return 'Gagal terhubung ke server. Periksa koneksi Anda.';
    }
  }

  static String _statusMessage(int? status) {
    if (status == null) return _generic;
    if (status == 400 || status == 422) return 'Data yang dikirim tidak valid. Periksa kembali isian Anda.';
    if (status == 401) return 'Sesi Anda telah berakhir. Silakan login kembali.';
    if (status == 403) return 'Anda tidak memiliki izin untuk tindakan ini.';
    if (status == 404) return 'Data tidak ditemukan.';
    if (status == 409) return 'Data bentrok dengan data lain. Muat ulang lalu coba lagi.';
    if (status == 413) return 'Berkas terlalu besar.';
    if (status == 429) return 'Terlalu banyak percobaan. Tunggu sebentar lalu coba lagi.';
    if (status == 503) return messageFor(AppErrorType.maintenance);
    if (status >= 500) return messageFor(AppErrorType.serverError);
    return _generic;
  }

  static AppError classify(dynamic error) {
    if (error is DioException) {
      return _classifyDioException(error);
    }
    return AppError(
      type: AppErrorType.unknown,
      userMessage: describe(error),
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
      userMessage: describe(error),
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

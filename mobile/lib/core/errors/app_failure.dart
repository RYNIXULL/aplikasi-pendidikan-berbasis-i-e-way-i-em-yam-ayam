import 'package:dio/dio.dart';

class AppFailure implements Exception {
  const AppFailure({
    required this.code,
    required this.message,
    this.statusCode,
  });

  final String code;
  final String message;
  final int? statusCode;

  @override
  String toString() => 'AppFailure($code, status: $statusCode): $message';

  factory AppFailure.fromDioError(DioException error) {
    final data = error.response?.data;
    if (data is Map<String, dynamic> && data['error'] is Map<String, dynamic>) {
      final errObj = data['error'] as Map<String, dynamic>;
      return AppFailure(
        code: (errObj['code'] ?? 'API_ERROR').toString(),
        message: (errObj['message'] ?? 'Terjadi kesalahan pada server.').toString(),
        statusCode: error.response?.statusCode,
      );
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError) {
      return const AppFailure(
        code: 'NETWORK_UNAVAILABLE',
        message: 'Koneksi jaringan tidak tersedia. Periksa internet Anda dan coba lagi.',
      );
    }
    return AppFailure(
      code: 'UNKNOWN_ERROR',
      message: error.message ?? 'Terjadi kesalahan yang tidak terduga.',
      statusCode: error.response?.statusCode,
    );
  }
}

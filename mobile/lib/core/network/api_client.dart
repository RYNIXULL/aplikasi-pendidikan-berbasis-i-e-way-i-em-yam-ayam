import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import '../config/app_config.dart';
import '../constants/app_constants.dart';
import '../storage/token_storage.dart';

class ApiClient {
  ApiClient({
    required TokenStorage tokenStorage,
    required void Function() onSessionExpired,
    String? baseUrl,
    Dio? dio,
  })  : _tokenStorage = tokenStorage,
        _onSessionExpired = onSessionExpired,
        dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: baseUrl ?? AppConfig.apiBaseUrl,
                connectTimeout: AppConfig.connectTimeout,
                receiveTimeout: AppConfig.receiveTimeout,
                headers: const {'Content-Type': 'application/json'},
              ),
            ) {
    this.dio.interceptors.add(
          _AuthQueuedInterceptor(
            dio: this.dio,
            tokenStorage: _tokenStorage,
            onSessionExpired: _onSessionExpired,
          ),
        );
  }

  final Dio dio;
  final TokenStorage _tokenStorage;
  final void Function() _onSessionExpired;
}

class _AuthQueuedInterceptor extends QueuedInterceptor {
  _AuthQueuedInterceptor({
    required this.dio,
    required this.tokenStorage,
    required this.onSessionExpired,
  });

  final Dio dio;
  final TokenStorage tokenStorage;
  final void Function() onSessionExpired;
  final Uuid _uuid = const Uuid();

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    options.headers['X-Request-Id'] = _uuid.v4();
    final isAuthPublic = options.path.endsWith(ApiPaths.login) ||
        options.path.endsWith(ApiPaths.register) ||
        options.path.endsWith(ApiPaths.refresh) ||
        options.path.endsWith(ApiPaths.forgotPassword) ||
        options.path.endsWith(ApiPaths.resetPassword);

    if (!isAuthPublic) {
      final access = await tokenStorage.readAccessToken();
      if (access != null && access.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $access';
      }
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final statusCode = err.response?.statusCode;
    final alreadyRetried = err.requestOptions.extra['_retried'] == true;
    final isRefreshCall = err.requestOptions.path.endsWith(ApiPaths.refresh);

    if (statusCode == 401 && !alreadyRetried && !isRefreshCall) {
      final refreshToken = await tokenStorage.readRefreshToken();
      if (refreshToken != null && refreshToken.isNotEmpty) {
        try {
          final refreshDio = Dio(BaseOptions(baseUrl: dio.options.baseUrl));
          final refreshResp = await refreshDio.post<Map<String, dynamic>>(
            ApiPaths.refresh,
            data: {'refreshToken': refreshToken},
          );
          final data = refreshResp.data?['data'] as Map<String, dynamic>?;
          final tokens = data?['tokens'] as Map<String, dynamic>?;
          final newAccess = tokens?['accessToken'] as String?;
          final newRefresh = tokens?['refreshToken'] as String?;

          if (newAccess != null && newRefresh != null) {
            await tokenStorage.saveTokens(accessToken: newAccess, refreshToken: newRefresh);
            final retryOpts = err.requestOptions;
            retryOpts.extra['_retried'] = true;
            retryOpts.headers['Authorization'] = 'Bearer $newAccess';
            final retriedResponse = await dio.fetch<dynamic>(retryOpts);
            return handler.resolve(retriedResponse);
          }
        } catch (_) {
          await tokenStorage.clearTokens();
          onSessionExpired();
          return handler.next(err);
        }
      }
      await tokenStorage.clearTokens();
      onSessionExpired();
    }

    handler.next(err);
  }
}

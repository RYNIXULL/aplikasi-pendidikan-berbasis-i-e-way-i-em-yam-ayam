import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/app_config.dart';
import '../../core/constants/app_constants.dart';
import '../../core/errors/app_failure.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/offline_cache_db.dart';
import '../../core/storage/token_storage.dart';
import '../models/models.dart';

enum AuthStatus { initial, loading, authenticated, unauthenticated }

class AuthState {
  const AuthState({
    this.status = AuthStatus.initial,
    this.user,
    this.errorMessage,
  });

  final AuthStatus status;
  final UserModel? user;
  final String? errorMessage;

  bool get isAuthenticated => status == AuthStatus.authenticated && user != null;

  AuthState copyWith({
    AuthStatus? status,
    UserModel? user,
    String? errorMessage,
    bool clearUser = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: clearUser ? null : (user ?? this.user),
      errorMessage: errorMessage,
    );
  }
}

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);
final apiBaseUrlProvider = StateProvider<String>((ref) => AppConfig.apiBaseUrl);
final tokenStorageProvider = Provider<TokenStorage>((ref) => SecureTokenStorage());
final offlineCacheProvider = Provider<OfflineCacheDatabase>((ref) => OfflineCacheDatabase());

final apiClientProvider = Provider<ApiClient>((ref) {
  final storage = ref.watch(tokenStorageProvider);
  final baseUrl = ref.watch(apiBaseUrlProvider);
  return ApiClient(
    tokenStorage: storage,
    baseUrl: baseUrl,
    onSessionExpired: () {
      ref.read(authControllerProvider.notifier).forceSignOut();
    },
  );
});

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._ref) : super(const AuthState());

  final Ref _ref;

  Future<void> restoreSession() async {
    state = state.copyWith(status: AuthStatus.loading, errorMessage: null);
    final storage = _ref.read(tokenStorageProvider);
    final token = await storage.readAccessToken();
    if (token == null || token.isEmpty) {
      state = const AuthState(status: AuthStatus.unauthenticated);
      return;
    }

    try {
      final api = _ref.read(apiClientProvider).dio;
      final res = await api.get<Map<String, dynamic>>(ApiPaths.me);
      final data = res.data?['data'] as Map<String, dynamic>;
      state = AuthState(status: AuthStatus.authenticated, user: UserModel.fromJson(data));
    } catch (_) {
      await storage.clearTokens();
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  Future<void> login({required String email, required String password}) async {
    state = state.copyWith(status: AuthStatus.loading, errorMessage: null);
    try {
      final api = _ref.read(apiClientProvider).dio;
      final res = await api.post<Map<String, dynamic>>(
        ApiPaths.login,
        data: {'email': email.trim(), 'password': password},
      );
      final data = res.data?['data'] as Map<String, dynamic>;
      final tokens = data['tokens'] as Map<String, dynamic>;
      await _ref.read(tokenStorageProvider).saveTokens(
            accessToken: tokens['accessToken'].toString(),
            refreshToken: tokens['refreshToken'].toString(),
          );
      final user = UserModel.fromJson(data['user'] as Map<String, dynamic>);
      state = AuthState(status: AuthStatus.authenticated, user: user);
    } on DioException catch (e) {
      final failure = AppFailure.fromDioError(e);
      state = AuthState(status: AuthStatus.unauthenticated, errorMessage: failure.message);
      throw failure;
    }
  }

  Future<void> register({
    required String email,
    required String password,
    required String fullName,
    required UserRole role,
    String? institutionName,
    String? subjectSpecialty,
    String? gradeLevel,
  }) async {
    state = state.copyWith(status: AuthStatus.loading, errorMessage: null);
    try {
      final api = _ref.read(apiClientProvider).dio;
      final res = await api.post<Map<String, dynamic>>(
        ApiPaths.register,
        data: {
          'email': email.trim(),
          'password': password,
          'fullName': fullName.trim(),
          'role': role == UserRole.teacher ? 'TEACHER' : 'STUDENT',
          if (institutionName != null && institutionName.isNotEmpty)
            'institutionName': institutionName.trim(),
          if (subjectSpecialty != null && subjectSpecialty.isNotEmpty)
            'subjectSpecialty': subjectSpecialty.trim(),
          if (gradeLevel != null && gradeLevel.isNotEmpty) 'gradeLevel': gradeLevel.trim(),
        },
      );
      final data = res.data?['data'] as Map<String, dynamic>;
      final tokens = data['tokens'] as Map<String, dynamic>;
      await _ref.read(tokenStorageProvider).saveTokens(
            accessToken: tokens['accessToken'].toString(),
            refreshToken: tokens['refreshToken'].toString(),
          );
      final user = UserModel.fromJson(data['user'] as Map<String, dynamic>);
      state = AuthState(status: AuthStatus.authenticated, user: user);
    } on DioException catch (e) {
      final failure = AppFailure.fromDioError(e);
      state = AuthState(status: AuthStatus.unauthenticated, errorMessage: failure.message);
      throw failure;
    }
  }

  Future<void> logout() async {
    final storage = _ref.read(tokenStorageProvider);
    final refreshToken = await storage.readRefreshToken();
    try {
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await _ref.read(apiClientProvider).dio.post<void>(
          ApiPaths.logout,
          data: {'refreshToken': refreshToken},
        );
      }
    } catch (_) {
      // Clear local session regardless of network reachability
    } finally {
      await storage.clearTokens();
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  void forceSignOut() {
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  void setAuthenticatedUserForTest(UserModel user) {
    state = AuthState(status: AuthStatus.authenticated, user: user);
  }
}

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(ref);
});

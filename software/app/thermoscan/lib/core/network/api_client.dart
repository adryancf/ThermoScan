import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thermoscan/core/config/app_config.dart';
import 'package:thermoscan/core/storage/token_storage.dart';

final baseUrlProvider = StateProvider<String>((ref) {
  return AppConfig.apiBaseUrl;
});

final dioProvider = Provider<Dio>((ref) {
  final tokenStorage = ref.watch(tokenStorageProvider);
  final baseUrl = ref.watch(baseUrlProvider);
  return createConfiguredDio(tokenStorage: tokenStorage, baseUrl: baseUrl);
});

Dio createConfiguredDio({
  required TokenStorage tokenStorage,
  String? baseUrl,
}) {
  final resolvedBaseUrl = baseUrl ?? AppConfig.apiBaseUrl;

  final dio = Dio(
    BaseOptions(
      baseUrl: resolvedBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 10),
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ),
  );

  // Separate Dio instance for token refresh to avoid interceptor recursion
  final refreshDio = Dio(
    BaseOptions(
      baseUrl: resolvedBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ),
  );

  Completer<String?>? refreshCompleter;

  dio.interceptors.add(
    QueuedInterceptorsWrapper(
      onRequest: (options, handler) async {
        final isPublicAuthPath = options.path.endsWith('/auth/login') ||
            options.path.endsWith('/auth/refresh');

        if (!isPublicAuthPath) {
          final accessToken = await tokenStorage.getAccessToken();
          if (accessToken != null && accessToken.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $accessToken';
          }
        }
        handler.next(options);
      },
      onError: (err, handler) async {
        final statusCode = err.response?.statusCode;
        final path = err.requestOptions.path;
        final alreadyRetried = err.requestOptions.extra['retried'] == true;

        final skipRefresh = path.endsWith('/auth/login') ||
            path.endsWith('/auth/refresh') ||
            path.endsWith('/auth/logout') ||
            path.endsWith('/auth/change-password');

        if (statusCode == 401 && !alreadyRetried && !skipRefresh) {
          try {
            String? newAccessToken;

            if (refreshCompleter != null) {
              newAccessToken = await refreshCompleter!.future;
            } else {
              refreshCompleter = Completer<String?>();
              try {
                final refreshToken = await tokenStorage.getRefreshToken();
                if (refreshToken == null || refreshToken.isEmpty) {
                  await tokenStorage.clearTokens();
                  refreshCompleter!.complete(null);
                  refreshCompleter = null;
                  return handler.next(err);
                }

                final resp = await refreshDio.post<Map<String, dynamic>>(
                  '/auth/refresh',
                  data: {'refresh_token': refreshToken},
                );

                final data = resp.data;
                if (data != null &&
                    data['access_token'] is String &&
                    data['refresh_token'] is String) {
                  newAccessToken = data['access_token'] as String;
                  final newRefreshToken = data['refresh_token'] as String;
                  await tokenStorage.saveTokens(
                    accessToken: newAccessToken,
                    refreshToken: newRefreshToken,
                  );
                  refreshCompleter!.complete(newAccessToken);
                } else {
                  await tokenStorage.clearTokens();
                  refreshCompleter!.complete(null);
                }
              } catch (_) {
                await tokenStorage.clearTokens();
                refreshCompleter!.complete(null);
              } finally {
                refreshCompleter = null;
              }
            }

            if (newAccessToken != null && newAccessToken.isNotEmpty) {
              final retryOptions = err.requestOptions;
              retryOptions.extra['retried'] = true;
              retryOptions.headers['Authorization'] = 'Bearer $newAccessToken';
              final response = await refreshDio.fetch<dynamic>(retryOptions);
              return handler.resolve(response);
            }
          } catch (_) {
            await tokenStorage.clearTokens();
          }
        }

        handler.next(err);
      },
    ),
  );

  return dio;
}

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_client/core/config/app_config.dart';
import 'package:astra_client/core/network/api_exception.dart';
import 'package:astra_client/core/network/auth_interceptor.dart';
import 'package:astra_client/core/storage/cache_store.dart';
import 'package:astra_client/core/storage/token_storage.dart';

final tokenStorageProvider = Provider<TokenStorage>((ref) => SecureTokenStorage());

final cacheStoreProvider = Provider<CacheStore>((ref) => FileCacheStore());

/// Émet un événement quand la session a expiré (refresh refusé) ; le
/// contrôleur d'authentification l'écoute pour renvoyer vers la connexion.
final sessionExpiredProvider = Provider<StreamController<void>>((ref) {
  final controller = StreamController<void>.broadcast();
  ref.onDispose(controller.close);
  return controller;
});

BaseOptions _baseOptions() => BaseOptions(
  baseUrl: AppConfig.apiBaseUrl,
  connectTimeout: AppConfig.connectTimeout,
  receiveTimeout: AppConfig.receiveTimeout,
  contentType: Headers.jsonContentType,
);

final dioProvider = Provider<Dio>((ref) {
  final sessionExpired = ref.watch(sessionExpiredProvider);
  return Dio(_baseOptions())
    ..interceptors.add(
      AuthInterceptor(
        storage: ref.watch(tokenStorageProvider),
        plainDio: Dio(_baseOptions()),
        onSessionExpired: () => sessionExpired.add(null),
      ),
    );
});

/// `true` quand l'écran affiché vient du cache faute de réseau.
final offlineProvider = NotifierProvider<OfflineNotifier, bool>(OfflineNotifier.new);

class OfflineNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) {
    if (state != value) state = value;
  }
}

final apiProvider = Provider<Api>(
  (ref) => Api(
    dio: ref.watch(dioProvider),
    cache: ref.watch(cacheStoreProvider),
    onOffline: (value) => ref.read(offlineProvider.notifier).set(value),
  ),
);

/// Accès à l'API Astra Client. Les lectures sont mises en cache et servies
/// hors ligne ; les écritures exigent toujours le réseau.
class Api {
  Api({required this._dio, required this._cache, required this._onOffline});

  final Dio _dio;
  final CacheStore _cache;
  final void Function(bool offline) _onOffline;

  Dio get dio => _dio;

  Future<T> get<T>(
    String path, {
    Map<String, Object?>? query,
    required T Function(Object? data) parse,
    bool cache = true,
  }) async {
    final key = query == null || query.isEmpty ? path : '$path?$query';
    try {
      final response = await _dio.get<Object?>(path, queryParameters: query);
      _onOffline(false);
      if (cache) unawaited(_cache.write(key, response.data));
      return parse(response.data);
    } on DioException catch (error) {
      final failure = ApiException.fromDio(error);
      if (cache && failure.isOffline) {
        final cached = await _cache.read(key);
        if (cached != null) {
          _onOffline(true);
          return parse(cached);
        }
      }
      throw failure;
    }
  }

  Future<T> post<T>(String path, {Object? data, T Function(Object? data)? parse}) =>
      guardApi(() async {
        final response = await _dio.post<Object?>(path, data: data);
        _onOffline(false);
        return parse == null ? null as T : parse(response.data);
      });

  Future<T> patch<T>(String path, {Object? data, required T Function(Object? data) parse}) =>
      guardApi(() async {
        final response = await _dio.patch<Object?>(path, data: data);
        return parse(response.data);
      });

  Future<void> put(String path, {Object? data}) => guardApi(() => _dio.put<void>(path, data: data));

  Future<void> delete(String path, {Object? data}) =>
      guardApi(() => _dio.delete<void>(path, data: data));
}

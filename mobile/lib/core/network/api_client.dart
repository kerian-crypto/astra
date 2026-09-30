import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_hub/core/config/app_config.dart';
import 'package:astra_hub/core/storage/token_storage.dart';
import 'package:astra_hub/core/network/auth_interceptor.dart';

final tokenStorageProvider = Provider<TokenStorage>((ref) => SecureTokenStorage());

/// Émet un événement quand la session a expiré (refresh refusé) ; le
/// contrôleur d'authentification l'écoute pour renvoyer vers le login.
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

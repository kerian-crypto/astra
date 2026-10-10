import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_client/core/network/api_client.dart';
import 'package:astra_client/core/network/api_exception.dart';
import 'package:astra_client/core/storage/cache_store.dart';
import 'package:astra_client/core/storage/token_storage.dart';
import 'package:astra_client/core/utils/files.dart';
import 'package:astra_client/core/utils/json.dart';
import 'package:astra_client/features/auth/data/session.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    dio: ref.watch(dioProvider),
    storage: ref.watch(tokenStorageProvider),
    cache: ref.watch(cacheStoreProvider),
  ),
);

/// Extrait le jeton d'un lien d'activation collé (ou le jeton seul).
String? tokenFromActivationInput(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;
  final uri = Uri.tryParse(text);
  final fromLink = uri?.queryParameters['token'];
  if (fromLink != null && fromLink.isNotEmpty) return fromLink;
  return RegExp(r'^[A-Za-z0-9_\-]{20,256}$').hasMatch(text) ? text : null;
}

class AuthRepository {
  AuthRepository({required this._dio, required this._storage, required this._cache});

  final Dio _dio;
  final TokenStorage _storage;
  final CacheStore _cache;

  Future<bool> hasSession() async => await _storage.read() != null;

  Future<void> login({required String email, required String password}) => guardApi(() async {
    final response = await _dio.post<Json>(
      '/client/auth/login',
      data: {'email': email.trim(), 'password': password},
    );
    await _storage.write(AuthTokens.fromJson(response.data!));
  });

  /// Active le compte (ou définit un nouveau mot de passe) avec le lien
  /// transmis par Astra, puis ouvre la session.
  Future<void> activate({required String token, required String password}) => guardApi(() async {
    final response = await _dio.post<Json>(
      '/client/auth/activate',
      data: {'token': token, 'password': password},
    );
    await _storage.write(AuthTokens.fromJson(response.data!));
  });

  /// Inscription : crée l'entreprise du client et ouvre la session.
  Future<void> register({
    required String companyName,
    required String fullName,
    required String email,
    required String password,
    String? phone,
    String? country,
  }) => guardApi(() async {
    final response = await _dio.post<Json>(
      '/client/auth/register',
      data: {
        'company_name': companyName.trim(),
        'full_name': fullName.trim(),
        'email': email.trim(),
        'password': password,
        if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
        if (country != null && country.trim().isNotEmpty) 'country': country.trim(),
      },
    );
    await _storage.write(AuthTokens.fromJson(response.data!));
  });

  Future<ClientSession> fetchSession() => guardApi(() async {
    final response = await _dio.get<Json>('/client/me');
    await _cache.write('/client/me', response.data);
    return ClientSession.fromJson(response.data!);
  });

  /// Session déjà enregistrée sur le téléphone, pour démarrer hors ligne.
  Future<ClientSession?> cachedSession() async {
    final data = await _cache.read('/client/me');
    return data is Json ? ClientSession.fromJson(data) : null;
  }

  /// Révoque la session côté serveur puis efface tout ce qui est local :
  /// jetons, cache et fichiers téléchargés (§57).
  Future<void> logout() async {
    final tokens = await _storage.read();
    await _storage.clear();
    await _cache.clear();
    await FileService.clearDownloads();
    if (tokens == null) return;
    try {
      await _dio.post<void>('/client/auth/logout', data: {'refresh_token': tokens.refreshToken});
    } on DioException catch (error) {
      debugPrint('Révocation serveur impossible : ${error.type}');
    }
  }
}

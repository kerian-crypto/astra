import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_hub/core/network/api_client.dart';
import 'package:astra_hub/core/network/api_exception.dart';
import 'package:astra_hub/core/storage/token_storage.dart';
import 'package:astra_hub/features/members/data/member.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(dio: ref.watch(dioProvider), storage: ref.watch(tokenStorageProvider)),
);

class AuthRepository {
  AuthRepository({required this._dio, required this._storage});

  final Dio _dio;
  final TokenStorage _storage;

  Future<bool> hasSession() async => await _storage.read() != null;

  Future<void> login({required String email, required String password}) {
    return guardApi(() async {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/login',
        data: {'email': email.trim(), 'password': password},
      );
      await _storage.write(AuthTokens.fromJson(response.data!));
    });
  }

  Future<Member> fetchCurrentMember() {
    return guardApi(() async {
      final response = await _dio.get<Map<String, dynamic>>('/users/me');
      return Member.fromJson(response.data!);
    });
  }

  /// Révoque la session côté serveur puis efface les tokens locaux.
  /// La déconnexion locale a lieu même si le serveur est injoignable.
  Future<void> logout() async {
    final tokens = await _storage.read();
    await _storage.clear();
    if (tokens == null) return;
    try {
      await _dio.post<void>('/auth/logout', data: {'refresh_token': tokens.refreshToken});
    } on DioException catch (error) {
      debugPrint('Révocation serveur impossible : ${error.type}');
    }
  }
}

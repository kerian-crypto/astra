import 'package:dio/dio.dart';

import 'package:astra_client/core/storage/token_storage.dart';

/// Ajoute l'access token aux requêtes et le renouvelle sur 401.
///
/// `QueuedInterceptor` sérialise les erreurs : si plusieurs requêtes échouent
/// en 401 en même temps, un seul refresh est effectué, les suivantes
/// réutilisent le nouveau token.
class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor({
    required this._storage,
    required this._plainDio,
    required this._onSessionExpired,
  });

  static const _retriedKey = 'astra_client.retried';

  /// Routes publiques : sans jeton, et sans tentative de refresh sur 401.
  /// (`/client/auth/password` exige au contraire la session.)
  static const _publicPaths = {
    '/client/auth/login',
    '/client/auth/activate',
    '/client/auth/register',
    '/client/auth/refresh',
    '/client/auth/logout',
  };

  final TokenStorage _storage;

  /// Dio sans cet intercepteur, pour le refresh et le rejeu. Rejouer via le
  /// Dio principal bloquerait la file de l'intercepteur (interblocage).
  final Dio _plainDio;
  final void Function() _onSessionExpired;

  bool _isAuthEndpoint(RequestOptions options) => _publicPaths.contains(options.path);

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (!_isAuthEndpoint(options)) {
      final tokens = await _storage.read();
      if (tokens != null) {
        options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
      }
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final options = err.requestOptions;
    final shouldTryRefresh =
        err.response?.statusCode == 401 &&
        !_isAuthEndpoint(options) &&
        options.extra[_retriedKey] != true;
    if (!shouldTryRefresh) return handler.next(err);

    final tokens = await _storage.read();
    if (tokens == null) {
      _onSessionExpired();
      return handler.next(err);
    }

    try {
      final sentHeader = options.headers['Authorization'];
      // Un autre appel a déjà renouvelé le token pendant que celui-ci attendait.
      final current = sentHeader == 'Bearer ${tokens.accessToken}'
          ? await _refresh(tokens.refreshToken)
          : tokens;
      if (current == null) {
        await _storage.clear();
        _onSessionExpired();
        return handler.next(err);
      }
      handler.resolve(await _retry(options, current.accessToken));
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  /// Renvoie null si la session est définitivement invalide (401 du serveur).
  /// Une erreur réseau est propagée sans déconnecter l'utilisateur.
  Future<AuthTokens?> _refresh(String refreshToken) async {
    try {
      final response = await _plainDio.post<Map<String, dynamic>>(
        '/client/auth/refresh',
        data: {'refresh_token': refreshToken},
      );
      final tokens = AuthTokens.fromJson(response.data!);
      await _storage.write(tokens);
      return tokens;
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) return null;
      rethrow;
    }
  }

  Future<Response<dynamic>> _retry(RequestOptions options, String accessToken) {
    return _plainDio.fetch<dynamic>(
      options.copyWith(
        headers: {...options.headers, 'Authorization': 'Bearer $accessToken'},
        extra: {...options.extra, _retriedKey: true},
      ),
    );
  }
}

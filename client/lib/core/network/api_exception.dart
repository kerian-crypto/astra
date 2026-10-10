import 'package:dio/dio.dart';

/// Nature d'une erreur, pour choisir l'écran d'état à afficher (§54).
enum ApiErrorKind { offline, unauthorized, forbidden, notFound, validation, server, unknown }

/// Erreur API présentable à l'utilisateur.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.kind = ApiErrorKind.unknown});

  factory ApiException.fromDio(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return const ApiException(
          'Connexion impossible. Vérifiez votre réseau et réessayez.',
          kind: ApiErrorKind.offline,
        );
      default:
        break;
    }
    final response = error.response;
    final status = response?.statusCode;
    return ApiException(
      _detailFrom(response?.data) ?? 'Une erreur inattendue est survenue.',
      statusCode: status,
      kind: switch (status) {
        401 => ApiErrorKind.unauthorized,
        403 => ApiErrorKind.forbidden,
        404 => ApiErrorKind.notFound,
        400 || 409 || 422 => ApiErrorKind.validation,
        final int code when code >= 500 => ApiErrorKind.server,
        _ => ApiErrorKind.unknown,
      },
    );
  }

  final String message;
  final int? statusCode;
  final ApiErrorKind kind;

  bool get isUnauthorized => kind == ApiErrorKind.unauthorized;
  bool get isOffline => kind == ApiErrorKind.offline;

  /// Le backend renvoie `{"detail": "..."}`, ou une liste d'erreurs de
  /// validation (422) dont on ne montre que la première.
  static String? _detailFrom(Object? data) {
    if (data is! Map) return null;
    final detail = data['detail'];
    if (detail is String) return detail;
    if (detail is List && detail.isNotEmpty && detail.first is Map) {
      final message = (detail.first as Map)['msg'] as String?;
      return message?.replaceFirst('Value error, ', '');
    }
    return null;
  }

  @override
  String toString() => message;
}

/// Exécute un appel Dio et convertit ses erreurs en [ApiException].
Future<T> guardApi<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on DioException catch (error) {
    throw ApiException.fromDio(error);
  }
}

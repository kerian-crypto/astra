import 'package:dio/dio.dart';

/// Erreur API présentable à l'utilisateur.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  factory ApiException.fromDio(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return const ApiException('Connexion impossible. Vérifiez votre réseau et réessayez.');
      default:
        break;
    }
    final response = error.response;
    return ApiException(
      _detailFrom(response?.data) ?? 'Une erreur inattendue est survenue.',
      statusCode: response?.statusCode,
    );
  }

  final String message;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;

  /// Le backend renvoie `{"detail": "..."}`, ou une liste d'erreurs de
  /// validation (422) dont on ne montre que la première.
  static String? _detailFrom(Object? data) {
    if (data is! Map) return null;
    final detail = data['detail'];
    if (detail is String) return detail;
    if (detail is List && detail.isNotEmpty && detail.first is Map) {
      return (detail.first as Map)['msg'] as String?;
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

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_hub/core/network/api_client.dart';
import 'package:astra_hub/core/push/push_messaging.dart';
import 'package:astra_hub/core/router/routes.dart';

/// Remplacé au démarrage (main.dart) quand Firebase est configuré.
final pushMessagingProvider = Provider<PushMessaging?>((_) => null);

final pushServiceProvider = Provider<PushService>((ref) {
  final service = PushService(
    dio: ref.watch(dioProvider),
    messaging: ref.watch(pushMessagingProvider),
    platform: defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Écran à ouvrir pour un push touché ; `null` : aucun.
String? routeForPush(PushData data) {
  final entityType = data['entity_type'];
  final entityId = data['entity_id'];
  if (entityType is! String || entityId is! String) return null;
  return Routes.forEntity(entityType, entityId);
}

/// Relie l'appareil au compte connecté pour recevoir les notifications push.
class PushService {
  PushService({required this._dio, required this._messaging, required this._platform});

  final Dio _dio;
  final PushMessaging? _messaging;
  final String _platform;
  StreamSubscription<String>? _tokenRefresh;

  bool get isAvailable => _messaging != null;

  /// À appeler une fois connecté. Sans effet si Firebase est absent ou si le
  /// membre refuse les notifications ; ne lève jamais d'exception.
  Future<void> register() async {
    final messaging = _messaging;
    if (messaging == null) return;
    try {
      if (!await messaging.requestPermission()) return;
      final token = await messaging.getToken();
      if (token != null) await _send(token);
      await _tokenRefresh?.cancel();
      _tokenRefresh = messaging.onTokenRefresh.listen((token) => unawaited(_send(token)));
    } on Object catch (error) {
      debugPrint('Enregistrement push impossible : $error');
    }
  }

  Future<void> _send(String token) async {
    try {
      await _dio.put<void>('/devices', data: {'token': token, 'platform': _platform});
    } on DioException catch (error) {
      debugPrint('Jeton push non transmis : ${error.type}');
    }
  }

  /// Avant la déconnexion (session encore valide) : le serveur oublie
  /// l'appareil, puis le jeton est invalidé chez Firebase.
  Future<void> unregister() async {
    final messaging = _messaging;
    if (messaging == null) return;
    await _tokenRefresh?.cancel();
    _tokenRefresh = null;
    try {
      final token = await messaging.getToken();
      if (token != null) {
        await _dio.post<void>('/devices/unregister', data: {'token': token});
      }
    } on Object catch (error) {
      debugPrint('Désinscription push côté serveur impossible : $error');
    }
    await forgetDevice();
  }

  /// Session expirée : plus d'appel authentifié possible. Invalider le jeton
  /// suffit : le serveur l'oubliera au prochain envoi refusé par Firebase.
  Future<void> forgetDevice() async {
    await _tokenRefresh?.cancel();
    _tokenRefresh = null;
    try {
      await _messaging?.deleteToken();
    } on Object catch (error) {
      debugPrint('Suppression du jeton push impossible : $error');
    }
  }

  /// Push touchés par le membre : celui qui a lancé l'app, puis les suivants.
  Stream<PushData> openedMessages() async* {
    final messaging = _messaging;
    if (messaging == null) return;
    final initial = await messaging.initialMessage();
    if (initial != null) yield initial;
    yield* messaging.onMessageOpened;
  }

  /// Marque lue la notification correspondant au push (s'il y en a une).
  Future<void> markOpened(PushData data) async {
    final id = data['notification_id'];
    if (id is! String) return;
    try {
      await _dio.post<void>('/notifications/$id/read');
    } on DioException catch (error) {
      debugPrint('Notification non marquée lue : ${error.type}');
    }
  }

  Future<void> dispose() async => _tokenRefresh?.cancel();
}

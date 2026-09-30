import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:astra_hub/core/config/app_config.dart';
import 'package:astra_hub/core/network/api_client.dart';
import 'package:astra_hub/core/storage/token_storage.dart';
import 'package:astra_hub/core/utils/json.dart';

typedef ChannelFactory = WebSocketChannel Function(Uri uri);

/// Connexion temps réel au serveur (messages, notifications).
///
/// Le token est envoyé dans le premier message, jamais dans l'URL. Le serveur
/// ferme la connexion à l'expiration du token : on se reconnecte avec un
/// token rafraîchi par un appel HTTP (qui passe par l'intercepteur).
class RealtimeService {
  RealtimeService({required this._storage, required this._refreshSession, ChannelFactory? connect})
    : _connect = connect ?? WebSocketChannel.connect;

  static const _maxBackoff = Duration(seconds: 30);
  static const _closeUnauthorized = 4001;

  final TokenStorage _storage;
  final Future<void> Function() _refreshSession;
  final ChannelFactory _connect;
  final _events = StreamController<Json>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _retry;
  int _attempt = 0;
  bool _running = false;

  Stream<Json> get events => _events.stream;

  static Uri socketUri(String apiBaseUrl) {
    final base = Uri.parse(apiBaseUrl);
    return base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '${base.path.replaceAll(RegExp(r'/$'), '')}/ws',
    );
  }

  void start() {
    if (_running) return;
    _running = true;
    unawaited(_open());
  }

  Future<void> stop() async {
    _running = false;
    _retry?.cancel();
    await _subscription?.cancel();
    await _channel?.sink.close();
    _channel = null;
  }

  Future<void> dispose() async {
    await stop();
    await _events.close();
  }

  Future<void> _open() async {
    final tokens = await _storage.read();
    if (!_running || tokens == null) return;
    try {
      final channel = _connect(socketUri(AppConfig.apiBaseUrl));
      _channel = channel;
      await channel.ready;
      channel.sink.add(jsonEncode({'type': 'auth', 'token': tokens.accessToken}));
      _subscription = channel.stream.listen(
        _onData,
        onDone: () => _onClosed(channel.closeCode),
        onError: (Object _) => _onClosed(null),
      );
    } on Object catch (error) {
      debugPrint('Temps réel indisponible : $error');
      _scheduleReconnect();
    }
  }

  void _onData(dynamic raw) {
    final Object? message;
    try {
      message = jsonDecode(raw as String);
    } on FormatException {
      return;
    }
    if (message is! Json) return;
    if (message['type'] == 'ready') {
      _attempt = 0;
      return;
    }
    _events.add(message);
  }

  Future<void> _onClosed(int? code) async {
    _channel = null;
    if (!_running) return;
    if (code == _closeUnauthorized) {
      try {
        await _refreshSession();
      } on Object catch (error) {
        debugPrint('Rafraîchissement de session impossible : $error');
      }
    }
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!_running) return;
    _attempt += 1;
    final seconds = min(_maxBackoff.inSeconds, pow(2, min(_attempt, 5)).toInt());
    _retry?.cancel();
    _retry = Timer(Duration(seconds: seconds), () => unawaited(_open()));
  }
}

final realtimeServiceProvider = Provider<RealtimeService>((ref) {
  final dio = ref.watch(dioProvider);
  final service = RealtimeService(
    storage: ref.watch(tokenStorageProvider),
    // Un appel authentifié déclenche le rafraîchissement du token si besoin.
    refreshSession: () => dio.get<void>('/users/me'),
  );
  ref.onDispose(service.dispose);
  return service;
});

import 'dart:async';
import 'dart:convert';

import 'package:astra_hub/core/network/api_client.dart';
import 'package:astra_hub/core/network/realtime.dart';
import 'package:astra_hub/core/storage/token_storage.dart';
import 'package:astra_hub/features/chat/data/chat.dart';
import 'package:astra_hub/features/chat/data/chat_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fake_http.dart';

/// Canal WebSocket en mémoire : `server` reçoit ce que l'app envoie et
/// peut lui pousser des messages.
class FakeSocket with StreamChannelMixin<dynamic> implements WebSocketChannel {
  final _incoming = StreamController<dynamic>();
  final sent = <dynamic>[];
  int? code;

  void push(Map<String, dynamic> event) => _incoming.add(jsonEncode(event));

  Future<void> serverClose(int closeCode) async {
    code = closeCode;
    await _incoming.close();
  }

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  WebSocketSink get sink => _Sink(sent);

  @override
  Future<void> get ready => Future.value();

  @override
  int? get closeCode => code;

  @override
  String? get closeReason => null;

  @override
  String? get protocol => null;
}

class _Sink implements WebSocketSink {
  _Sink(this.sent);

  final List<dynamic> sent;

  @override
  void add(dynamic data) => sent.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) async {}

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {}

  @override
  Future<void> get done => Future.value();
}

void main() {
  group('RealtimeService', () {
    test('builds ws/wss URLs from the API base URL', () {
      expect(
        RealtimeService.socketUri('http://10.0.2.2:8000/api/v1').toString(),
        'ws://10.0.2.2:8000/api/v1/ws',
      );
      expect(
        RealtimeService.socketUri('https://astra.example/api/v1/').toString(),
        'wss://astra.example/api/v1/ws',
      );
    });

    test('authenticates in the first message and forwards events', () async {
      final socket = FakeSocket();
      final service = RealtimeService(
        storage: InMemoryTokenStorage(const AuthTokens(accessToken: 'tok', refreshToken: 'r')),
        refreshSession: () async {},
        connect: (_) => socket,
      );
      final events = <Map<String, dynamic>>[];
      final subscription = service.events.listen(events.add);

      service.start();
      await Future<void>.delayed(Duration.zero);
      socket
        ..push({'type': 'ready'})
        ..push({'type': 'message.created', 'channel_id': 'c1'});
      await Future<void>.delayed(Duration.zero);

      expect(jsonDecode(socket.sent.single as String), {'type': 'auth', 'token': 'tok'});
      expect(events, [
        {'type': 'message.created', 'channel_id': 'c1'},
      ]);
      await subscription.cancel();
      await service.dispose();
    });

    test('refreshes the session when the server closes for expiry', () async {
      final socket = FakeSocket();
      var refreshed = 0;
      final service = RealtimeService(
        storage: InMemoryTokenStorage(const AuthTokens(accessToken: 'tok', refreshToken: 'r')),
        refreshSession: () async => refreshed++,
        connect: (_) => socket,
      );

      service.start();
      await Future<void>.delayed(Duration.zero);
      await socket.serverClose(4001);
      await Future<void>.delayed(Duration.zero);

      expect(refreshed, 1);
      await service.dispose();
    });

    test('does not connect without a session', () async {
      var connections = 0;
      final service = RealtimeService(
        storage: InMemoryTokenStorage(),
        refreshSession: () async {},
        connect: (_) {
          connections++;
          return FakeSocket();
        },
      );

      service.start();
      await Future<void>.delayed(Duration.zero);

      expect(connections, 0);
      await service.dispose();
    });
  });

  group('ChannelMessages', () {
    ProviderContainer container(FakeHandler handler) {
      final c = ProviderContainer(
        overrides: [
          tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
          dioProvider.overrideWithValue(fakeDio(FakeHttpAdapter(handler))),
        ],
        retry: (_, _) => null,
      );
      addTearDown(c.dispose);
      return c;
    }

    test('upsert prepends new messages and replaces existing ones', () async {
      final c = container((_) async => FakeResponse(200, [messageJson()]));
      final provider = channelMessagesProvider('c1');
      final sub = c.listen(provider, (_, _) {});
      addTearDown(sub.close);
      await c.read(provider.future);
      final notifier = c.read(provider.notifier);

      notifier.upsert(ChatMessage.fromJson(messageJson(id: 'm2', body: 'Nouveau')));
      notifier.upsert(ChatMessage.fromJson(messageJson(id: 'm1', body: 'Modifié')));

      expect(c.read(provider).value!.map((m) => m.body), ['Nouveau', 'Modifié']);
    });

    test('loadMore asks for older messages with a before cursor', () async {
      final queries = <Map<String, dynamic>>[];
      final page = [for (var i = 0; i < ChatRepository.pageSize; i++) messageJson(id: 'm$i')];
      final c = container((options) async {
        queries.add(options.queryParameters);
        return FakeResponse(200, queries.length == 1 ? page : [messageJson(id: 'old')]);
      });
      final provider = channelMessagesProvider('c1');
      final sub = c.listen(provider, (_, _) {});
      addTearDown(sub.close);
      await c.read(provider.future);

      await c.read(provider.notifier).loadMore();

      expect(queries.last.containsKey('before'), isTrue);
      expect(c.read(provider).value!.last.id, 'old');
      expect(c.read(provider.notifier).hasMore, isFalse);
    });
  });
}

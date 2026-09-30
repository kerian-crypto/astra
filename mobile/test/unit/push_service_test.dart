import 'dart:async';

import 'package:astra_hub/core/push/push_messaging.dart';
import 'package:astra_hub/core/push/push_service.dart';
import 'package:astra_hub/core/router/routes.dart';
import 'package:astra_hub/features/chat/data/chat.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_http.dart';

class FakeMessaging implements PushMessaging {
  bool permitted = true;
  String? token = 'device-token';
  PushData? launchedWith;
  bool deleted = false;
  final refreshes = StreamController<String>.broadcast();
  final opened = StreamController<PushData>.broadcast();

  @override
  Future<bool> requestPermission() async => permitted;

  @override
  Future<String?> getToken() async => token;

  @override
  Stream<String> get onTokenRefresh => refreshes.stream;

  @override
  Future<void> deleteToken() async => deleted = true;

  @override
  Future<PushData?> initialMessage() async => launchedWith;

  @override
  Stream<PushData> get onMessageOpened => opened.stream;
}

void main() {
  group('routeForPush', () {
    test('opens the screen of the notified entity', () {
      expect(routeForPush({'entity_type': 'task', 'entity_id': 't1'}), Routes.task('t1'));
      expect(routeForPush({'entity_type': 'channel', 'entity_id': 'c1'}), Routes.chat('c1'));
      expect(routeForPush({'entity_type': 'project', 'entity_id': 'p1'}), Routes.project('p1'));
      expect(routeForPush({'entity_type': 'meeting', 'entity_id': 'm1'}), Routes.meeting('m1'));
      expect(routeForPush({'entity_type': 'ai_conversation', 'entity_id': 'a1'}), Routes.ai);
    });

    test('opens nothing for deleted or malformed targets', () {
      expect(routeForPush({'entity_type': 'deleted', 'entity_id': 'm1'}), isNull);
      expect(routeForPush({'entity_type': 'task'}), isNull);
      expect(routeForPush({}), isNull);
    });
  });

  test('parses every notification kind sent by the API', () {
    for (final kind in NotificationKind.values.where((k) => k != NotificationKind.other)) {
      expect(NotificationKind.parse(kind.wire), kind);
    }
    expect(NotificationKind.parse('inconnu'), NotificationKind.other);
    expect(NotificationKind.parse(''), NotificationKind.other);
  });

  group('PushService', () {
    late FakeHttpAdapter adapter;
    late FakeMessaging messaging;

    PushService build({PushMessaging? using}) {
      adapter = FakeHttpAdapter((_) async => const FakeResponse(204));
      return PushService(dio: fakeDio(adapter), messaging: using, platform: 'android');
    }

    setUp(() => messaging = FakeMessaging());

    test('registers the device token, then every refreshed token', () async {
      final service = build(using: messaging);

      await service.register();
      messaging.refreshes.add('new-token');
      await pumpEventQueue();

      expect(adapter.requests.map((r) => '${r.method} ${r.path}'), [
        'PUT /devices',
        'PUT /devices',
      ]);
      expect(adapter.requests.map((r) => r.data), [
        {'token': 'device-token', 'platform': 'android'},
        {'token': 'new-token', 'platform': 'android'},
      ]);
      await service.dispose();
    });

    test('does nothing when notifications are refused', () async {
      messaging.permitted = false;
      final service = build(using: messaging);

      await service.register();

      expect(adapter.requests, isEmpty);
    });

    test('is a no-op without Firebase', () async {
      final service = build();

      await service.register();
      await service.unregister();

      expect(service.isAvailable, isFalse);
      expect(adapter.requests, isEmpty);
      expect(await service.openedMessages().toList(), isEmpty);
    });

    test('logout unregisters on the server then deletes the token', () async {
      final service = build(using: messaging);

      await service.unregister();

      expect(adapter.requests.single.path, '/devices/unregister');
      expect(adapter.requests.single.data, {'token': 'device-token'});
      expect(messaging.deleted, isTrue);
    });

    test('server errors never break registration or logout', () async {
      adapter = FakeHttpAdapter((_) async => const FakeResponse(500));
      final service = PushService(dio: fakeDio(adapter), messaging: messaging, platform: 'ios');

      await service.register();
      await service.unregister();

      expect(messaging.deleted, isTrue);
    });

    test('yields the launching push first, then the opened ones', () async {
      messaging.launchedWith = {'entity_type': 'task', 'entity_id': 't1'};
      final service = build(using: messaging);
      final received = <PushData>[];

      final subscription = service.openedMessages().listen(received.add);
      await pumpEventQueue();
      messaging.opened.add({'entity_type': 'channel', 'entity_id': 'c1'});
      await pumpEventQueue();

      expect(received.map(routeForPush), [Routes.task('t1'), Routes.chat('c1')]);
      await subscription.cancel();
    });

    test('marks the matching notification read when a push is opened', () async {
      final service = build(using: messaging);

      await service.markOpened({'notification_id': 'n1'});
      await service.markOpened({'type': 'message'});

      expect(adapter.requests.single.path, '/notifications/n1/read');
    });
  });
}

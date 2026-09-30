import 'package:astra_hub/core/network/api_client.dart';
import 'package:astra_hub/core/network/api_exception.dart';
import 'package:astra_hub/core/router/app_router.dart';
import 'package:astra_hub/core/storage/token_storage.dart';
import 'package:astra_hub/features/auth/presentation/auth_controller.dart';
import 'package:astra_hub/features/members/data/member.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_http.dart';

void main() {
  group('authRedirect', () {
    const loading = AsyncLoading<Object?>();
    const loggedOut = AsyncData<Object?>(null);
    final loggedIn = AsyncData<Object?>(Member.fromJson(memberJson()));
    const failed = AsyncError<Object?>('offline', StackTrace.empty);

    test('holds on the splash screen while the session loads', () {
      expect(authRedirect(loading, Routes.projects), Routes.splash);
      expect(authRedirect(loading, Routes.splash), isNull);
    });

    test('shows the splash screen (with retry) on startup error', () {
      expect(authRedirect(failed, Routes.today), Routes.splash);
    });

    test('sends logged-out users to login', () {
      expect(authRedirect(loggedOut, Routes.projects), Routes.login);
      expect(authRedirect(loggedOut, Routes.login), isNull);
    });

    test('registration is public but not for signed-in members', () {
      expect(authRedirect(loggedOut, Routes.register), isNull);
      expect(authRedirect(loggedIn, Routes.register), Routes.today);
    });

    test('sends logged-in users away from public screens', () {
      expect(authRedirect(loggedIn, Routes.login), Routes.today);
      expect(authRedirect(loggedIn, Routes.splash), Routes.today);
      expect(authRedirect(loggedIn, Routes.project('p1')), isNull);
    });
  });

  group('AuthController', () {
    late InMemoryTokenStorage storage;
    late FakeHttpAdapter adapter;

    ProviderContainer buildContainer(FakeHandler handler) {
      adapter = FakeHttpAdapter(handler);
      final container = ProviderContainer(
        overrides: [
          tokenStorageProvider.overrideWithValue(storage),
          dioProvider.overrideWithValue(fakeDio(adapter)),
        ],
        // Pas de nouvelle tentative automatique : on teste l'état d'erreur.
        retry: (_, _) => null,
      );
      addTearDown(container.dispose);
      return container;
    }

    setUp(() => storage = InMemoryTokenStorage());

    test('starts logged out when no token is stored', () async {
      final container = buildContainer((_) async => const FakeResponse(500));

      expect(await container.read(authControllerProvider.future), isNull);
      expect(adapter.requests, isEmpty);
    });

    test('restores the member when a session exists', () async {
      await storage.write(const AuthTokens(accessToken: 'a', refreshToken: 'r'));
      final container = buildContainer((_) async => FakeResponse(200, memberJson()));

      final member = await container.read(authControllerProvider.future);

      expect(member?.fullName, 'Ada Lovelace');
    });

    test('drops an invalid stored session', () async {
      await storage.write(const AuthTokens(accessToken: 'a', refreshToken: 'r'));
      final container = buildContainer(
        (options) async =>
            options.path == '/users/me' ? const FakeResponse(401) : const FakeResponse(204),
      );

      expect(await container.read(authControllerProvider.future), isNull);
      expect(await storage.read(), isNull);
    });

    test('surfaces a network error at startup without dropping the session', () async {
      await storage.write(const AuthTokens(accessToken: 'a', refreshToken: 'r'));
      final container = buildContainer((_) async => const FakeResponse(503));

      await expectLater(
        container.read(authControllerProvider.future),
        throwsA(isA<ApiException>()),
      );
      expect(await storage.read(), isNotNull);
    });

    test('login stores tokens and exposes the member', () async {
      final container = buildContainer(
        (options) async => options.path == '/auth/login'
            ? const FakeResponse(200, {'access_token': 'a', 'refresh_token': 'r'})
            : FakeResponse(200, memberJson()),
      );
      await container.read(authControllerProvider.future);

      await container
          .read(authControllerProvider.notifier)
          .login(email: ' ada@astra.example.com ', password: 'secret');

      expect(container.read(authControllerProvider).value?.fullName, 'Ada Lovelace');
      expect((await storage.read())?.accessToken, 'a');
      expect(adapter.requests.first.data, {'email': 'ada@astra.example.com', 'password': 'secret'});
    });

    test('login failure throws the backend message and stays logged out', () async {
      final container = buildContainer(
        (_) async => const FakeResponse(401, {'detail': 'Email ou mot de passe incorrect.'}),
      );
      await container.read(authControllerProvider.future);

      await expectLater(
        container.read(authControllerProvider.notifier).login(email: 'a@b.co', password: 'x'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('incorrect'))),
      );
      expect(container.read(authControllerProvider).value, isNull);
    });

    test('logout clears tokens and revokes the session server-side', () async {
      await storage.write(const AuthTokens(accessToken: 'a', refreshToken: 'r'));
      final container = buildContainer(
        (options) async =>
            options.path == '/users/me' ? FakeResponse(200, memberJson()) : const FakeResponse(204),
      );
      await container.read(authControllerProvider.future);

      await container.read(authControllerProvider.notifier).logout();

      expect(container.read(authControllerProvider).value, isNull);
      expect(await storage.read(), isNull);
      expect(adapter.requests.last.path, '/auth/logout');
      expect(adapter.requests.last.data, {'refresh_token': 'r'});
    });

    test('session expiry event logs the member out', () async {
      await storage.write(const AuthTokens(accessToken: 'a', refreshToken: 'r'));
      final container = buildContainer((_) async => FakeResponse(200, memberJson()));
      await container.read(authControllerProvider.future);

      container.read(sessionExpiredProvider).add(null);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(authControllerProvider).value, isNull);
    });
  });
}

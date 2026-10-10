import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:astra_client/core/network/api_client.dart';
import 'package:astra_client/core/network/api_exception.dart';
import 'package:astra_client/core/network/auth_interceptor.dart';
import 'package:astra_client/core/router/app_router.dart';
import 'package:astra_client/core/storage/cache_store.dart';
import 'package:astra_client/core/storage/token_storage.dart';
import 'package:astra_client/core/utils/formatting.dart';
import 'package:astra_client/features/auth/data/auth_repository.dart';
import 'package:astra_client/features/auth/data/session.dart';
import 'package:astra_client/features/billing/data/billing.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fake_http.dart';

void main() {
  group('ApiException', () {
    DioException error(int status, [Object? data]) => DioException(
      requestOptions: RequestOptions(path: '/x'),
      response: Response(
        requestOptions: RequestOptions(path: '/x'),
        statusCode: status,
        data: data,
      ),
      type: DioExceptionType.badResponse,
    );

    test('maps HTTP statuses to UI error kinds', () {
      expect(ApiException.fromDio(error(403)).kind, ApiErrorKind.forbidden);
      expect(ApiException.fromDio(error(404)).kind, ApiErrorKind.notFound);
      expect(ApiException.fromDio(error(401)).kind, ApiErrorKind.unauthorized);
      expect(ApiException.fromDio(error(503)).kind, ApiErrorKind.server);
      final offline = ApiException.fromDio(
        DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: DioExceptionType.connectionError,
        ),
      );
      expect(offline.isOffline, isTrue);
    });

    test('shows the first validation message without the pydantic prefix', () {
      final failure = ApiException.fromDio(
        error(422, {
          'detail': [
            {'msg': 'Value error, Le motif du refus est obligatoire.'},
          ],
        }),
      );
      expect(failure.message, 'Le motif du refus est obligatoire.');
    });
  });

  group('Api cache', () {
    test('serves cached data when offline and flags the offline state', () async {
      var online = true;
      final adapter = FakeHttpAdapter((options) async {
        if (!online) {
          throw DioException(requestOptions: options, type: DioExceptionType.connectionError);
        }
        return const FakeResponse(200, {'value': 1});
      });
      final container = ProviderContainer(
        overrides: [
          dioProvider.overrideWithValue(fakeDio(adapter)),
          cacheStoreProvider.overrideWithValue(MemoryCacheStore()),
        ],
      );
      addTearDown(container.dispose);
      final api = container.read(apiProvider);

      final first = await api.get('/client/projects', parse: (data) => data);
      await Future<void>.delayed(Duration.zero);
      online = false;
      final cached = await api.get('/client/projects', parse: (data) => data);

      expect(first, {'value': 1});
      expect(cached, {'value': 1});
      expect(container.read(offlineProvider), isTrue);
    });

    test('offline without cache raises an offline error', () async {
      final adapter = FakeHttpAdapter(
        (options) async =>
            throw DioException(requestOptions: options, type: DioExceptionType.connectionError),
      );
      final container = ProviderContainer(
        overrides: [
          dioProvider.overrideWithValue(fakeDio(adapter)),
          cacheStoreProvider.overrideWithValue(MemoryCacheStore()),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(apiProvider).get('/client/invoices', parse: (data) => data),
        throwsA(isA<ApiException>().having((e) => e.isOffline, 'offline', isTrue)),
      );
    });
  });

  group('AuthInterceptor', () {
    test('sends the token on /client/auth/password but not on login', () async {
      final adapter = FakeHttpAdapter((_) async => const FakeResponse(204));
      final dio = fakeDio(adapter)
        ..interceptors.add(
          AuthInterceptor(
            storage: InMemoryTokenStorage(const AuthTokens(accessToken: 'tok', refreshToken: 'r')),
            plainDio: fakeDio(adapter),
            onSessionExpired: () {},
          ),
        );

      await dio.post<void>('/client/auth/login');
      await dio.post<void>('/client/auth/password');

      expect(adapter.requests[0].headers['Authorization'], isNull);
      expect(adapter.requests[1].headers['Authorization'], 'Bearer tok');
    });
  });

  group('activation link', () {
    test('extracts the token from a link or accepts a raw token', () {
      const token = 'abcdefghijklmnopqrstuvwxyz0123456789';
      expect(tokenFromActivationInput('astraclient://app/activate?token=$token'), token);
      expect(tokenFromActivationInput('  $token '), token);
      expect(tokenFromActivationInput('bonjour'), isNull);
      expect(tokenFromActivationInput(''), isNull);
    });
  });

  group('authRedirect', () {
    Uri at(String path) => Uri.parse(path);

    test('logged out users go to login, but the activation link stays open', () {
      const loggedOut = AsyncData<Object?>(null);
      expect(authRedirect(loggedOut, at('/home')), Routes.login);
      expect(authRedirect(loggedOut, at('/activate?token=x')), isNull);
      expect(authRedirect(loggedOut, at('/login')), isNull);
    });

    test('logged in users leave public screens for the dashboard', () {
      final session = ClientSession.fromJson(meJson());
      expect(authRedirect(AsyncData<Object?>(session), at('/login')), Routes.home);
      expect(authRedirect(AsyncData<Object?>(session), at('/projects')), isNull);
    });

    test('loading goes to splash', () {
      expect(authRedirect(const AsyncLoading<Object?>(), at('/home')), Routes.splash);
    });
  });

  group('deep links', () {
    test('every notification target opens a screen', () {
      for (final type in [
        'project',
        'deliverable',
        'document',
        'invoice',
        'payment_declaration',
        'contract',
        'support_ticket',
        'client_conversation',
      ]) {
        expect(Routes.forEntity(type, 'x'), isNotNull, reason: type);
      }
      expect(Routes.forEntity('task', 'x'), isNull);
    });
  });

  group('models and formatting', () {
    test('session exposes permissions', () {
      final limited = ClientSession.fromJson(meJson(permissions: ['view_project', 'unknown']));
      expect(limited.can(ClientPermission.viewProject), isTrue);
      expect(limited.can(ClientPermission.viewInvoice), isFalse);
      expect(limited.firstName, 'Jean');
    });

    test('invoice parses amounts and payment status', () {
      final detail = InvoiceDetail.fromJson(
        invoiceJson(status: 'partially_confirmed', remaining: '500.00'),
      );
      expect(detail.invoice.paymentStatus, PaymentStatus.partial);
      expect(detail.invoice.remainingAmount, 500);
      expect(detail.canDeclare, isTrue);
    });

    test('formats FCFA amounts and due dates', () {
      expect(formatMoney(1500000, 'XOF'), contains('FCFA'));
      final today = DateTime(2026, 10, 7);
      expect(formatDue(DateTime(2026, 10, 7), today: today), 'aujourd\'hui');
      expect(formatDue(DateTime(2026, 10, 10), today: today), 'dans 3 jours');
      expect(formatDue(DateTime(2026, 10, 5), today: today), 'en retard de 2 jours');
      expect(initials('Jean Dupont'), 'JD');
    });
  });
}

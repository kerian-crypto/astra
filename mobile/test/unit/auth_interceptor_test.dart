import 'package:astra_hub/core/network/auth_interceptor.dart';
import 'package:astra_hub/core/storage/token_storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_http.dart';

const _oldTokens = AuthTokens(accessToken: 'old-access', refreshToken: 'old-refresh');
const _newTokens = {'access_token': 'new-access', 'refresh_token': 'new-refresh'};

void main() {
  late InMemoryTokenStorage storage;
  late int sessionExpiredCount;

  setUp(() {
    storage = InMemoryTokenStorage(_oldTokens);
    sessionExpiredCount = 0;
  });

  /// Dio principal (avec intercepteur) sur [api], refresh/rejeu sur [plain].
  Dio buildDio({required FakeHttpAdapter api, required FakeHttpAdapter plain}) {
    return fakeDio(api)
      ..interceptors.add(
        AuthInterceptor(
          storage: storage,
          plainDio: fakeDio(plain),
          onSessionExpired: () => sessionExpiredCount++,
        ),
      );
  }

  test('adds the bearer token to API requests', () async {
    final api = FakeHttpAdapter((_) async => const FakeResponse(200, {}));
    final dio = buildDio(api: api, plain: FakeHttpAdapter((_) async => const FakeResponse(500)));

    await dio.get<void>('/users/me');

    expect(api.requests.single.headers['Authorization'], 'Bearer old-access');
  });

  test('does not attach a token to auth endpoints', () async {
    final api = FakeHttpAdapter((_) async => const FakeResponse(200, _newTokens));
    final dio = buildDio(api: api, plain: FakeHttpAdapter((_) async => const FakeResponse(500)));

    await dio.post<void>('/auth/login', data: {});

    expect(api.requests.single.headers.containsKey('Authorization'), isFalse);
  });

  test('refreshes on 401 then retries the request with the new token', () async {
    final api = FakeHttpAdapter((_) async => const FakeResponse(401, {'detail': 'expired'}));
    final plain = FakeHttpAdapter(
      (options) async => options.path == '/auth/refresh'
          ? const FakeResponse(200, _newTokens)
          : const FakeResponse(200, {'ok': true}),
    );
    final dio = buildDio(api: api, plain: plain);

    final response = await dio.get<Map<String, dynamic>>('/users/me');

    expect(response.data, {'ok': true});
    expect(plain.requests.first.data, {'refresh_token': 'old-refresh'});
    expect(plain.requests.last.headers['Authorization'], 'Bearer new-access');
    expect((await storage.read())?.accessToken, 'new-access');
    expect(sessionExpiredCount, 0);
  });

  test('refreshes only once for concurrent 401s', () async {
    final api = FakeHttpAdapter((_) async => const FakeResponse(401));
    final plain = FakeHttpAdapter(
      (options) async => options.path == '/auth/refresh'
          ? const FakeResponse(200, _newTokens)
          : const FakeResponse(200, {}),
    );
    final dio = buildDio(api: api, plain: plain);

    await Future.wait([dio.get<void>('/a'), dio.get<void>('/b'), dio.get<void>('/c')]);

    final refreshCalls = plain.requests.where((r) => r.path == '/auth/refresh');
    expect(refreshCalls, hasLength(1));
  });

  test('clears the session when the refresh token is rejected', () async {
    final api = FakeHttpAdapter((_) async => const FakeResponse(401));
    final plain = FakeHttpAdapter((_) async => const FakeResponse(401));
    final dio = buildDio(api: api, plain: plain);

    await expectLater(dio.get<void>('/users/me'), throwsA(isA<DioException>()));

    expect(await storage.read(), isNull);
    expect(sessionExpiredCount, 1);
  });

  test('keeps the session when refresh fails for a network reason', () async {
    final api = FakeHttpAdapter((_) async => const FakeResponse(401));
    final plain = FakeHttpAdapter((_) async => const FakeResponse(503));
    final dio = buildDio(api: api, plain: plain);

    await expectLater(dio.get<void>('/users/me'), throwsA(isA<DioException>()));

    expect((await storage.read())?.refreshToken, 'old-refresh');
    expect(sessionExpiredCount, 0);
  });

  test('signals session expiry on 401 when no token is stored', () async {
    await storage.clear();
    final api = FakeHttpAdapter((_) async => const FakeResponse(401));
    final dio = buildDio(api: api, plain: FakeHttpAdapter((_) async => const FakeResponse(500)));

    await expectLater(dio.get<void>('/users/me'), throwsA(isA<DioException>()));

    expect(sessionExpiredCount, 1);
  });

  test('does not try to refresh on non-401 errors', () async {
    final api = FakeHttpAdapter((_) async => const FakeResponse(403));
    final plain = FakeHttpAdapter((_) async => const FakeResponse(200, _newTokens));
    final dio = buildDio(api: api, plain: plain);

    await expectLater(dio.get<void>('/projects/x'), throwsA(isA<DioException>()));

    expect(plain.requests, isEmpty);
  });
}

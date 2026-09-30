import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

typedef FakeHandler = Future<FakeResponse> Function(RequestOptions options);

class FakeResponse {
  const FakeResponse(this.statusCode, [this.body]);

  final int statusCode;
  final Object? body;
}

/// Adaptateur HTTP en mémoire : enregistre les requêtes et répond via [handler].
class FakeHttpAdapter implements HttpClientAdapter {
  FakeHttpAdapter(this.handler);

  final FakeHandler handler;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final response = await handler(options);
    return ResponseBody.fromString(
      response.body == null ? '' : jsonEncode(response.body),
      response.statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Dio fakeDio(FakeHttpAdapter adapter) =>
    Dio(BaseOptions(baseUrl: 'https://api.test/api/v1'))..httpClientAdapter = adapter;

Map<String, Object?> memberJson({
  String id = 'u1',
  String fullName = 'Ada Lovelace',
  String accessLevel = 'member',
}) => {
  'id': id,
  'email': 'ada@astra.example.com',
  'full_name': fullName,
  'job_title': 'Développeuse',
  'photo_url': null,
  'access_level': accessLevel,
  'skills': ['Flutter', 'FastAPI'],
  'availability': 70,
  'is_active': true,
  'created_at': '2026-09-01T10:00:00Z',
};

Map<String, Object?> projectJson({String id = 'p1', String status = 'active'}) => {
  'id': id,
  'name': 'MarketCM V2',
  'description': null,
  'objective': 'Nouvelle version',
  'status': status,
  'priority': 'high',
  'due_date': '2026-12-31',
  'budget': '1500.50',
  'created_by_id': 'u1',
  'created_at': '2026-09-01T10:00:00Z',
  'updated_at': '2026-09-02T10:00:00Z',
};

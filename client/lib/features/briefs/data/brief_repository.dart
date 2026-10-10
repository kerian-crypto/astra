import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_client/core/network/api_client.dart';
import 'package:astra_client/core/network/api_exception.dart';
import 'package:astra_client/core/utils/json.dart';
import 'package:astra_client/core/utils/picked_file.dart';
import 'package:astra_client/features/briefs/data/brief.dart';

final briefRepositoryProvider = Provider<BriefRepository>(
  (ref) => BriefRepository(ref.watch(apiProvider)),
);

class BriefRepository {
  BriefRepository(this._api);

  final Api _api;

  Future<Questionnaire> questionnaire() => _api.get(
    '/client/briefs/questionnaire',
    parse: (data) => Questionnaire.fromJson(data! as Json),
  );

  Future<List<Brief>> list() =>
      _api.get('/client/briefs', parse: (data) => listOf(data, Brief.fromJson));

  Future<Brief> get(String id) =>
      _api.get('/client/briefs/$id', parse: (data) => Brief.fromJson(data! as Json));

  /// Nouveau cahier des charges, ou reprise du brouillon en cours.
  Future<Brief> start() =>
      _api.post('/client/briefs', parse: (data) => Brief.fromJson(data! as Json));

  Future<Brief> save(String id, {required Map<String, Object?> answers, String? section}) =>
      _api.patch(
        '/client/briefs/$id',
        data: {'answers': answers, 'current_section': ?section},
        parse: (data) => Brief.fromJson(data! as Json),
      );

  Future<Brief> addFile(String id, String questionId, PickedFile file) async {
    final form = FormData.fromMap({'question_id': questionId, 'file': await file.toMultipart()});
    return _api.post(
      '/client/briefs/$id/files',
      data: form,
      parse: (data) => Brief.fromJson(data! as Json),
    );
  }

  Future<Brief> removeFile(String id, String fileId) => guardApi(() async {
    final response = await _api.dio.delete<Json>('/client/briefs/$id/files/$fileId');
    return Brief.fromJson(response.data!);
  });

  Future<Brief> submit(String id) =>
      _api.post('/client/briefs/$id/submit', parse: (data) => Brief.fromJson(data! as Json));
}

final questionnaireProvider = FutureProvider<Questionnaire>(
  (ref) => ref.watch(briefRepositoryProvider).questionnaire(),
);

final briefsProvider = FutureProvider.autoDispose<List<Brief>>(
  (ref) => ref.watch(briefRepositoryProvider).list(),
);

final briefProvider = FutureProvider.autoDispose.family<Brief, String>(
  (ref, id) => ref.watch(briefRepositoryProvider).get(id),
);

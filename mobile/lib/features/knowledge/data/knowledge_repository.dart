import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:astra_hub/core/network/api_client.dart';
import 'package:astra_hub/core/network/api_exception.dart';
import 'package:astra_hub/core/utils/json.dart';
import 'package:astra_hub/features/knowledge/data/knowledge.dart';

final knowledgeRepositoryProvider = Provider<KnowledgeRepository>(
  (ref) => KnowledgeRepository(ref.watch(dioProvider)),
);

class KnowledgeRepository {
  KnowledgeRepository(this._dio);

  final Dio _dio;

  Future<List<AstraDocument>> documents({String? projectId}) => guardApi(() async {
    final path = projectId == null ? '/documents' : '/projects/$projectId/documents';
    final response = await _dio.get<List<dynamic>>(path);
    return listOf(response.data, AstraDocument.fromJson);
  });

  Future<AstraDocument> upload({
    required String? projectId,
    required String title,
    required DocumentKind kind,
    required String filePath,
    required String filename,
  }) => guardApi(() async {
    final path = projectId == null ? '/documents' : '/projects/$projectId/documents';
    final form = FormData.fromMap({
      'title': title.trim(),
      'kind': kind.name,
      'file': await MultipartFile.fromFile(filePath, filename: filename),
    });
    final response = await _dio.post<Json>(path, data: form);
    return AstraDocument.fromJson(response.data!);
  });

  /// Télécharge dans le cache de l'application (fichier privé) et renvoie son chemin.
  Future<String> download(AstraDocument document) => guardApi(() async {
    final directory = await getTemporaryDirectory();
    final target = File('${directory.path}/${document.id}-${document.filename}');
    if (!await target.exists()) {
      await _dio.download('/documents/${document.id}/download', target.path);
    }
    return target.path;
  });

  Future<void> delete(String id) => guardApi(() => _dio.delete<void>('/documents/$id'));

  Future<List<SearchHit>> search(String query) => guardApi(() async {
    final response = await _dio.get<List<dynamic>>('/search', queryParameters: {'q': query});
    return listOf(response.data, SearchHit.fromJson);
  });

  Future<AstraHealth> health() => guardApi(() async {
    final response = await _dio.get<Json>(
      '/insights/health',
      queryParameters: {'today': isoDate(DateTime.now())},
    );
    return AstraHealth.fromJson(response.data!);
  });
}

final documentsProvider = FutureProvider.autoDispose.family<List<AstraDocument>, String?>(
  (ref, projectId) => ref.watch(knowledgeRepositoryProvider).documents(projectId: projectId),
);

final healthProvider = FutureProvider.autoDispose<AstraHealth>(
  (ref) => ref.watch(knowledgeRepositoryProvider).health(),
);

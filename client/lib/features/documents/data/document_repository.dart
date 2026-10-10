import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_client/core/network/api_client.dart';
import 'package:astra_client/core/utils/json.dart';
import 'package:astra_client/features/documents/data/document.dart';

final documentRepositoryProvider = Provider<DocumentRepository>(
  (ref) => DocumentRepository(ref.watch(apiProvider)),
);

class DocumentRepository {
  DocumentRepository(this._api);

  final Api _api;

  Future<List<ClientDocument>> list({DocumentCategory? category, String? projectId}) => _api.get(
    '/client/documents',
    query: {'category': ?category?.value, 'project_id': ?projectId},
    parse: (data) => listOf(data, ClientDocument.fromJson),
  );

  Future<List<ClientDocument>> versions(String documentId) => _api.get(
    '/client/documents/$documentId/versions',
    parse: (data) => listOf(data, ClientDocument.fromJson),
  );
}

final documentsProvider = FutureProvider.autoDispose
    .family<List<ClientDocument>, ({DocumentCategory? category, String? projectId})>(
      (ref, filter) => ref
          .watch(documentRepositoryProvider)
          .list(category: filter.category, projectId: filter.projectId),
    );

final documentVersionsProvider = FutureProvider.autoDispose.family<List<ClientDocument>, String>(
  (ref, id) => ref.watch(documentRepositoryProvider).versions(id),
);

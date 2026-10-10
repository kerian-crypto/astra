import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_client/core/network/api_client.dart';
import 'package:astra_client/core/utils/json.dart';
import 'package:astra_client/core/utils/picked_file.dart';
import 'package:astra_client/features/deliverables/data/deliverable.dart';

final deliverableRepositoryProvider = Provider<DeliverableRepository>(
  (ref) => DeliverableRepository(ref.watch(apiProvider)),
);

class DeliverableRepository {
  DeliverableRepository(this._api);

  final Api _api;

  Future<List<Deliverable>> list({String? projectId, bool pendingOnly = false}) => _api.get(
    '/client/deliverables',
    query: {'project_id': ?projectId, if (pendingOnly) 'pending_only': true},
    parse: (data) => listOf(data, Deliverable.fromJson),
  );

  Future<DeliverableDetail> get(String id) => _api.get(
    '/client/deliverables/$id',
    parse: (data) => DeliverableDetail.fromJson(data! as Json),
  );

  /// Approbation ou demande de modification (connexion obligatoire).
  Future<DeliverableDetail> review(
    String id, {
    required ReviewAction action,
    String? reason,
    String? comment,
    PickedFile? attachment,
  }) async {
    final form = FormData.fromMap({
      'action': action.value,
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      if (comment != null && comment.trim().isNotEmpty) 'comment': comment.trim(),
      if (attachment != null) 'file': await attachment.toMultipart(),
    });
    return _api.post(
      '/client/deliverables/$id/reviews',
      data: form,
      parse: (data) => DeliverableDetail.fromJson(data! as Json),
    );
  }
}

final deliverablesProvider = FutureProvider.autoDispose
    .family<List<Deliverable>, ({String? projectId, bool pendingOnly})>(
      (ref, filter) => ref
          .watch(deliverableRepositoryProvider)
          .list(projectId: filter.projectId, pendingOnly: filter.pendingOnly),
    );

final deliverableProvider = FutureProvider.autoDispose.family<DeliverableDetail, String>(
  (ref, id) => ref.watch(deliverableRepositoryProvider).get(id),
);

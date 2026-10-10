import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_client/core/network/api_client.dart';
import 'package:astra_client/core/utils/json.dart';
import 'package:astra_client/features/projects/data/project.dart';

final projectRepositoryProvider = Provider<ProjectRepository>(
  (ref) => ProjectRepository(ref.watch(apiProvider)),
);

class ProjectRepository {
  ProjectRepository(this._api);

  final Api _api;

  Future<List<ProjectSummary>> list() =>
      _api.get('/client/projects', parse: (data) => listOf(data, ProjectSummary.fromJson));

  Future<ProjectDetail> get(String id) =>
      _api.get('/client/projects/$id', parse: (data) => ProjectDetail.fromJson(data! as Json));

  Future<List<TimelineEvent>> timeline(String id) => _api.get(
    '/client/projects/$id/timeline',
    parse: (data) => listOf(data, TimelineEvent.fromJson),
  );

  /// Conversation du projet (créée à la première ouverture). Renvoie son id.
  Future<String> openConversation(String id) => _api.post(
    '/client/projects/$id/conversation',
    parse: (data) => (data! as Json)['id'] as String,
  );
}

final projectsProvider = FutureProvider.autoDispose<List<ProjectSummary>>(
  (ref) => ref.watch(projectRepositoryProvider).list(),
);

final projectProvider = FutureProvider.autoDispose.family<ProjectDetail, String>(
  (ref, id) => ref.watch(projectRepositoryProvider).get(id),
);

final projectTimelineProvider = FutureProvider.autoDispose.family<List<TimelineEvent>, String>(
  (ref, id) => ref.watch(projectRepositoryProvider).timeline(id),
);

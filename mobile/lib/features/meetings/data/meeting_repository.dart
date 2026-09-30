import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_hub/core/network/api_client.dart';
import 'package:astra_hub/core/network/api_exception.dart';
import 'package:astra_hub/core/utils/json.dart';
import 'package:astra_hub/features/meetings/data/meeting.dart';
import 'package:astra_hub/features/projects/data/project.dart';

final meetingRepositoryProvider = Provider<MeetingRepository>(
  (ref) => MeetingRepository(ref.watch(dioProvider)),
);

class MeetingRepository {
  MeetingRepository(this._dio);

  final Dio _dio;

  Future<Json> _send(String method, String path, [Object? data]) => guardApi(() async {
    final response = await _dio.request<Json>(
      path,
      data: data,
      options: Options(method: method),
    );
    return response.data ?? const {};
  });

  Future<List<Meeting>> list({DateTime? start, DateTime? end}) => guardApi(() async {
    final response = await _dio.get<List<dynamic>>(
      '/meetings',
      queryParameters: {
        if (start != null) 'start': start.toUtc().toIso8601String(),
        if (end != null) 'end': end.toUtc().toIso8601String(),
      },
    );
    return listOf(response.data, Meeting.fromJson);
  });

  Future<MeetingDetail> get(String id) async =>
      MeetingDetail.fromJson(await _send('GET', '/meetings/$id'));

  Future<MeetingDetail> create({
    required String title,
    required DateTime scheduledAt,
    required List<String> participantIds,
    String? projectId,
    String? agenda,
  }) async => MeetingDetail.fromJson(
    await _send('POST', '/meetings', {
      'title': title.trim(),
      'scheduled_at': scheduledAt.toUtc().toIso8601String(),
      'participant_ids': participantIds,
      'project_id': ?projectId,
      if (agenda != null && agenda.trim().isNotEmpty) 'agenda': agenda.trim(),
    }),
  );

  Future<MeetingDetail> update(String id, Json fields) async =>
      MeetingDetail.fromJson(await _send('PATCH', '/meetings/$id', fields));

  Future<Decision> addDecision(String meetingId, String title, {String? description}) async =>
      Decision.fromJson(
        await _send('POST', '/meetings/$meetingId/decisions', {
          'title': title.trim(),
          if (description != null && description.isNotEmpty) 'description': description,
        }),
      );

  Future<void> createTasks(String meetingId, List<Json> tasks) =>
      _send('POST', '/meetings/$meetingId/tasks', tasks);

  Future<Decision> review(String decisionId, DecisionStatus status) async => Decision.fromJson(
    await _send('POST', '/decisions/$decisionId/review', {'status': status.name}),
  );

  /// Décision validée → projet opérationnel avec ses phases (spec §9).
  Future<ProjectDetail> decisionToProject(
    String decisionId, {
    required String name,
    required List<String> phases,
  }) async => ProjectDetail.fromJson(
    await _send('POST', '/decisions/$decisionId/project', {
      'name': name.trim(),
      'phases': [
        for (final phase in phases)
          if (phase.trim().isNotEmpty) {'name': phase.trim()},
      ],
    }),
  );
}

final meetingsProvider = FutureProvider.autoDispose<List<Meeting>>((ref) {
  // Réunions des 30 derniers jours et à venir.
  final start = DateTime.now().subtract(const Duration(days: 30));
  return ref.watch(meetingRepositoryProvider).list(start: start);
});

final meetingDetailProvider = FutureProvider.autoDispose.family<MeetingDetail, String>(
  (ref, id) => ref.watch(meetingRepositoryProvider).get(id),
);

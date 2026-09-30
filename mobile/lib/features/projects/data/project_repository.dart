import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_hub/core/network/api_client.dart';
import 'package:astra_hub/core/network/api_exception.dart';
import 'package:astra_hub/features/projects/data/project.dart';

final projectRepositoryProvider = Provider<ProjectRepository>(
  (ref) => ProjectRepository(ref.watch(dioProvider)),
);

class ProjectRepository {
  ProjectRepository(this._dio);

  final Dio _dio;

  Future<List<Project>> list({ProjectStatus? status}) {
    return guardApi(() async {
      final response = await _dio.get<List<dynamic>>(
        '/projects',
        queryParameters: {if (status != null) 'status': status.name},
      );
      return List.unmodifiable(
        response.data!.map((p) => Project.fromJson(p as Map<String, dynamic>)),
      );
    });
  }

  Future<ProjectDetail> get(String id) {
    return guardApi(() async {
      final response = await _dio.get<Map<String, dynamic>>('/projects/$id');
      return ProjectDetail.fromJson(response.data!);
    });
  }

  Future<ProjectDetail> create({
    required String name,
    String? objective,
    Priority priority = Priority.medium,
  }) {
    return guardApi(() async {
      final response = await _dio.post<Map<String, dynamic>>(
        '/projects',
        data: {
          'name': name.trim(),
          if (objective != null && objective.trim().isNotEmpty) 'objective': objective.trim(),
          'priority': priority.name,
        },
      );
      return ProjectDetail.fromJson(response.data!);
    });
  }
}

final projectListProvider = FutureProvider.autoDispose<List<Project>>(
  (ref) => ref.watch(projectRepositoryProvider).list(),
);

final projectDetailProvider = FutureProvider.autoDispose.family<ProjectDetail, String>(
  (ref, id) => ref.watch(projectRepositoryProvider).get(id),
);

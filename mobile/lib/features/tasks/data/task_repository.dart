import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_hub/core/network/api_client.dart';
import 'package:astra_hub/core/network/api_exception.dart';
import 'package:astra_hub/core/utils/json.dart';
import 'package:astra_hub/features/knowledge/data/knowledge.dart';
import 'package:astra_hub/features/tasks/data/task.dart';

final taskRepositoryProvider = Provider<TaskRepository>(
  (ref) => TaskRepository(ref.watch(dioProvider)),
);

class TaskRepository {
  TaskRepository(this._dio);

  final Dio _dio;

  Future<List<T>> _list<T>(String path, T Function(Json) parse) => guardApi(() async {
    final response = await _dio.get<List<dynamic>>(path);
    return listOf(response.data, parse);
  });

  Future<Json> _send(String method, String path, [Object? data]) => guardApi(() async {
    final response = await _dio.request<Json>(
      path,
      data: data,
      options: Options(method: method),
    );
    return response.data ?? const {};
  });

  Future<List<Task>> projectTasks(String projectId) =>
      _list('/projects/$projectId/tasks', Task.fromJson);

  Future<List<Phase>> phases(String projectId) =>
      _list('/projects/$projectId/phases', Phase.fromJson);

  Future<Phase> createPhase(String projectId, String name) async =>
      Phase.fromJson(await _send('POST', '/projects/$projectId/phases', {'name': name.trim()}));

  Future<List<Activity>> projectActivity(String projectId) =>
      _list('/projects/$projectId/activity', Activity.fromJson);

  Future<TaskDetail> task(String id) async => TaskDetail.fromJson(await _send('GET', '/tasks/$id'));

  Future<TaskDetail> create(String projectId, Json fields) async =>
      TaskDetail.fromJson(await _send('POST', '/projects/$projectId/tasks', fields));

  /// `fields` ne contient que les champs modifiés (PATCH partiel).
  Future<TaskDetail> update(String id, Json fields) async =>
      TaskDetail.fromJson(await _send('PATCH', '/tasks/$id', fields));

  Future<void> delete(String id) => _send('DELETE', '/tasks/$id');

  Future<void> addChecklistItem(String taskId, String label) =>
      _send('POST', '/tasks/$taskId/checklist', {'label': label.trim()});

  Future<void> setChecklistItem(String taskId, String itemId, {required bool isDone}) =>
      _send('PATCH', '/tasks/$taskId/checklist/$itemId', {'is_done': isDone});

  Future<List<Comment>> comments(String taskId) =>
      _list('/tasks/$taskId/comments', Comment.fromJson);

  Future<void> addComment(String taskId, String body) =>
      _send('POST', '/tasks/$taskId/comments', {'body': body.trim()});

  Future<List<Activity>> history(String taskId) =>
      _list('/tasks/$taskId/history', Activity.fromJson);

  Future<List<AssignmentSuggestion>> suggestions(String taskId) =>
      _list('/tasks/$taskId/assignment-suggestions', AssignmentSuggestion.fromJson);
}

final projectTasksProvider = FutureProvider.autoDispose.family<List<Task>, String>(
  (ref, projectId) => ref.watch(taskRepositoryProvider).projectTasks(projectId),
);

final projectPhasesProvider = FutureProvider.autoDispose.family<List<Phase>, String>(
  (ref, projectId) => ref.watch(taskRepositoryProvider).phases(projectId),
);

final projectActivityProvider = FutureProvider.autoDispose.family<List<Activity>, String>(
  (ref, projectId) => ref.watch(taskRepositoryProvider).projectActivity(projectId),
);

final taskDetailProvider = FutureProvider.autoDispose.family<TaskDetail, String>(
  (ref, id) => ref.watch(taskRepositoryProvider).task(id),
);

final taskCommentsProvider = FutureProvider.autoDispose.family<List<Comment>, String>(
  (ref, id) => ref.watch(taskRepositoryProvider).comments(id),
);

final taskHistoryProvider = FutureProvider.autoDispose.family<List<Activity>, String>(
  (ref, id) => ref.watch(taskRepositoryProvider).history(id),
);

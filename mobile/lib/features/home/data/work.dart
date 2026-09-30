import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_hub/core/network/api_client.dart';
import 'package:astra_hub/core/network/api_exception.dart';
import 'package:astra_hub/core/utils/json.dart';
import 'package:astra_hub/features/meetings/data/meeting.dart';
import 'package:astra_hub/features/tasks/data/task.dart';

/// Espace « MON TRAVAIL » (spec §8).
class MyWork {
  const MyWork({
    required this.today,
    required this.overdue,
    required this.priority,
    required this.upcoming,
    required this.meetings,
  });

  factory MyWork.fromJson(Json json) => MyWork(
    today: listOf(json['today'], Task.fromJson),
    overdue: listOf(json['overdue'], Task.fromJson),
    priority: listOf(json['priority'], Task.fromJson),
    upcoming: listOf(json['upcoming'], Task.fromJson),
    meetings: listOf(json['meetings'], Meeting.fromJson),
  );

  final List<Task> today;
  final List<Task> overdue;
  final List<Task> priority;
  final List<Task> upcoming;
  final List<Meeting> meetings;
}

class AttentionProject {
  const AttentionProject({required this.id, required this.name, required this.reason});

  factory AttentionProject.fromJson(Json json) => AttentionProject(
    id: json['id'] as String,
    name: json['name'] as String,
    reason: json['reason'] as String,
  );

  final String id;
  final String name;
  final String reason;
}

/// Tableau de bord (spec §19).
class Dashboard {
  const Dashboard({
    required this.myOpenTasks,
    required this.myTodayTasks,
    required this.myOverdueTasks,
    required this.myMeetingsToday,
    required this.unreadNotifications,
    required this.activeProjects,
    required this.openTasks,
    required this.overdueTasks,
    required this.projectsNeedingAttention,
  });

  factory Dashboard.fromJson(Json json) {
    final me = json['me'] as Json;
    final astra = json['astra'] as Json;
    return Dashboard(
      myOpenTasks: me['open_tasks'] as int,
      myTodayTasks: me['today_tasks'] as int,
      myOverdueTasks: me['overdue_tasks'] as int,
      myMeetingsToday: me['upcoming_meetings'] as int,
      unreadNotifications: me['unread_notifications'] as int,
      activeProjects: astra['active_projects'] as int,
      openTasks: astra['open_tasks'] as int,
      overdueTasks: astra['overdue_tasks'] as int,
      projectsNeedingAttention: listOf(
        astra['projects_needing_attention'],
        AttentionProject.fromJson,
      ),
    );
  }

  final int myOpenTasks;
  final int myTodayTasks;
  final int myOverdueTasks;
  final int myMeetingsToday;
  final int unreadNotifications;
  final int activeProjects;
  final int openTasks;
  final int overdueTasks;
  final List<AttentionProject> projectsNeedingAttention;
}

final workRepositoryProvider = Provider<WorkRepository>(
  (ref) => WorkRepository(ref.watch(dioProvider)),
);

class WorkRepository {
  WorkRepository(this._dio);

  final Dio _dio;

  /// La date locale du téléphone est envoyée : « aujourd'hui » suit le fuseau
  /// du membre, pas celui du serveur.
  Map<String, String> get _today => {'today': isoDate(DateTime.now())};

  Future<MyWork> myWork() => guardApi(() async {
    final response = await _dio.get<Json>('/me/work', queryParameters: _today);
    return MyWork.fromJson(response.data!);
  });

  Future<Dashboard> dashboard() => guardApi(() async {
    final response = await _dio.get<Json>('/dashboard', queryParameters: _today);
    return Dashboard.fromJson(response.data!);
  });
}

final myWorkProvider = FutureProvider.autoDispose<MyWork>(
  (ref) => ref.watch(workRepositoryProvider).myWork(),
);

final dashboardProvider = FutureProvider.autoDispose<Dashboard>(
  (ref) => ref.watch(workRepositoryProvider).dashboard(),
);

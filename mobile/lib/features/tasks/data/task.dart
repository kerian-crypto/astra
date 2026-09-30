import 'package:astra_hub/core/utils/json.dart';
import 'package:astra_hub/features/members/data/member.dart';
import 'package:astra_hub/features/projects/data/project.dart';

enum TaskStatus {
  todo('À faire'),
  inProgress('En cours'),
  review('Review'),
  done('Terminé');

  const TaskStatus(this.label);

  final String label;

  String get apiName => this == inProgress ? 'in_progress' : name;

  static TaskStatus fromJson(Object? value) =>
      values.firstWhere((s) => s.apiName == value, orElse: () => todo);
}

class Phase {
  const Phase({required this.id, required this.name, required this.position, this.dueDate});

  factory Phase.fromJson(Json json) => Phase(
    id: json['id'] as String,
    name: json['name'] as String,
    position: json['position'] as int,
    dueDate: dateOrNull(json['due_date']),
  );

  final String id;
  final String name;
  final int position;
  final DateTime? dueDate;
}

class Task {
  const Task({
    required this.id,
    required this.projectId,
    required this.title,
    required this.status,
    required this.priority,
    this.phaseId,
    this.assignee,
    this.dueDate,
  });

  factory Task.fromJson(Json json) => Task(
    id: json['id'] as String,
    projectId: json['project_id'] as String,
    phaseId: json['phase_id'] as String?,
    title: json['title'] as String,
    status: TaskStatus.fromJson(json['status']),
    priority: enumFromJson(Priority.values, json['priority'], Priority.medium),
    assignee: json['assignee'] == null ? null : Member.fromJson(json['assignee'] as Json),
    dueDate: dateOrNull(json['due_date']),
  );

  final String id;
  final String projectId;
  final String? phaseId;
  final String title;
  final TaskStatus status;
  final Priority priority;
  final Member? assignee;
  final DateTime? dueDate;

  bool isOverdue(DateTime today) =>
      status != TaskStatus.done &&
      dueDate != null &&
      dueDate!.isBefore(DateTime(today.year, today.month, today.day));
}

class ChecklistItem {
  const ChecklistItem({required this.id, required this.label, required this.isDone});

  factory ChecklistItem.fromJson(Json json) => ChecklistItem(
    id: json['id'] as String,
    label: json['label'] as String,
    isDone: json['is_done'] as bool,
  );

  final String id;
  final String label;
  final bool isDone;
}

class TaskRef {
  const TaskRef({required this.id, required this.title, required this.status});

  factory TaskRef.fromJson(Json json) => TaskRef(
    id: json['id'] as String,
    title: json['title'] as String,
    status: TaskStatus.fromJson(json['status']),
  );

  final String id;
  final String title;
  final TaskStatus status;
}

class TaskDetail {
  const TaskDetail({
    required this.task,
    required this.checklist,
    required this.dependencies,
    required this.dependents,
    this.description,
  });

  factory TaskDetail.fromJson(Json json) => TaskDetail(
    task: Task.fromJson(json),
    description: json['description'] as String?,
    checklist: listOf(json['checklist'], ChecklistItem.fromJson),
    dependencies: listOf(json['dependencies'], TaskRef.fromJson),
    dependents: listOf(json['dependents'], TaskRef.fromJson),
  );

  final Task task;
  final String? description;
  final List<ChecklistItem> checklist;
  final List<TaskRef> dependencies;
  final List<TaskRef> dependents;
}

class Comment {
  const Comment({
    required this.id,
    required this.author,
    required this.body,
    required this.createdAt,
  });

  factory Comment.fromJson(Json json) => Comment(
    id: json['id'] as String,
    author: Member.fromJson(json['author'] as Json),
    body: json['body'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  final String id;
  final Member author;
  final String body;
  final DateTime createdAt;
}

class Activity {
  const Activity({
    required this.action,
    required this.entityType,
    required this.changes,
    required this.createdAt,
    this.actor,
  });

  factory Activity.fromJson(Json json) => Activity(
    action: json['action'] as String,
    entityType: json['entity_type'] as String,
    changes: Map.unmodifiable(json['changes'] as Json),
    createdAt: DateTime.parse(json['created_at'] as String),
    actor: json['actor'] == null ? null : Member.fromJson(json['actor'] as Json),
  );

  final String action;
  final String entityType;
  final Map<String, dynamic> changes;
  final DateTime createdAt;
  final Member? actor;

  static const _actions = {
    'created': 'a créé',
    'updated': 'a modifié',
    'status_changed': 'a changé le statut de',
    'deleted': 'a supprimé',
    'commented': 'a commenté',
    'dependencies_changed': 'a changé les dépendances de',
    'member_set': 'a défini un membre de',
    'member_removed': 'a retiré un membre de',
    'uploaded': 'a déposé',
    'reviewed': 'a statué sur',
    'project_created': 'a créé un projet depuis',
  };

  static const _entities = {
    'task': 'la tâche',
    'project': 'le projet',
    'phase': 'la phase',
    'meeting': 'la réunion',
    'decision': 'la décision',
    'document': 'le document',
  };

  String describe() {
    final who = actor?.fullName ?? 'Quelqu\'un';
    final what = _actions[action] ?? action;
    final entity = _entities[entityType] ?? entityType;
    final status = changes['status'];
    if (action == 'status_changed' && status is Map) {
      final to = TaskStatus.fromJson(status['to']).label;
      return '$who $what $entity → $to';
    }
    return '$who $what $entity';
  }
}

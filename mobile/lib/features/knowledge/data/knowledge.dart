import 'package:astra_hub/core/utils/json.dart';
import 'package:astra_hub/features/members/data/member.dart';
import 'package:astra_hub/features/tasks/data/task.dart';

enum DocumentKind {
  specification('Cahier des charges'),
  design('Design'),
  technical('Technique'),
  contract('Contrat'),
  minutes('Compte rendu'),
  guide('Guide'),
  deliverable('Livrable'),
  lessons('Retour d\'expérience'),
  other('Autre');

  const DocumentKind(this.label);

  final String label;
}

class AstraDocument {
  const AstraDocument({
    required this.id,
    required this.title,
    required this.kind,
    required this.filename,
    required this.sizeBytes,
    required this.createdAt,
    required this.isIndexed,
    this.projectId,
    this.uploadedBy,
  });

  factory AstraDocument.fromJson(Json json) => AstraDocument(
    id: json['id'] as String,
    projectId: json['project_id'] as String?,
    title: json['title'] as String,
    kind: enumFromJson(DocumentKind.values, json['kind'], DocumentKind.other),
    filename: json['filename'] as String,
    sizeBytes: json['size_bytes'] as int,
    uploadedBy: json['uploaded_by'] == null ? null : Member.fromJson(json['uploaded_by'] as Json),
    createdAt: DateTime.parse(json['created_at'] as String),
    isIndexed: json['is_indexed'] as bool,
  );

  final String id;
  final String? projectId;
  final String title;
  final DocumentKind kind;
  final String filename;
  final int sizeBytes;
  final Member? uploadedBy;
  final DateTime createdAt;
  final bool isIndexed;

  String get readableSize {
    if (sizeBytes < 1024) return '$sizeBytes o';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(0)} Ko';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
  }
}

enum SearchType {
  project('Projet'),
  task('Tâche'),
  decision('Décision'),
  meeting('Réunion'),
  document('Document'),
  message('Message');

  const SearchType(this.label);

  final String label;
}

class SearchHit {
  const SearchHit({
    required this.type,
    required this.id,
    required this.title,
    required this.snippet,
    this.projectId,
    this.parentId,
  });

  factory SearchHit.fromJson(Json json) => SearchHit(
    type: enumFromJson(SearchType.values, json['type'], SearchType.task),
    id: json['id'] as String,
    title: json['title'] as String,
    snippet: json['snippet'] as String,
    projectId: json['project_id'] as String?,
    parentId: json['parent_id'] as String?,
  );

  final SearchType type;
  final String id;
  final String title;
  final String snippet;
  final String? projectId;
  final String? parentId;
}

// ---------- État de santé ----------

class MemberLoad {
  const MemberLoad({
    required this.member,
    required this.openTasks,
    required this.overdueTasks,
    required this.capacity,
    required this.isOverloaded,
  });

  factory MemberLoad.fromJson(Json json) => MemberLoad(
    member: Member.fromJson(json['member'] as Json),
    openTasks: json['open_tasks'] as int,
    overdueTasks: json['overdue_tasks'] as int,
    capacity: json['capacity'] as int,
    isOverloaded: json['is_overloaded'] as bool,
  );

  final Member member;
  final int openTasks;
  final int overdueTasks;
  final int capacity;
  final bool isOverloaded;
}

class HealthItem {
  const HealthItem({required this.title, required this.subtitle, this.taskId, this.projectId});

  final String title;
  final String subtitle;
  final String? taskId;
  final String? projectId;
}

class AstraHealth {
  const AstraHealth({required this.sections});

  /// Sections affichables : titre → éléments.
  factory AstraHealth.fromJson(Json json) {
    List<HealthItem> tasks(String key, String subtitle) => [
      for (final t in listOf(json[key], Task.fromJson))
        HealthItem(title: t.title, subtitle: subtitle, taskId: t.id, projectId: t.projectId),
    ];
    return AstraHealth(
      sections: {
        'Projets à risque': [
          for (final p in (json['projects_at_risk'] as List<dynamic>).cast<Json>())
            HealthItem(
              title: p['name'] as String,
              subtitle: p['reason'] as String,
              projectId: p['id'] as String,
            ),
        ],
        'Tâches en retard': tasks('overdue_tasks', 'Échéance dépassée'),
        'Tâches bloquées': tasks('blocked_tasks', 'Un prérequis n\'est pas terminé'),
        'Dépendances critiques': [
          for (final c in (json['critical_dependencies'] as List<dynamic>).cast<Json>())
            HealthItem(
              title: (c['task'] as Json)['title'] as String,
              subtitle: '${c['waiting_tasks']} tâches attendent celle-ci',
              taskId: (c['task'] as Json)['id'] as String,
              projectId: (c['task'] as Json)['project_id'] as String,
            ),
        ],
        'Membres surchargés': [
          for (final m in listOf(json['overloaded_members'], MemberLoad.fromJson))
            HealthItem(
              title: m.member.fullName,
              subtitle: '${m.openTasks} tâches ouvertes pour une capacité de ${m.capacity}',
            ),
        ],
        'Décisions non exécutées': [
          for (final d in (json['unexecuted_decisions'] as List<dynamic>).cast<Json>())
            HealthItem(
              title: d['title'] as String,
              subtitle: 'Validée le ${d['validated_on']}',
              projectId: d['project_id'] as String?,
            ),
        ],
        'Informations manquantes': [
          for (final i in (json['missing_information'] as List<dynamic>).cast<Json>())
            HealthItem(
              title: i['project_name'] as String,
              subtitle: i['issue'] as String,
              projectId: i['project_id'] as String,
            ),
        ],
      },
    );
  }

  final Map<String, List<HealthItem>> sections;

  bool get isHealthy => sections.values.every((items) => items.isEmpty);
}

class AssignmentSuggestion {
  const AssignmentSuggestion({required this.member, required this.reasons});

  factory AssignmentSuggestion.fromJson(Json json) => AssignmentSuggestion(
    member: Member.fromJson(json['member'] as Json),
    reasons: stringsOf(json['reasons']),
  );

  final Member member;
  final List<String> reasons;
}

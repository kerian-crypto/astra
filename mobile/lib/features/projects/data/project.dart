import 'package:astra_hub/core/utils/json.dart';
import 'package:astra_hub/features/members/data/member.dart';

enum ProjectStatus {
  idea('Idée'),
  planning('Planification'),
  active('Actif'),
  review('Review'),
  done('Terminé'),
  archived('Archivé');

  const ProjectStatus(this.label);

  final String label;
}

enum Priority {
  low('Basse'),
  medium('Moyenne'),
  high('Haute'),
  critical('Critique');

  const Priority(this.label);

  final String label;
}

enum ProjectRole {
  viewer('Lecteur'),
  contributor('Contributeur'),
  lead('Responsable');

  const ProjectRole(this.label);

  final String label;
}

class Project {
  const Project({
    required this.id,
    required this.name,
    required this.status,
    required this.priority,
    required this.updatedAt,
    this.description,
    this.objective,
    this.dueDate,
    this.budget,
  });

  factory Project.fromJson(Json json) => Project(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String?,
    objective: json['objective'] as String?,
    status: enumFromJson(ProjectStatus.values, json['status'], ProjectStatus.idea),
    priority: enumFromJson(Priority.values, json['priority'], Priority.medium),
    dueDate: dateOrNull(json['due_date']),
    // Le backend sérialise les Decimal en chaîne pour ne pas perdre de précision.
    budget: json['budget'] as String?,
    updatedAt: DateTime.parse(json['updated_at'] as String),
  );

  final String id;
  final String name;
  final String? description;
  final String? objective;
  final ProjectStatus status;
  final Priority priority;
  final DateTime? dueDate;
  final String? budget;
  final DateTime updatedAt;
}

class ProjectMember {
  const ProjectMember({required this.member, required this.role});

  factory ProjectMember.fromJson(Json json) => ProjectMember(
    member: Member.fromJson(json['user'] as Json),
    role: enumFromJson(ProjectRole.values, json['role'], ProjectRole.viewer),
  );

  final Member member;
  final ProjectRole role;
}

class ProjectDetail {
  const ProjectDetail({required this.project, required this.members, required this.myRole});

  factory ProjectDetail.fromJson(Json json) => ProjectDetail(
    project: Project.fromJson(json),
    members: listOf(json['members'], ProjectMember.fromJson),
    myRole: enumFromJson(ProjectRole.values, json['my_role'], ProjectRole.viewer),
  );

  final Project project;
  final List<ProjectMember> members;
  final ProjectRole myRole;

  /// Les droits réels sont vérifiés par le serveur ; ceci sert à masquer
  /// les actions impossibles.
  bool get canContribute => myRole != ProjectRole.viewer;
  bool get isLead => myRole == ProjectRole.lead;

  /// Membres à qui l'on peut attribuer une tâche.
  List<Member> get assignableMembers => [
    for (final m in members)
      if (m.role != ProjectRole.viewer) m.member,
  ];
}

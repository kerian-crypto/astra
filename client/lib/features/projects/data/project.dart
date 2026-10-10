import 'package:astra_client/core/theme/client_theme.dart';
import 'package:astra_client/core/utils/json.dart';

/// Statut d'un projet tel que piloté par Astra Hub (§16).
enum ProjectStatus {
  planning('Planification', Tone.neutral),
  inProgress('En cours', Tone.brand),
  waitingClient('En attente de votre retour', Tone.warning),
  inValidation('En validation', Tone.info),
  changesRequested('Modification demandée', Tone.warning),
  inCorrection('En correction', Tone.info),
  done('Terminé', Tone.success),
  suspended('Suspendu', Tone.neutral),
  cancelled('Annulé', Tone.danger);

  const ProjectStatus(this.label, this.tone);
  final String label;
  final Tone tone;

  static ProjectStatus parse(Object? value) => switch (value) {
    'planning' => planning,
    'in_progress' => inProgress,
    'waiting_client' => waitingClient,
    'in_validation' => inValidation,
    'changes_requested' => changesRequested,
    'in_correction' => inCorrection,
    'done' => done,
    'suspended' => suspended,
    'cancelled' => cancelled,
    _ => inProgress,
  };

  bool get isFinished => this == done || this == cancelled;
}

class ProjectSummary {
  const ProjectSummary({
    required this.id,
    required this.name,
    required this.status,
    required this.progress,
    required this.updatedAt,
    this.dueDate,
    this.pendingValidations = 0,
  });

  factory ProjectSummary.fromJson(Json json) => ProjectSummary(
    id: json['id'] as String,
    name: json['name'] as String,
    status: ProjectStatus.parse(json['status']),
    progress: json['progress'] as int? ?? 0,
    dueDate: dateOrNull(json['due_date']),
    updatedAt: DateTime.parse(json['updated_at'] as String),
    pendingValidations: json['pending_validations'] as int? ?? 0,
  );

  final String id;
  final String name;
  final ProjectStatus status;
  final int progress;
  final DateTime? dueDate;
  final DateTime updatedAt;
  final int pendingValidations;
}

class TeamMember {
  const TeamMember({required this.fullName, required this.isLead, this.jobTitle});

  factory TeamMember.fromJson(Json json) => TeamMember(
    fullName: json['full_name'] as String,
    jobTitle: json['job_title'] as String?,
    isLead: json['is_lead'] as bool? ?? false,
  );

  final String fullName;
  final String? jobTitle;
  final bool isLead;
}

class ProjectDetail extends ProjectSummary {
  const ProjectDetail({
    required super.id,
    required super.name,
    required super.status,
    required super.progress,
    required super.updatedAt,
    required this.createdAt,
    required this.team,
    required this.deliverableCount,
    required this.documentCount,
    super.dueDate,
    super.pendingValidations,
    this.description,
    this.summary,
    this.conversationId,
  });

  factory ProjectDetail.fromJson(Json json) {
    final base = ProjectSummary.fromJson(json);
    return ProjectDetail(
      id: base.id,
      name: base.name,
      status: base.status,
      progress: base.progress,
      dueDate: base.dueDate,
      updatedAt: base.updatedAt,
      pendingValidations: base.pendingValidations,
      description: json['description'] as String?,
      summary: json['summary'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      team: listOf(json['team'], TeamMember.fromJson),
      deliverableCount: json['deliverable_count'] as int? ?? 0,
      documentCount: json['document_count'] as int? ?? 0,
      conversationId: json['conversation_id'] as String?,
    );
  }

  final String? description;
  final String? summary;
  final DateTime createdAt;
  final List<TeamMember> team;
  final int deliverableCount;
  final int documentCount;
  final String? conversationId;

  TeamMember? get lead => team.where((m) => m.isLead).firstOrNull;
}

class TimelineEvent {
  const TimelineEvent({
    required this.id,
    required this.kind,
    required this.label,
    required this.entityId,
    required this.createdAt,
    this.actorName,
  });

  factory TimelineEvent.fromJson(Json json) => TimelineEvent(
    id: json['id'] as String,
    kind: json['kind'] as String,
    label: json['label'] as String,
    actorName: json['actor_name'] as String?,
    entityId: json['entity_id'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  final String id;
  final String kind;
  final String label;
  final String? actorName;
  final String entityId;
  final DateTime createdAt;
}

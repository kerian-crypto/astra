import 'package:astra_hub/core/utils/json.dart';

class AiStatus {
  const AiStatus({required this.enabled, required this.reachable});

  factory AiStatus.fromJson(Json json) =>
      AiStatus(enabled: json['enabled'] as bool, reachable: json['reachable'] as bool);

  final bool enabled;
  final bool reachable;

  bool get isAvailable => enabled && reachable;
}

class AiSource {
  const AiSource({required this.number, required this.type, required this.title, this.id});

  factory AiSource.fromJson(Json json) => AiSource(
    number: json['number'] as int,
    type: json['type'] as String,
    id: json['id'] as String?,
    title: json['title'] as String,
  );

  final int number;
  final String type;
  final String? id;
  final String title;
}

class AiAnswer {
  const AiAnswer({required this.answer, required this.sources});

  factory AiAnswer.fromJson(Json json) => AiAnswer(
    answer: json['answer'] as String,
    sources: listOf(json['sources'], AiSource.fromJson),
  );

  final String answer;
  final List<AiSource> sources;
}

/// Proposition de plan : `plan` est renvoyé tel quel à /projects/from-plan
/// après validation humaine.
class PlanProposal {
  const PlanProposal({
    required this.plan,
    required this.deliverables,
    required this.risks,
    required this.requiredSkills,
    required this.estimatedWorkloadDays,
  });

  factory PlanProposal.fromJson(Json json) => PlanProposal(
    plan: Map.unmodifiable(json['plan'] as Json),
    deliverables: stringsOf(json['deliverables']),
    risks: stringsOf(json['risks']),
    requiredSkills: stringsOf(json['required_skills']),
    estimatedWorkloadDays: json['estimated_workload_days'] as int,
  );

  final Map<String, dynamic> plan;
  final List<String> deliverables;
  final List<String> risks;
  final List<String> requiredSkills;
  final int estimatedWorkloadDays;

  String get name => plan['name'] as String;
  String? get objective => plan['objective'] as String?;

  List<({String name, List<String> tasks})> get phases => [
    for (final phase in (plan['phases'] as List<dynamic>).cast<Json>())
      (
        name: phase['name'] as String,
        tasks: [
          for (final task in (phase['tasks'] as List<dynamic>).cast<Json>())
            task['title'] as String,
        ],
      ),
  ];
}

class ProposedTask {
  const ProposedTask({
    required this.title,
    this.description,
    this.assigneeId,
    this.assigneeName,
    this.dueDate,
  });

  factory ProposedTask.fromJson(Json json) => ProposedTask(
    title: json['title'] as String,
    description: json['description'] as String?,
    assigneeId: json['assignee_id'] as String?,
    assigneeName: json['assignee_name'] as String?,
    dueDate: json['due_date'] as String?,
  );

  final String title;
  final String? description;
  final String? assigneeId;
  final String? assigneeName;
  final String? dueDate;

  Json toTaskCreate() => {
    'title': title,
    if (description != null && description!.isNotEmpty) 'description': description,
    'assignee_id': ?assigneeId,
    'due_date': ?dueDate,
  };
}

class MeetingSummary {
  const MeetingSummary({
    required this.summary,
    required this.decisions,
    required this.openQuestions,
    required this.tasks,
    required this.risks,
  });

  factory MeetingSummary.fromJson(Json json) => MeetingSummary(
    summary: json['summary'] as String,
    decisions: [
      for (final d in (json['decisions'] as List<dynamic>).cast<Json>())
        (title: d['title'] as String, description: d['description'] as String),
    ],
    openQuestions: stringsOf(json['open_questions']),
    tasks: listOf(json['tasks'], ProposedTask.fromJson),
    risks: stringsOf(json['risks']),
  );

  final String summary;
  final List<({String title, String description})> decisions;
  final List<String> openQuestions;
  final List<ProposedTask> tasks;
  final List<String> risks;
}

enum AiMessageStatus { pending, done, failed }

/// Écran de l'app que Ronda lit en plus de l'activité générale.
class AiFocus {
  const AiFocus(this.type, this.id);

  /// Déduit l'écran consulté de l'adresse courante (ex. `/projects/42`).
  static AiFocus? fromPath(String path) {
    final segments = Uri.parse(path).pathSegments;
    if (segments.length != 2) return null;
    final type = switch (segments.first) {
      'projects' => 'project',
      'tasks' => 'task',
      'meetings' => 'meeting',
      'messages' => 'channel',
      _ => null,
    };
    return type == null ? null : AiFocus(type, segments.last);
  }

  /// Format du paramètre `?focus=` de l'écran ASTRA AI : `type:id`.
  static AiFocus? parse(String? value) {
    final separator = value?.indexOf(':') ?? -1;
    if (value == null || separator <= 0 || separator == value.length - 1) return null;
    return AiFocus(value.substring(0, separator), value.substring(separator + 1));
  }

  final String type;
  final String id;

  String get query => '$type:$id';

  String get label => switch (type) {
    'project' => 'Ce projet',
    'task' => 'Cette tâche',
    'meeting' => 'Cette réunion',
    'channel' => 'Cette conversation',
    'document' => 'Ce document',
    'decision' => 'Cette décision',
    _ => 'Cet écran',
  };

  Json toJson() => {'type': type, 'id': id};
}

enum AiActionStatus { proposed, applied, dismissed }

/// Action proposée par Ronda : rien n'est créé tant que le membre ne valide pas.
class AiAction {
  const AiAction({
    required this.kind,
    required this.status,
    required this.title,
    required this.details,
    this.resultType,
    this.resultId,
  });

  factory AiAction.fromJson(Json json) => AiAction(
    kind: json['kind'] as String,
    status: enumFromJson(AiActionStatus.values, json['status'], AiActionStatus.proposed),
    title: json['title'] as String,
    details: stringsOf(json['details']),
    resultType: json['result_type'] as String?,
    resultId: json['result_id'] as String?,
  );

  final String kind;
  final AiActionStatus status;
  final String title;
  final List<String> details;

  /// Élément créé après validation (`project`, `meeting`, `task`, `decision`).
  final String? resultType;
  final String? resultId;
}

/// Message d'une conversation ASTRA AI enregistrée côté serveur.
class AiMessage {
  const AiMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.sources,
    required this.status,
    this.focusTitle,
    this.action,
  });

  factory AiMessage.fromJson(Json json) => AiMessage(
    id: json['id'] as String,
    role: json['role'] as String,
    content: json['content'] as String,
    sources: listOf(json['sources'], AiSource.fromJson),
    status: enumFromJson(AiMessageStatus.values, json['status'], AiMessageStatus.done),
    focusTitle: json['focus_title'] as String?,
    action: switch (json['action']) {
      final Json action => AiAction.fromJson(action),
      _ => null,
    },
  );

  final String id;
  final String role;
  final String content;
  final List<AiSource> sources;
  final AiMessageStatus status;

  /// Titre de l'écran consulté quand la question a été posée.
  final String? focusTitle;

  final AiAction? action;

  AiMessage withAction(AiAction value) => AiMessage(
    id: id,
    role: role,
    content: content,
    sources: sources,
    status: status,
    focusTitle: focusTitle,
    action: value,
  );

  bool get isUser => role == 'user';
}

class AiConversationSummary {
  const AiConversationSummary({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.isPending,
  });

  factory AiConversationSummary.fromJson(Json json) => AiConversationSummary(
    id: json['id'] as String,
    title: json['title'] as String,
    updatedAt: DateTime.parse(json['updated_at'] as String),
    isPending: json['is_pending'] as bool,
  );

  final String id;
  final String title;
  final DateTime updatedAt;

  /// Ronda génère encore une réponse (elle continue même écran fermé).
  final bool isPending;
}

class AiConversation extends AiConversationSummary {
  const AiConversation({
    required super.id,
    required super.title,
    required super.updatedAt,
    required super.isPending,
    required this.messages,
  });

  factory AiConversation.fromJson(Json json) {
    final summary = AiConversationSummary.fromJson(json);
    return AiConversation(
      id: summary.id,
      title: summary.title,
      updatedAt: summary.updatedAt,
      isPending: summary.isPending,
      messages: listOf(json['messages'], AiMessage.fromJson),
    );
  }

  final List<AiMessage> messages;
}

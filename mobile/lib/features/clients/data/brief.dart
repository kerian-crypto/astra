import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_hub/core/network/api_client.dart';
import 'package:astra_hub/core/network/api_exception.dart';
import 'package:astra_hub/core/theme/astra_theme.dart';
import 'package:astra_hub/core/utils/json.dart';
import 'package:astra_hub/features/clients/data/clients.dart';

enum BriefStatus {
  draft('draft', 'Brouillon', AstraTheme.textSecondary),
  submitted('submitted', 'À étudier', AstraTheme.warning),
  inReview('in_review', 'En cours d\'étude', AstraTheme.secondary),
  converted('converted', 'Projet créé', AstraTheme.accent),
  archived('archived', 'Archivé', AstraTheme.textSecondary);

  const BriefStatus(this.value, this.label, this.color);
  final String value;
  final String label;
  final Color color;

  static BriefStatus parse(Object? value) =>
      values.where((s) => s.value == value).firstOrNull ?? submitted;
}

class BriefChoice {
  const BriefChoice(this.value, this.label);

  final String value;
  final String label;
}

class BriefQuestion {
  const BriefQuestion({
    required this.id,
    required this.label,
    required this.type,
    required this.choices,
  });

  factory BriefQuestion.fromJson(Json json) => BriefQuestion(
    id: json['id'] as String,
    label: json['label'] as String,
    type: json['type'] as String,
    choices: [
      for (final c in (json['choices'] as List<dynamic>? ?? const []))
        BriefChoice((c as Json)['value'] as String, c['label'] as String),
    ],
  );

  final String id;
  final String label;
  final String type;
  final List<BriefChoice> choices;

  /// Réponse lisible (listes, choix, dates).
  String describe(Object? value) {
    if (value == null) return '—';
    String label(String v) => choices.where((c) => c.value == v).firstOrNull?.label ?? v;
    return switch (type) {
      'list' => (value as List<dynamic>).map((e) => '• $e').join('\n'),
      'single_choice' => label(value as String),
      'multi_choice' => [
        for (final v in ((value as Json)['selected'] as List<dynamic>? ?? const []))
          label(v as String),
        if (value['other'] != null) value['other'] as String,
      ].join(', '),
      _ => '$value',
    };
  }
}

class BriefSection {
  const BriefSection({required this.id, required this.title, required this.questions});

  factory BriefSection.fromJson(Json json) => BriefSection(
    id: json['id'] as String,
    title: json['title'] as String,
    questions: listOf(json['questions'], BriefQuestion.fromJson),
  );

  final String id;
  final String title;
  final List<BriefQuestion> questions;
}

class PlannedTask {
  const PlannedTask({required this.title, this.description, this.priority = 'medium'});

  factory PlannedTask.fromJson(Json json) => PlannedTask(
    title: json['title'] as String,
    description: json['description'] as String?,
    priority: json['priority'] as String? ?? 'medium',
  );

  final String title;
  final String? description;
  final String priority;
}

class PlannedPhase {
  const PlannedPhase({required this.name, required this.tasks, this.dueDate});

  factory PlannedPhase.fromJson(Json json) => PlannedPhase(
    name: json['name'] as String,
    dueDate: dateOrNull(json['due_date']),
    tasks: listOf(json['tasks'], PlannedTask.fromJson),
  );

  final String name;
  final DateTime? dueDate;
  final List<PlannedTask> tasks;
}

class HubBrief {
  const HubBrief({
    required this.id,
    required this.status,
    required this.title,
    required this.answers,
    required this.files,
    required this.companyId,
    required this.companyName,
    required this.companySelfRegistered,
    required this.plan,
    required this.planJson,
    this.authorName,
    this.submittedAt,
    this.projectId,
  });

  factory HubBrief.fromJson(Json json) {
    final plan = json['proposed_plan'] as Json;
    return HubBrief(
      id: json['id'] as String,
      status: BriefStatus.parse(json['status']),
      title: json['title'] as String,
      answers: (json['answers'] as Json?) ?? const {},
      files: [
        for (final f in (json['files'] as List<dynamic>? ?? const []))
          (
            id: (f as Json)['id'] as String,
            questionId: f['question_id'] as String,
            file: AttachedFile.fromJson(f['file'])!,
          ),
      ],
      companyId: json['company_id'] as String,
      companyName: json['company_name'] as String,
      companySelfRegistered: json['company_self_registered'] as bool? ?? false,
      authorName: json['author_name'] as String?,
      submittedAt: dateOrNull(json['submitted_at']),
      projectId: json['project_id'] as String?,
      plan: listOf(plan['phases'], PlannedPhase.fromJson),
      planJson: plan,
    );
  }

  final String id;
  final BriefStatus status;
  final String title;
  final Json answers;
  final List<({String id, String questionId, AttachedFile file})> files;
  final String companyId;
  final String companyName;
  final bool companySelfRegistered;
  final String? authorName;
  final DateTime? submittedAt;
  final String? projectId;
  final List<PlannedPhase> plan;
  final Json planJson;

  int get taskCount => plan.fold(0, (sum, p) => sum + p.tasks.length);
  bool get canConvert => status == BriefStatus.submitted || status == BriefStatus.inReview;
}

final briefRepositoryProvider = Provider<HubBriefRepository>(
  (ref) => HubBriefRepository(ref.watch(dioProvider)),
);

class HubBriefRepository {
  HubBriefRepository(this._dio);

  final Dio _dio;

  Future<List<BriefSection>> questionnaire() => guardApi(() async {
    final response = await _dio.get<Json>('/clients/briefs/questionnaire');
    return listOf(response.data!['sections'], BriefSection.fromJson);
  });

  Future<List<HubBrief>> list() => guardApi(() async {
    final response = await _dio.get<List<dynamic>>('/clients/briefs');
    return listOf(response.data, HubBrief.fromJson);
  });

  Future<HubBrief> get(String id) => guardApi(() async {
    final response = await _dio.get<Json>('/clients/briefs/$id');
    return HubBrief.fromJson(response.data!);
  });

  Future<HubBrief> _post(String path, [Object? data]) => guardApi(() async {
    final response = await _dio.post<Json>(path, data: data);
    return HubBrief.fromJson(response.data!);
  });

  Future<HubBrief> startReview(String id) => _post('/clients/briefs/$id/start-review');

  /// Crée le projet à partir du plan proposé (nom et responsable ajustables).
  Future<HubBrief> convert(String id, {Json? plan}) =>
      _post('/clients/briefs/$id/convert', {'plan': ?plan});

  Future<HubBrief> archive(String id) => _post('/clients/briefs/$id/archive');
}

final hubBriefsProvider = FutureProvider.autoDispose<List<HubBrief>>(
  (ref) => ref.watch(briefRepositoryProvider).list(),
);

final hubBriefProvider = FutureProvider.autoDispose.family<HubBrief, String>(
  (ref, id) => ref.watch(briefRepositoryProvider).get(id),
);

final briefQuestionnaireProvider = FutureProvider<List<BriefSection>>(
  (ref) => ref.watch(briefRepositoryProvider).questionnaire(),
);

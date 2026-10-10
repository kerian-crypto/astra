import 'package:astra_client/core/theme/client_theme.dart';
import 'package:astra_client/core/utils/json.dart';
import 'package:astra_client/features/deliverables/data/deliverable.dart';

enum QuestionType { text, longText, number, list, singleChoice, multiChoice, date, files }

QuestionType _type(Object? value) => switch (value) {
  'long_text' => QuestionType.longText,
  'number' => QuestionType.number,
  'list' => QuestionType.list,
  'single_choice' => QuestionType.singleChoice,
  'multi_choice' => QuestionType.multiChoice,
  'date' => QuestionType.date,
  'files' => QuestionType.files,
  _ => QuestionType.text,
};

class QuestionChoice {
  const QuestionChoice({required this.value, required this.label, this.description});

  factory QuestionChoice.fromJson(Json json) => QuestionChoice(
    value: json['value'] as String,
    label: json['label'] as String,
    description: json['description'] as String?,
  );

  final String value;
  final String label;
  final String? description;
}

class BriefQuestion {
  const BriefQuestion({
    required this.id,
    required this.label,
    required this.type,
    required this.required,
    this.help,
    this.example,
    this.choices = const [],
    this.minItems,
    this.maxItems,
    this.allowOther = false,
  });

  factory BriefQuestion.fromJson(Json json) => BriefQuestion(
    id: json['id'] as String,
    label: json['label'] as String,
    type: _type(json['type']),
    required: json['required'] as bool? ?? false,
    help: json['help'] as String?,
    example: json['example'] as String?,
    choices: listOf(json['choices'], QuestionChoice.fromJson),
    minItems: json['min_items'] as int?,
    maxItems: json['max_items'] as int?,
    allowOther: json['allow_other'] as bool? ?? false,
  );

  final String id;
  final String label;
  final QuestionType type;
  final bool required;
  final String? help;
  final String? example;
  final List<QuestionChoice> choices;
  final int? minItems;
  final int? maxItems;
  final bool allowOther;

  /// Réponse présente au sens du serveur (les fichiers sont comptés à part).
  bool isAnswered(Object? answer) => switch (answer) {
    null => false,
    final String text => text.trim().isNotEmpty,
    final List<Object?> list => list.isNotEmpty && list.length >= (minItems ?? 1),
    final Map<String, Object?> map =>
      ((map['selected'] as List<Object?>?) ?? const []).isNotEmpty ||
          ((map['other'] as String?) ?? '').trim().isNotEmpty,
    _ => true,
  };
}

class BriefSection {
  const BriefSection({
    required this.id,
    required this.title,
    required this.intro,
    required this.questions,
  });

  factory BriefSection.fromJson(Json json) => BriefSection(
    id: json['id'] as String,
    title: json['title'] as String,
    intro: json['intro'] as String,
    questions: listOf(json['questions'], BriefQuestion.fromJson),
  );

  final String id;
  final String title;
  final String intro;
  final List<BriefQuestion> questions;
}

class Questionnaire {
  const Questionnaire(this.sections);

  factory Questionnaire.fromJson(Json json) =>
      Questionnaire(listOf(json['sections'], BriefSection.fromJson));

  final List<BriefSection> sections;

  BriefQuestion? question(String id) =>
      sections.expand((s) => s.questions).where((q) => q.id == id).firstOrNull;
}

enum BriefStatus {
  draft('draft', 'Brouillon', Tone.warning),
  submitted('submitted', 'Transmis à Astra', Tone.info),
  inReview('in_review', 'En cours d\'étude', Tone.brand),
  converted('converted', 'Projet lancé', Tone.success),
  archived('archived', 'Archivé', Tone.neutral);

  const BriefStatus(this.value, this.label, this.tone);
  final String value;
  final String label;
  final Tone tone;

  static BriefStatus parse(Object? value) =>
      values.where((s) => s.value == value).firstOrNull ?? draft;
}

class BriefFile {
  const BriefFile({required this.id, required this.questionId, required this.file});

  factory BriefFile.fromJson(Json json) => BriefFile(
    id: json['id'] as String,
    questionId: json['question_id'] as String,
    file: AttachedFile.fromJson(json['file'])!,
  );

  final String id;
  final String questionId;
  final AttachedFile file;
}

class Brief {
  const Brief({
    required this.id,
    required this.status,
    required this.title,
    required this.answers,
    required this.missingRequired,
    required this.files,
    required this.createdAt,
    required this.updatedAt,
    this.currentSection,
    this.submittedAt,
    this.projectId,
  });

  factory Brief.fromJson(Json json) => Brief(
    id: json['id'] as String,
    status: BriefStatus.parse(json['status']),
    title: json['title'] as String,
    answers: Map.unmodifiable((json['answers'] as Json?) ?? const {}),
    currentSection: json['current_section'] as String?,
    missingRequired: stringsOf(json['missing_required']),
    files: listOf(json['files'], BriefFile.fromJson),
    submittedAt: dateOrNull(json['submitted_at']),
    projectId: json['project_id'] as String?,
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
  );

  final String id;
  final BriefStatus status;
  final String title;
  final Map<String, Object?> answers;
  final String? currentSection;
  final List<String> missingRequired;
  final List<BriefFile> files;
  final DateTime? submittedAt;
  final String? projectId;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isDraft => status == BriefStatus.draft;

  List<BriefFile> filesFor(String questionId) =>
      files.where((f) => f.questionId == questionId).toList();
}

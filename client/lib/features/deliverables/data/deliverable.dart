import 'package:astra_client/core/theme/client_theme.dart';
import 'package:astra_client/core/utils/json.dart';

enum DeliverableStatus {
  published('Disponible', Tone.brand),
  awaitingValidation('Validation requise', Tone.warning),
  approved('Approuvé', Tone.success),
  changesRequested('Modification demandée', Tone.info);

  const DeliverableStatus(this.label, this.tone);
  final String label;
  final Tone tone;

  static DeliverableStatus parse(Object? value) => switch (value) {
    'awaiting_validation' => awaitingValidation,
    'approved' => approved,
    'changes_requested' => changesRequested,
    _ => published,
  };
}

enum ReviewAction {
  approve('approve'),
  requestChanges('request_changes');

  const ReviewAction(this.value);
  final String value;
}

class AttachedFile {
  const AttachedFile({required this.name, required this.contentType, required this.sizeBytes});

  static AttachedFile? fromJson(Object? json) {
    if (json is! Json) return null;
    return AttachedFile(
      name: json['name'] as String,
      contentType: json['content_type'] as String,
      sizeBytes: json['size_bytes'] as int? ?? 0,
    );
  }

  final String name;
  final String contentType;
  final int sizeBytes;

  bool get isImage => contentType.startsWith('image/');
}

class DeliverableVersion {
  const DeliverableVersion({
    required this.id,
    required this.number,
    required this.publishedAt,
    this.notes,
    this.linkUrl,
    this.file,
  });

  factory DeliverableVersion.fromJson(Json json) => DeliverableVersion(
    id: json['id'] as String,
    number: json['number'] as int,
    notes: json['notes'] as String?,
    linkUrl: json['link_url'] as String?,
    file: AttachedFile.fromJson(json['file']),
    publishedAt: DateTime.parse(json['published_at'] as String),
  );

  final String id;
  final int number;
  final String? notes;
  final String? linkUrl;
  final AttachedFile? file;
  final DateTime publishedAt;
}

class DeliverableReview {
  const DeliverableReview({
    required this.id,
    required this.versionNumber,
    required this.approved,
    required this.reviewerName,
    required this.createdAt,
    this.reason,
    this.comment,
    this.file,
  });

  factory DeliverableReview.fromJson(Json json) => DeliverableReview(
    id: json['id'] as String,
    versionNumber: json['version_number'] as int,
    approved: json['action'] == 'approve',
    reviewerName: json['reviewer_name'] as String,
    reason: json['reason'] as String?,
    comment: json['comment'] as String?,
    file: AttachedFile.fromJson(json['file']),
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  final String id;
  final int versionNumber;
  final bool approved;
  final String reviewerName;
  final String? reason;
  final String? comment;
  final AttachedFile? file;
  final DateTime createdAt;
}

class Deliverable {
  const Deliverable({
    required this.id,
    required this.projectId,
    required this.projectName,
    required this.title,
    required this.status,
    required this.requiresValidation,
    required this.updatedAt,
    this.description,
    this.dueDate,
    this.currentVersion,
  });

  factory Deliverable.fromJson(Json json) => Deliverable(
    id: json['id'] as String,
    projectId: json['project_id'] as String,
    projectName: json['project_name'] as String? ?? '',
    title: json['title'] as String,
    description: json['description'] as String?,
    status: DeliverableStatus.parse(json['status']),
    requiresValidation: json['requires_validation'] as bool? ?? false,
    dueDate: dateOrNull(json['due_date']),
    currentVersion: json['current_version'] == null
        ? null
        : DeliverableVersion.fromJson(json['current_version'] as Json),
    updatedAt: DateTime.parse(json['updated_at'] as String),
  );

  final String id;
  final String projectId;
  final String projectName;
  final String title;
  final String? description;
  final DeliverableStatus status;
  final bool requiresValidation;
  final DateTime? dueDate;
  final DeliverableVersion? currentVersion;
  final DateTime updatedAt;
}

class DeliverableDetail extends Deliverable {
  const DeliverableDetail({
    required super.id,
    required super.projectId,
    required super.projectName,
    required super.title,
    required super.status,
    required super.requiresValidation,
    required super.updatedAt,
    required this.versions,
    required this.reviews,
    required this.canReview,
    super.description,
    super.dueDate,
    super.currentVersion,
  });

  factory DeliverableDetail.fromJson(Json json) {
    final base = Deliverable.fromJson(json);
    return DeliverableDetail(
      id: base.id,
      projectId: base.projectId,
      projectName: base.projectName,
      title: base.title,
      description: base.description,
      status: base.status,
      requiresValidation: base.requiresValidation,
      dueDate: base.dueDate,
      currentVersion: base.currentVersion,
      updatedAt: base.updatedAt,
      versions: listOf(json['versions'], DeliverableVersion.fromJson),
      reviews: listOf(json['reviews'], DeliverableReview.fromJson),
      canReview: json['can_review'] as bool? ?? false,
    );
  }

  final List<DeliverableVersion> versions;
  final List<DeliverableReview> reviews;
  final bool canReview;
}

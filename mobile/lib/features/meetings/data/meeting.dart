import 'package:astra_hub/core/utils/json.dart';
import 'package:astra_hub/features/members/data/member.dart';

enum MeetingStatus {
  planned('Planifiée'),
  done('Terminée'),
  cancelled('Annulée');

  const MeetingStatus(this.label);

  final String label;
}

enum DecisionStatus {
  proposed('Proposée'),
  validated('Validée'),
  rejected('Rejetée');

  const DecisionStatus(this.label);

  final String label;
}

class Meeting {
  const Meeting({
    required this.id,
    required this.title,
    required this.scheduledAt,
    required this.durationMinutes,
    required this.status,
    this.projectId,
    this.location,
  });

  factory Meeting.fromJson(Json json) => Meeting(
    id: json['id'] as String,
    projectId: json['project_id'] as String?,
    title: json['title'] as String,
    scheduledAt: DateTime.parse(json['scheduled_at'] as String).toLocal(),
    durationMinutes: json['duration_minutes'] as int,
    location: json['location'] as String?,
    status: enumFromJson(MeetingStatus.values, json['status'], MeetingStatus.planned),
  );

  final String id;
  final String? projectId;
  final String title;
  final DateTime scheduledAt;
  final int durationMinutes;
  final String? location;
  final MeetingStatus status;
}

class Decision {
  const Decision({
    required this.id,
    required this.title,
    required this.status,
    this.description,
    this.meetingId,
    this.projectId,
    this.resultingProjectId,
  });

  factory Decision.fromJson(Json json) => Decision(
    id: json['id'] as String,
    title: json['title'] as String,
    description: json['description'] as String?,
    status: enumFromJson(DecisionStatus.values, json['status'], DecisionStatus.proposed),
    meetingId: json['meeting_id'] as String?,
    projectId: json['project_id'] as String?,
    resultingProjectId: json['resulting_project_id'] as String?,
  );

  final String id;
  final String title;
  final String? description;
  final DecisionStatus status;
  final String? meetingId;
  final String? projectId;
  final String? resultingProjectId;
}

class MeetingDetail {
  const MeetingDetail({
    required this.meeting,
    required this.participants,
    required this.decisions,
    required this.canEdit,
    this.agenda,
    this.minutes,
  });

  factory MeetingDetail.fromJson(Json json) => MeetingDetail(
    meeting: Meeting.fromJson(json),
    agenda: json['agenda'] as String?,
    minutes: json['minutes'] as String?,
    participants: listOf(json['participants'], Member.fromJson),
    decisions: listOf(json['decisions'], Decision.fromJson),
    canEdit: json['can_edit'] as bool,
  );

  final Meeting meeting;
  final String? agenda;
  final String? minutes;
  final List<Member> participants;
  final List<Decision> decisions;
  final bool canEdit;
}

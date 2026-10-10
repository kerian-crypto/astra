import 'package:flutter/material.dart';

import 'package:astra_client/core/theme/client_theme.dart';
import 'package:astra_client/core/utils/json.dart';

enum TicketType {
  technical('technical', 'Support technique', Icons.build_outlined),
  question('question', 'Question', Icons.help_outline),
  change('change', 'Modification', Icons.edit_note_outlined),
  complaint('complaint', 'Réclamation', Icons.report_outlined),
  administrative('administrative', 'Demande administrative', Icons.business_center_outlined),
  documentRequest('document_request', 'Demande de document', Icons.description_outlined),
  other('other', 'Autre', Icons.more_horiz);

  const TicketType(this.value, this.label, this.icon);
  final String value;
  final String label;
  final IconData icon;

  static TicketType parse(Object? value) =>
      values.where((t) => t.value == value).firstOrNull ?? other;
}

enum TicketStatus {
  newTicket('new', 'Nouveau', Tone.info),
  acknowledged('acknowledged', 'Pris en charge', Tone.brand),
  inProgress('in_progress', 'En cours', Tone.brand),
  waitingClient('waiting_client', 'En attente de votre réponse', Tone.warning),
  resolved('resolved', 'Résolu', Tone.success),
  closed('closed', 'Fermé', Tone.neutral);

  const TicketStatus(this.value, this.label, this.tone);
  final String value;
  final String label;
  final Tone tone;

  static TicketStatus parse(Object? value) =>
      values.where((s) => s.value == value).firstOrNull ?? newTicket;

  bool get isOpen => this != resolved && this != closed;
}

enum TicketPriority {
  low('low', 'Basse'),
  normal('normal', 'Normale'),
  high('high', 'Haute'),
  urgent('urgent', 'Urgente');

  const TicketPriority(this.value, this.label);
  final String value;
  final String label;

  static TicketPriority parse(Object? value) =>
      values.where((p) => p.value == value).firstOrNull ?? normal;
}

class Ticket {
  const Ticket({
    required this.id,
    required this.number,
    required this.type,
    required this.subject,
    required this.description,
    required this.status,
    required this.priority,
    required this.createdAt,
    required this.updatedAt,
    this.projectId,
    this.projectName,
    this.createdByName,
    this.conversationId,
  });

  factory Ticket.fromJson(Json json) => Ticket(
    id: json['id'] as String,
    number: json['number'] as String,
    type: TicketType.parse(json['type']),
    subject: json['subject'] as String,
    description: json['description'] as String,
    status: TicketStatus.parse(json['status']),
    priority: TicketPriority.parse(json['priority']),
    projectId: json['project_id'] as String?,
    projectName: json['project_name'] as String?,
    createdByName: json['created_by_name'] as String?,
    conversationId: json['conversation_id'] as String?,
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
  );

  final String id;
  final String number;
  final TicketType type;
  final String subject;
  final String description;
  final TicketStatus status;
  final TicketPriority priority;
  final String? projectId;
  final String? projectName;
  final String? createdByName;
  final String? conversationId;
  final DateTime createdAt;
  final DateTime updatedAt;
}

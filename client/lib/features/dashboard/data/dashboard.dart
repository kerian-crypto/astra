import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_client/core/network/api_client.dart';
import 'package:astra_client/core/utils/json.dart';
import 'package:astra_client/features/auth/data/session.dart';
import 'package:astra_client/features/documents/data/document.dart';

class ActionItem {
  const ActionItem({
    required this.kind,
    required this.title,
    required this.entityType,
    required this.entityId,
    this.subtitle,
    this.createdAt,
  });

  factory ActionItem.fromJson(Json json) => ActionItem(
    kind: json['kind'] as String,
    title: json['title'] as String,
    subtitle: json['subtitle'] as String?,
    entityType: json['entity_type'] as String,
    entityId: json['entity_id'] as String,
    createdAt: dateOrNull(json['created_at']),
  );

  final String kind;
  final String title;
  final String? subtitle;
  final String entityType;
  final String entityId;
  final DateTime? createdAt;
}

class Deadline {
  const Deadline({
    required this.kind,
    required this.title,
    required this.dueDate,
    required this.entityType,
    required this.entityId,
  });

  factory Deadline.fromJson(Json json) => Deadline(
    kind: json['kind'] as String,
    title: json['title'] as String,
    dueDate: DateTime.parse(json['due_date'] as String),
    entityType: json['entity_type'] as String,
    entityId: json['entity_id'] as String,
  );

  final String kind;
  final String title;
  final DateTime dueDate;
  final String entityType;
  final String entityId;
}

class Dashboard {
  const Dashboard({
    required this.company,
    required this.activeProjects,
    required this.completedProjects,
    required this.pendingValidations,
    required this.unreadMessages,
    required this.unreadNotifications,
    required this.actions,
    required this.deadlines,
    required this.recentDocuments,
    this.pendingInvoices,
    this.openTickets,
    this.briefId,
    this.briefStatus,
    this.needsOnboarding = false,
  });

  factory Dashboard.fromJson(Json json) => Dashboard(
    company: Company.fromJson(json['company'] as Json),
    activeProjects: json['active_projects'] as int? ?? 0,
    completedProjects: json['completed_projects'] as int? ?? 0,
    pendingValidations: json['pending_validations'] as int? ?? 0,
    unreadMessages: json['unread_messages'] as int? ?? 0,
    unreadNotifications: json['unread_notifications'] as int? ?? 0,
    pendingInvoices: json['pending_invoices'] as int?,
    openTickets: json['open_tickets'] as int?,
    actions: listOf(json['actions'], ActionItem.fromJson),
    deadlines: listOf(json['deadlines'], Deadline.fromJson),
    recentDocuments: listOf(json['recent_documents'], ClientDocument.fromJson),
    briefId: json['brief_id'] as String?,
    briefStatus: json['brief_status'] as String?,
    needsOnboarding: json['needs_onboarding'] as bool? ?? false,
  );

  final Company company;
  final int activeProjects;
  final int completedProjects;
  final int pendingValidations;
  final int unreadMessages;
  final int unreadNotifications;
  final int? pendingInvoices;
  final int? openTickets;
  final List<ActionItem> actions;
  final List<Deadline> deadlines;
  final List<ClientDocument> recentDocuments;
  final String? briefId;
  final String? briefStatus;
  final bool needsOnboarding;
}

final dashboardProvider = FutureProvider.autoDispose<Dashboard>(
  (ref) => ref
      .watch(apiProvider)
      .get('/client/dashboard', parse: (data) => Dashboard.fromJson(data! as Json)),
);

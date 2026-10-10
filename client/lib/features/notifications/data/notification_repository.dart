import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_client/core/network/api_client.dart';
import 'package:astra_client/core/theme/client_theme.dart';
import 'package:astra_client/core/utils/json.dart';

class ClientNotification {
  const ClientNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.entityType,
    required this.entityId,
    required this.createdAt,
    this.body,
    this.readAt,
  });

  factory ClientNotification.fromJson(Json json) => ClientNotification(
    id: json['id'] as String,
    kind: json['kind'] as String,
    title: json['title'] as String,
    body: json['body'] as String?,
    entityType: json['entity_type'] as String,
    entityId: json['entity_id'] as String,
    readAt: dateOrNull(json['read_at']),
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  final String id;
  final String kind;
  final String title;
  final String? body;
  final String entityType;
  final String entityId;
  final DateTime? readAt;
  final DateTime createdAt;

  bool get isUnread => readAt == null;

  (IconData, Tone) get visual => switch (kind) {
    'new_message' => (Icons.chat_bubble_outline, Tone.brand),
    'validation_required' => (Icons.fact_check_outlined, Tone.warning),
    'deliverable_ready' => (Icons.inventory_2_outlined, Tone.brand),
    'document_available' => (Icons.description_outlined, Tone.info),
    'invoice_created' => (Icons.receipt_long_outlined, Tone.info),
    'payment_confirmed' => (Icons.verified_outlined, Tone.success),
    'payment_rejected' => (Icons.report_gmailerrorred_outlined, Tone.danger),
    'ticket_updated' => (Icons.support_agent_outlined, Tone.brand),
    'contract_available' => (Icons.handshake_outlined, Tone.info),
    'project_added' => (Icons.rocket_launch_outlined, Tone.success),
    _ => (Icons.folder_outlined, Tone.neutral),
  };
}

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => NotificationRepository(ref.watch(apiProvider)),
);

class NotificationRepository {
  NotificationRepository(this._api);

  final Api _api;

  Future<List<ClientNotification>> list() =>
      _api.get('/client/notifications', parse: (data) => listOf(data, ClientNotification.fromJson));

  Future<void> markRead(String id) => _api.post<void>('/client/notifications/$id/read');

  Future<void> markAllRead() => _api.post<void>('/client/notifications/read-all');
}

final notificationsProvider = FutureProvider.autoDispose<List<ClientNotification>>(
  (ref) => ref.watch(notificationRepositoryProvider).list(),
);

final unreadNotificationsProvider = Provider.autoDispose<int>(
  (ref) => ref.watch(notificationsProvider).value?.where((n) => n.isUnread).length ?? 0,
);

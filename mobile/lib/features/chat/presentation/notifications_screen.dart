import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:astra_hub/core/network/api_exception.dart';
import 'package:astra_hub/core/router/routes.dart';
import 'package:astra_hub/core/utils/formatting.dart';
import 'package:astra_hub/core/widgets/async_value_view.dart';
import 'package:astra_hub/features/chat/data/chat.dart';
import 'package:astra_hub/features/chat/data/chat_repository.dart';
import 'package:astra_hub/features/home/data/work.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  static String? routeFor(AppNotification n) => Routes.forEntity(n.entityType, n.entityId);

  IconData _icon(NotificationKind kind) => switch (kind) {
    NotificationKind.mention => Icons.alternate_email,
    NotificationKind.taskAssigned => Icons.assignment_ind_outlined,
    NotificationKind.taskStatus => Icons.published_with_changes,
    NotificationKind.taskComment => Icons.comment_outlined,
    NotificationKind.projectAdded => Icons.create_new_folder_outlined,
    NotificationKind.projectStatus => Icons.flag_outlined,
    NotificationKind.meetingInvite => Icons.event_outlined,
    NotificationKind.meetingUpdated => Icons.edit_calendar_outlined,
    NotificationKind.meetingCancelled => Icons.event_busy_outlined,
    NotificationKind.decisionProposed => Icons.how_to_vote_outlined,
    NotificationKind.decisionReviewed => Icons.gavel_outlined,
    NotificationKind.documentAdded => Icons.description_outlined,
    NotificationKind.channelAdded => Icons.group_add_outlined,
    NotificationKind.registrationRequest => Icons.person_add_alt,
    NotificationKind.other => Icons.notifications_outlined,
  };

  Future<void> _open(BuildContext context, WidgetRef ref, AppNotification n) async {
    try {
      if (n.isUnread) await ref.read(chatRepositoryProvider).markNotificationRead(n.id);
    } on ApiException {
      // La navigation reste possible même si le marquage échoue.
    }
    ref
      ..invalidate(notificationsProvider)
      ..invalidate(dashboardProvider);
    final route = routeFor(n);
    if (route != null && context.mounted) await context.push(route);
  }

  Future<void> _markAll(WidgetRef ref) async {
    await ref.read(chatRepositoryProvider).markAllNotificationsRead();
    ref
      ..invalidate(notificationsProvider)
      ..invalidate(dashboardProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [TextButton(onPressed: () => _markAll(ref), child: const Text('Tout lire'))],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(notificationsProvider.future),
        child: AsyncValueView(
          value: notifications,
          onRetry: () => ref.invalidate(notificationsProvider),
          data: (items) => items.isEmpty
              ? const EmptyState(icon: Icons.notifications_none, message: 'Aucune notification.')
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (_, index) {
                    final n = items[index];
                    return ListTile(
                      leading: Icon(_icon(n.kind)),
                      title: Text(
                        n.title,
                        style: n.isUnread ? const TextStyle(fontWeight: FontWeight.bold) : null,
                      ),
                      subtitle: Text(
                        [?n.body, formatShortMoment(n.createdAt)].join('\n'),
                        maxLines: 3,
                      ),
                      isThreeLine: n.body != null,
                      onTap: () => _open(context, ref, n),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

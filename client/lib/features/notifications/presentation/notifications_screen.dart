import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:astra_client/core/layout/page_frame.dart';
import 'package:astra_client/core/router/routes.dart';
import 'package:astra_client/core/theme/client_theme.dart';
import 'package:astra_client/core/utils/formatting.dart';
import 'package:astra_client/core/widgets/state_views.dart';
import 'package:astra_client/core/widgets/ui.dart';
import 'package:astra_client/features/dashboard/data/dashboard.dart';
import 'package:astra_client/features/notifications/data/notification_repository.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  Future<void> _open(BuildContext context, WidgetRef ref, ClientNotification notification) async {
    if (notification.isUnread) {
      unawaited(
        ref.read(notificationRepositoryProvider).markRead(notification.id).then((_) {
          ref
            ..invalidate(notificationsProvider)
            ..invalidate(dashboardProvider);
        }, onError: (Object _) {}),
      );
    }
    final route = Routes.forEntity(notification.entityType, notification.entityId);
    if (route != null) await context.push(route);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationsProvider);
    final unread = ref.watch(unreadNotificationsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (unread > 0)
            TextButton(
              onPressed: () async {
                try {
                  await ref.read(notificationRepositoryProvider).markAllRead();
                  ref.invalidate(notificationsProvider);
                } on Exception catch (error) {
                  if (context.mounted) showError(context, error);
                }
              },
              child: const Text('Tout marquer lu'),
            ),
        ],
      ),
      body: AsyncView(
        value: notifications,
        onRetry: () => ref.invalidate(notificationsProvider),
        isEmpty: (list) => list.isEmpty,
        empty: const StateMessage(
          icon: Icons.notifications_none_rounded,
          title: 'Aucune notification',
          message: 'Vous serez prévenu ici des nouveautés de vos projets.',
        ),
        builder: (list) => FramedListView(
          maxWidth: 760,
          onRefresh: () => ref.refresh(notificationsProvider.future),
          children: [
            for (final notification in list)
              _NotificationTile(
                notification: notification,
                onTap: () => _open(context, ref, notification),
              ),
          ],
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final ClientNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, tone) = notification.visual;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Material(
        color: notification.isUnread
            ? scheme.primaryContainer.withValues(alpha: 0.45)
            : scheme.surface,
        borderRadius: BorderRadius.circular(ClientTheme.radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(ClientTheme.radius),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Space.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ToneIcon(icon, tone: tone),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        notification.title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: notification.isUnread ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                      if (notification.body != null)
                        Text(notification.body!, maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(
                        formatRelative(notification.createdAt),
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (notification.isUnread)
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(top: 6),
                    decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

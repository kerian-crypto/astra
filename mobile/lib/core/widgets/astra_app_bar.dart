import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:astra_hub/core/router/routes.dart';
import 'package:astra_hub/features/chat/data/chat_repository.dart';

/// Barre commune des onglets : recherche, notifications et accès permanent
/// à ASTRA AI (spec §11).
class AstraAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const AstraAppBar({required this.title, this.bottom, super.key});

  final String title;
  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize => Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationsProvider);
    return AppBar(
      title: Text(title),
      bottom: bottom,
      actions: [
        IconButton(
          tooltip: 'Rechercher dans Astra',
          icon: const Icon(Icons.search),
          onPressed: () => context.push(Routes.search),
        ),
        IconButton(
          tooltip: 'Notifications',
          icon: Badge(
            isLabelVisible: unread > 0,
            label: Text('$unread'),
            child: const Icon(Icons.notifications_outlined),
          ),
          onPressed: () => context.push(Routes.notifications),
        ),
        IconButton(
          tooltip: 'ASTRA AI',
          icon: const Icon(Icons.auto_awesome),
          onPressed: () => context.push(Routes.ai),
        ),
      ],
    );
  }
}

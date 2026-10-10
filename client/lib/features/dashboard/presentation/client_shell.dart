import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:astra_client/core/layout/breakpoints.dart';
import 'package:astra_client/core/network/api_client.dart';
import 'package:astra_client/core/network/realtime.dart';
import 'package:astra_client/core/push/push_messaging.dart';
import 'package:astra_client/core/push/push_service.dart';
import 'package:astra_client/core/router/routes.dart';
import 'package:astra_client/core/theme/client_theme.dart';
import 'package:astra_client/core/utils/json.dart';
import 'package:astra_client/core/widgets/state_views.dart';
import 'package:astra_client/core/widgets/ui.dart';
import 'package:astra_client/features/auth/presentation/auth_controller.dart';
import 'package:astra_client/features/billing/data/billing_repository.dart';
import 'package:astra_client/features/dashboard/data/dashboard.dart';
import 'package:astra_client/features/deliverables/data/deliverable_repository.dart';
import 'package:astra_client/features/documents/data/document_repository.dart';
import 'package:astra_client/features/projects/data/project_repository.dart';
import 'package:astra_client/features/support/data/ticket_repository.dart';
import 'package:astra_client/features/messages/data/conversation.dart';
import 'package:astra_client/features/messages/data/conversation_repository.dart';
import 'package:astra_client/features/notifications/data/notification_repository.dart';

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _destinations = [
  _Destination('Accueil', Icons.space_dashboard_outlined, Icons.space_dashboard_rounded),
  _Destination('Projets', Icons.work_outline_rounded, Icons.work_rounded),
  _Destination('Messages', Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded),
  _Destination('Documents', Icons.folder_open_outlined, Icons.folder_rounded),
  _Destination('Plus', Icons.grid_view_outlined, Icons.grid_view_rounded),
];

/// Coque des onglets (§12). Adaptée à la largeur : barre de navigation en bas
/// sur téléphone, rail latéral sur tablette, rail étendu sur grand écran.
/// N'existe qu'une fois connecté : ouvre le temps réel et le push.
class ClientShell extends ConsumerStatefulWidget {
  const ClientShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<ClientShell> createState() => _ClientShellState();
}

class _ClientShellState extends ConsumerState<ClientShell> with WidgetsBindingObserver {
  StreamSubscription<Json>? _events;
  StreamSubscription<PushData>? _openedPushes;
  late final RealtimeService _realtime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _realtime = ref.read(realtimeServiceProvider);
    _events = _realtime.events.listen(_onEvent);
    _realtime.start();
    final push = ref.read(pushServiceProvider);
    unawaited(push.register());
    _openedPushes = push.openedMessages().listen(_onPushOpened);
    // Juste après l'inscription : ouverture du questionnaire de cadrage.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !ref.read(onboardingRequestedProvider)) return;
      ref.read(onboardingRequestedProvider.notifier).set(false);
      unawaited(GoRouter.of(context).push(Routes.newBrief));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_events?.cancel());
    unawaited(_openedPushes?.cancel());
    unawaited(_realtime.stop());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      unawaited(_realtime.stop());
    } else if (state == AppLifecycleState.resumed) {
      _realtime.start();
      _refreshSummaries();
    }
  }

  void _refreshSummaries() {
    ref
      ..invalidate(conversationsProvider)
      ..invalidate(notificationsProvider)
      ..invalidate(dashboardProvider);
  }

  void _onEvent(Json event) {
    final type = event['type'] as String? ?? '';
    if (type == 'message.created') {
      final message = event['message'];
      if (message is Json) {
        final parsed = ChatMessage.fromJson(message);
        ref.read(conversationMessagesProvider(parsed.conversationId).notifier).upsert(parsed);
      }
      ref.invalidate(conversationsProvider);
    } else if (type == 'notification.created') {
      ref
        ..invalidate(notificationsProvider)
        ..invalidate(dashboardProvider);
      final notification = event['notification'];
      if (notification is Json) {
        _refreshEntity(
          notification['entity_type'] as String?,
          notification['entity_id'] as String?,
        );
      }
    }
  }

  /// Un écran déjà ouvert se met à jour dès qu'Astra modifie sa ressource.
  void _refreshEntity(String? type, String? id) {
    if (type == null || id == null) return;
    switch (type) {
      case 'deliverable':
        ref
          ..invalidate(deliverableProvider(id))
          ..invalidate(deliverablesProvider)
          ..invalidate(projectsProvider);
      case 'project':
        ref
          ..invalidate(projectProvider(id))
          ..invalidate(projectTimelineProvider(id))
          ..invalidate(projectsProvider);
      case 'invoice':
        ref
          ..invalidate(invoiceProvider(id))
          ..invalidate(invoicesProvider)
          ..invalidate(declarationsProvider);
      case 'support_ticket':
        ref
          ..invalidate(ticketProvider(id))
          ..invalidate(ticketsProvider);
      case 'document':
        ref.invalidate(documentsProvider);
      case 'contract':
        ref.invalidate(contractsProvider);
    }
  }

  void _onPushOpened(PushData data) {
    unawaited(ref.read(pushServiceProvider).markOpened(data));
    _refreshSummaries();
    final route = routeForPush(data);
    if (route != null && mounted) unawaited(GoRouter.of(context).push(route));
  }

  void _select(int index) {
    widget.shell.goBranch(index, initialLocation: index == widget.shell.currentIndex);
  }

  @override
  Widget build(BuildContext context) {
    final unread = ref.watch(unreadMessagesProvider);
    final offline = ref.watch(offlineProvider);
    final size = context.windowSize;
    final body = Column(
      children: [
        if (offline) const OfflineBanner(),
        Expanded(child: widget.shell),
      ],
    );

    if (size == WindowSize.compact) {
      return Scaffold(
        body: body,
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
          ),
          child: NavigationBar(
            selectedIndex: widget.shell.currentIndex,
            onDestinationSelected: _select,
            destinations: [
              for (final (i, d) in _destinations.indexed)
                NavigationDestination(
                  icon: _badged(Icon(d.icon), i == 2 ? unread : 0),
                  selectedIcon: _badged(Icon(d.selectedIcon), i == 2 ? unread : 0),
                  label: d.label,
                ),
            ],
          ),
        ),
      );
    }

    final extended = size == WindowSize.expanded;
    return Scaffold(
      body: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
              ),
            ),
            child: NavigationRail(
              extended: extended,
              minExtendedWidth: 240,
              selectedIndex: widget.shell.currentIndex,
              onDestinationSelected: _select,
              labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.xl),
                child: BrandMark(size: 40, showName: extended),
              ),
              trailing: extended ? const Expanded(child: _RailFooter()) : null,
              destinations: [
                for (final (i, d) in _destinations.indexed)
                  NavigationRailDestination(
                    icon: _badged(Icon(d.icon), i == 2 ? unread : 0),
                    selectedIcon: _badged(Icon(d.selectedIcon), i == 2 ? unread : 0),
                    label: Text(d.label),
                    padding: const EdgeInsets.symmetric(vertical: 2),
                  ),
              ],
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }

  Widget _badged(Widget icon, int count) =>
      Badge(isLabelVisible: count > 0, label: Text('$count'), child: icon);
}

/// Bas du rail étendu : entreprise du client connecté.
class _RailFooter extends ConsumerWidget {
  const _RailFooter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    if (session == null) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: SizedBox(
          width: 208,
          child: Row(
            children: [
              InitialsAvatar(session.company.name.substring(0, 1).toUpperCase(), radius: 18),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.company.name,
                      style: text.titleSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      session.fullName,
                      style: text.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

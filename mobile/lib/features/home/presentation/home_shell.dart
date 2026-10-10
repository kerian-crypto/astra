import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:astra_hub/core/layout/responsive.dart';
import 'package:astra_hub/core/network/realtime.dart';
import 'package:astra_hub/core/router/routes.dart';
import 'package:astra_hub/core/widgets/astra_logo.dart';
import 'package:astra_hub/features/auth/presentation/auth_controller.dart';
import 'package:astra_hub/core/push/push_messaging.dart';
import 'package:astra_hub/core/push/push_service.dart';
import 'package:astra_hub/core/utils/json.dart';
import 'package:astra_hub/features/chat/data/chat.dart';
import 'package:astra_hub/features/chat/data/chat_repository.dart';
import 'package:astra_hub/features/home/data/work.dart';

/// Coque des onglets. N'existe que lorsque le membre est connecté : c'est
/// elle qui ouvre et ferme la connexion temps réel.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> with WidgetsBindingObserver {
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
    // Économise batterie et données en arrière-plan ; resynchronise au retour.
    if (state == AppLifecycleState.paused) {
      unawaited(_realtime.stop());
    } else if (state == AppLifecycleState.resumed) {
      _realtime.start();
      ref
        ..invalidate(channelsProvider)
        ..invalidate(notificationsProvider)
        ..invalidate(dashboardProvider);
    }
  }

  void _onEvent(Json event) {
    final type = event['type'] as String? ?? '';
    if (type.startsWith('message.')) {
      final channelId = event['channel_id'] as String;
      final message = event['message'];
      if (message is Json) {
        ref.read(channelMessagesProvider(channelId).notifier).upsert(ChatMessage.fromJson(message));
      } else {
        ref.invalidate(channelMessagesProvider(channelId));
      }
      ref.invalidate(channelsProvider);
    } else if (type == 'notification.created') {
      ref
        ..invalidate(notificationsProvider)
        ..invalidate(dashboardProvider);
    }
  }

  /// Push touché dans la barre de notifications : ouvre l'écran concerné.
  void _onPushOpened(PushData data) {
    unawaited(ref.read(pushServiceProvider).markOpened(data));
    ref
      ..invalidate(notificationsProvider)
      ..invalidate(dashboardProvider);
    final route = routeForPush(data);
    if (route != null && mounted) unawaited(GoRouter.of(context).push(route));
  }

  @override
  Widget build(BuildContext context) {
    final shell = widget.shell;
    final unreadMessages =
        ref.watch(channelsProvider).value?.fold<int>(0, (sum, c) => sum + c.unreadCount) ?? 0;
    final member = ref.watch(authControllerProvider).value;
    final destinations = [
      (Icons.today_outlined, Icons.today, 'Aujourd\'hui', 0),
      (Icons.folder_outlined, Icons.folder, 'Projets', 0),
      (Icons.chat_bubble_outline, Icons.chat_bubble, 'Messages', unreadMessages),
      (Icons.groups_outlined, Icons.groups, 'Réunions', 0),
      (Icons.person_outline, Icons.person, 'Profil', 0),
    ];
    Widget badged(IconData icon, int count) =>
        Badge(isLabelVisible: count > 0, label: Text('$count'), child: Icon(icon));
    // Un second tap sur l'onglet courant revient à sa racine.
    void select(int index) => shell.goBranch(index, initialLocation: index == shell.currentIndex);

    final size = context.windowSize;
    if (size == WindowSize.compact) {
      return Scaffold(
        body: shell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: select,
          destinations: [
            for (final (icon, selected, label, count) in destinations)
              NavigationDestination(
                icon: badged(icon, count),
                selectedIcon: badged(selected, count),
                label: label,
              ),
          ],
        ),
      );
    }

    // Tablette et grand écran : rail latéral, étendu avec libellés sur grand écran.
    final extended = size == WindowSize.expanded;
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: extended,
            minExtendedWidth: 220,
            selectedIndex: shell.currentIndex,
            onDestinationSelected: select,
            labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: AstraMark(width: extended ? 120 : 44),
            ),
            trailing: member?.canCreateProjects ?? false
                ? Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: extended
                            ? TextButton.icon(
                                onPressed: () => context.push(Routes.clients),
                                icon: const Icon(Icons.storefront_outlined),
                                label: const Text('Espace clients'),
                              )
                            : IconButton(
                                tooltip: 'Espace clients',
                                onPressed: () => context.push(Routes.clients),
                                icon: const Icon(Icons.storefront_outlined),
                              ),
                      ),
                    ),
                  )
                : null,
            destinations: [
              for (final (icon, selected, label, count) in destinations)
                NavigationRailDestination(
                  icon: badged(icon, count),
                  selectedIcon: badged(selected, count),
                  label: Text(label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: shell),
        ],
      ),
    );
  }
}

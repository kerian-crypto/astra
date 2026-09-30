import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:astra_hub/core/network/realtime.dart';
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
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        // Un second tap sur l'onglet courant revient à sa racine.
        onDestinationSelected: (index) =>
            shell.goBranch(index, initialLocation: index == shell.currentIndex),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: 'Aujourd\'hui',
          ),
          const NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: 'Projets',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: unreadMessages > 0,
              label: Text('$unreadMessages'),
              child: const Icon(Icons.chat_bubble_outline),
            ),
            selectedIcon: const Icon(Icons.chat_bubble),
            label: 'Messages',
          ),
          const NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups),
            label: 'Réunions',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profil',
          ),
        ],
      ),
    );
  }
}

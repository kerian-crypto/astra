import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:astra_hub/core/router/routes.dart';
import 'package:astra_hub/features/ai/presentation/ai_screen.dart';
import 'package:astra_hub/features/auth/presentation/auth_controller.dart';
import 'package:astra_hub/features/auth/presentation/login_screen.dart';
import 'package:astra_hub/features/auth/presentation/register_screen.dart';
import 'package:astra_hub/features/auth/presentation/registrations_screen.dart';
import 'package:astra_hub/features/auth/presentation/splash_screen.dart';
import 'package:astra_hub/features/chat/presentation/channels_screen.dart';
import 'package:astra_hub/features/chat/presentation/chat_screen.dart';
import 'package:astra_hub/features/chat/presentation/notifications_screen.dart';
import 'package:astra_hub/features/home/presentation/home_shell.dart';
import 'package:astra_hub/features/home/presentation/today_screen.dart';
import 'package:astra_hub/features/knowledge/presentation/documents_screen.dart';
import 'package:astra_hub/features/knowledge/presentation/health_screen.dart';
import 'package:astra_hub/features/knowledge/presentation/search_screen.dart';
import 'package:astra_hub/features/meetings/presentation/meeting_detail_screen.dart';
import 'package:astra_hub/features/meetings/presentation/meetings_screen.dart';
import 'package:astra_hub/features/profile/presentation/profile_screen.dart';
import 'package:astra_hub/features/projects/presentation/project_detail_screen.dart';
import 'package:astra_hub/features/projects/presentation/projects_screen.dart';
import 'package:astra_hub/features/tasks/presentation/task_detail_screen.dart';

export 'package:astra_hub/core/router/routes.dart';

/// Redirection selon l'état de session. Fonction pure, testable isolément.
@visibleForTesting
String? authRedirect(AsyncValue<Object?> auth, String location) {
  final isPublic =
      location == Routes.splash || location == Routes.login || location == Routes.register;
  // Chargement initial ou erreur réseau : l'écran d'accueil gère l'attente.
  if (auth.isLoading && !auth.hasValue || auth.hasError) {
    return location == Routes.splash ? null : Routes.splash;
  }
  final isLoggedIn = auth.value != null;
  if (!isLoggedIn) {
    return location == Routes.login || location == Routes.register ? null : Routes.login;
  }
  return isPublic ? Routes.today : null;
}

GoRoute _tab(String path, Widget screen, {List<RouteBase> children = const []}) =>
    GoRoute(path: path, builder: (_, _) => screen, routes: children);

GoRoute _detail(String path, Widget Function(String id) build) =>
    GoRoute(path: path, builder: (_, state) => build(state.pathParameters['id']!));

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ValueNotifier<AsyncValue<Object?>>(ref.read(authControllerProvider));
  ref
    ..listen(authControllerProvider, (_, next) => authState.value = next)
    ..onDispose(authState.dispose);

  final router = GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: authState,
    redirect: (_, state) => authRedirect(authState.value, state.matchedLocation),
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: Routes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(path: Routes.register, builder: (_, _) => const RegisterScreen()),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [_tab(Routes.today, const TodayScreen())]),
          StatefulShellBranch(
            routes: [
              _tab(
                Routes.projects,
                const ProjectsScreen(),
                children: [_detail(':id', (id) => ProjectDetailScreen(projectId: id))],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              _tab(
                Routes.messages,
                const ChannelsScreen(),
                children: [_detail(':id', (id) => ChatScreen(channelId: id))],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              _tab(
                Routes.meetings,
                const MeetingsScreen(),
                children: [_detail(':id', (id) => MeetingDetailScreen(meetingId: id))],
              ),
            ],
          ),
          StatefulShellBranch(routes: [_tab(Routes.profile, const ProfileScreen())]),
        ],
      ),
      _detail('/tasks/:id', (id) => TaskDetailScreen(taskId: id)),
      GoRoute(path: Routes.notifications, builder: (_, _) => const NotificationsScreen()),
      GoRoute(path: Routes.search, builder: (_, _) => const SearchScreen()),
      GoRoute(path: Routes.ai, builder: (_, _) => const AiScreen()),
      GoRoute(path: Routes.health, builder: (_, _) => const HealthScreen()),
      GoRoute(path: Routes.registrations, builder: (_, _) => const RegistrationsScreen()),
      GoRoute(path: Routes.documents, builder: (_, _) => const DocumentsScreen(projectId: null)),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

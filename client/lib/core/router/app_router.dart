import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:astra_client/core/router/routes.dart';
import 'package:astra_client/features/auth/presentation/activation_screen.dart';
import 'package:astra_client/features/auth/presentation/auth_controller.dart';
import 'package:astra_client/features/auth/presentation/login_screen.dart';
import 'package:astra_client/features/auth/presentation/register_screen.dart';
import 'package:astra_client/features/auth/presentation/splash_screen.dart';
import 'package:astra_client/features/briefs/presentation/brief_wizard_screen.dart';
import 'package:astra_client/features/briefs/presentation/briefs_screen.dart';
import 'package:astra_client/features/billing/presentation/contracts_screen.dart';
import 'package:astra_client/features/billing/presentation/declare_payment_screen.dart';
import 'package:astra_client/features/billing/presentation/invoice_screen.dart';
import 'package:astra_client/features/billing/presentation/invoices_screen.dart';
import 'package:astra_client/features/billing/presentation/payments_screen.dart';
import 'package:astra_client/features/dashboard/presentation/client_shell.dart';
import 'package:astra_client/features/dashboard/presentation/dashboard_screen.dart';
import 'package:astra_client/features/deliverables/presentation/deliverable_screen.dart';
import 'package:astra_client/features/documents/presentation/documents_screen.dart';
import 'package:astra_client/features/messages/presentation/conversation_screen.dart';
import 'package:astra_client/features/messages/presentation/conversations_screen.dart';
import 'package:astra_client/features/notifications/presentation/notifications_screen.dart';
import 'package:astra_client/features/profile/presentation/more_screen.dart';
import 'package:astra_client/features/profile/presentation/profile_screens.dart';
import 'package:astra_client/features/projects/presentation/project_detail_screen.dart';
import 'package:astra_client/features/projects/presentation/projects_screen.dart';
import 'package:astra_client/features/support/presentation/new_ticket_screen.dart';
import 'package:astra_client/features/support/presentation/ticket_screen.dart';
import 'package:astra_client/features/support/presentation/tickets_screen.dart';

export 'package:astra_client/core/router/routes.dart';

const _publicRoutes = {Routes.splash, Routes.login, Routes.activate, Routes.register};

/// Redirection selon l'état de session. Fonction pure, testable isolément.
@visibleForTesting
String? authRedirect(AsyncValue<Object?> auth, Uri location) {
  final path = location.path;
  // Le lien d'activation reste accessible, connecté ou non.
  if (path == Routes.activate && !(auth.value != null)) return null;
  if (auth.isLoading && !auth.hasValue || auth.hasError) {
    return path == Routes.splash ? null : Routes.splash;
  }
  final isLoggedIn = auth.value != null;
  if (!isLoggedIn) return path == Routes.login || path == Routes.register ? null : Routes.login;
  return _publicRoutes.contains(path) ? Routes.home : null;
}

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
    redirect: (_, state) => authRedirect(authState.value, state.uri),
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: Routes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(path: Routes.register, builder: (_, _) => const RegisterScreen()),
      GoRoute(
        path: Routes.activate,
        builder: (_, state) => ActivationScreen(token: state.uri.queryParameters['token']),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => ClientShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.home, builder: (_, _) => const DashboardScreen())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.projects,
                builder: (_, _) => const ProjectsScreen(),
                routes: [_detail(':id', (id) => ProjectDetailScreen(projectId: id))],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.messages,
                builder: (_, _) => const ConversationsScreen(),
                routes: [_detail(':id', (id) => ConversationScreen(conversationId: id))],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.documents, builder: (_, _) => const DocumentsScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.more, builder: (_, _) => const MoreScreen())],
          ),
        ],
      ),
      _detail('/deliverables/:id', (id) => DeliverableScreen(deliverableId: id)),
      GoRoute(path: Routes.notifications, builder: (_, _) => const NotificationsScreen()),
      GoRoute(
        path: Routes.invoices,
        builder: (_, _) => const InvoicesScreen(),
        routes: [
          _detail(':id', (id) => InvoiceScreen(invoiceId: id)),
          _detail(':id/declare', (id) => DeclarePaymentScreen(invoiceId: id)),
        ],
      ),
      GoRoute(path: Routes.payments, builder: (_, _) => const PaymentsScreen()),
      GoRoute(
        path: Routes.contracts,
        builder: (_, _) => const ContractsScreen(),
        routes: [_detail(':id', (id) => ContractScreen(contractId: id))],
      ),
      GoRoute(
        path: Routes.tickets,
        builder: (_, _) => const TicketsScreen(),
        routes: [
          GoRoute(
            path: 'new',
            builder: (_, state) => NewTicketScreen(projectId: state.uri.queryParameters['project']),
          ),
          _detail(':id', (id) => TicketScreen(ticketId: id)),
        ],
      ),
      GoRoute(path: Routes.profile, builder: (_, _) => const ProfileScreen()),
      GoRoute(path: Routes.company, builder: (_, _) => const CompanyScreen()),
      GoRoute(path: Routes.team, builder: (_, _) => const TeamScreen()),
      GoRoute(path: Routes.security, builder: (_, _) => const SecurityScreen()),
      GoRoute(
        path: Routes.briefs,
        builder: (_, _) => const BriefsScreen(),
        routes: [
          GoRoute(path: 'new', builder: (_, _) => const BriefWizardScreen()),
          _detail(':id', (id) => BriefScreen(briefId: id)),
          _detail(':id/edit', (id) => BriefWizardScreen(briefId: id)),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

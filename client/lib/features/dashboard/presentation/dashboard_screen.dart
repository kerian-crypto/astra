import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:astra_client/core/layout/page_frame.dart';
import 'package:astra_client/core/router/routes.dart';
import 'package:astra_client/core/theme/client_theme.dart';
import 'package:astra_client/core/utils/formatting.dart';
import 'package:astra_client/core/widgets/state_views.dart';
import 'package:astra_client/core/widgets/ui.dart';
import 'package:astra_client/features/auth/presentation/auth_controller.dart';
import 'package:astra_client/features/dashboard/data/dashboard.dart';
import 'package:astra_client/features/documents/presentation/document_tile.dart';
import 'package:astra_client/features/notifications/data/notification_repository.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(dashboardProvider);
    final unread = ref.watch(unreadNotificationsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accueil'),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: () => context.push(Routes.notifications),
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text('$unread'),
              child: const Icon(Icons.notifications_none_rounded),
            ),
          ),
          const SizedBox(width: Space.sm),
        ],
      ),
      body: AsyncView(
        value: dashboard,
        onRetry: () => ref.invalidate(dashboardProvider),
        builder: (data) => FramedListView(
          onRefresh: () => ref.refresh(dashboardProvider.future),
          children: [
            _Greeting(dashboard: data),
            if (data.needsOnboarding) ...[
              const SizedBox(height: Space.lg),
              _OnboardingCard(draftId: data.briefStatus == 'draft' ? data.briefId : null),
            ],
            const SizedBox(height: Space.xl),
            SplitLayout(
              sideWidth: 380,
              main: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ActionsCard(actions: data.actions),
                  const SizedBox(height: Space.lg),
                  _DeadlinesCard(deadlines: data.deadlines),
                ],
              ),
              side: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Metrics(dashboard: data),
                  const SizedBox(height: Space.lg),
                  _RecentDocuments(dashboard: data),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Greeting extends ConsumerWidget {
  const _Greeting({required this.dashboard});

  final Dashboard dashboard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final hour = DateTime.now().hour;
    final hello = hour < 18 ? 'Bonjour' : 'Bonsoir';
    final todo = dashboard.actions.length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Space.xl),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(ClientTheme.radius + 4),
        gradient: const LinearGradient(
          colors: [ClientColors.ink, Color(0xFF0B4F5C), ClientColors.teal],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            dashboard.company.name.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: ClientColors.amber,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: Space.sm),
          Text(
            '$hello ${session?.firstName ?? ''}',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: Space.xs),
          Text(
            todo == 0
                ? 'Tout est à jour. Votre équipe Astra avance sur vos projets.'
                : todo == 1
                ? 'Une action vous attend.'
                : '$todo actions vous attendent.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: const Color(0xCCFFFFFF)),
          ),
        ],
      ),
    );
  }
}

/// « Ce que je dois faire maintenant » (§13.1).
class _ActionsCard extends StatelessWidget {
  const _ActionsCard({required this.actions});

  final List<ActionItem> actions;

  static (IconData, Tone, String) _visual(String kind) => switch (kind) {
    'brief_draft' => (Icons.assignment_outlined, Tone.brand, 'Questionnaire en cours'),
    'validation_required' => (Icons.fact_check_outlined, Tone.warning, 'Validation requise'),
    'payment_due' => (Icons.receipt_long_outlined, Tone.danger, 'Paiement à effectuer'),
    'payment_rejected' => (
      Icons.report_gmailerrorred_outlined,
      Tone.danger,
      'Paiement à justifier',
    ),
    'ticket_reply' => (Icons.support_agent_outlined, Tone.brand, 'Réponse attendue'),
    'new_document' => (Icons.description_outlined, Tone.info, 'Nouveau document'),
    _ => (Icons.circle_outlined, Tone.neutral, ''),
  };

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'À faire maintenant',
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, Space.sm),
      child: actions.isEmpty
          ? const StateMessage(
              icon: Icons.check_circle_outline_rounded,
              title: 'Rien en attente',
              message: 'Vous serez notifié dès qu\'une action sera nécessaire.',
              tone: Tone.success,
              compact: true,
            )
          : Column(
              children: [
                for (final action in actions)
                  _ActionRow(action: action, visual: _visual(action.kind)),
              ],
            ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.action, required this.visual});

  final ActionItem action;
  final (IconData, Tone, String) visual;

  @override
  Widget build(BuildContext context) {
    final (icon, tone, label) = visual;
    final scheme = Theme.of(context).colorScheme;
    final route = Routes.forEntity(action.entityType, action.entityId);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.xs),
      leading: ToneIcon(icon, tone: tone),
      title: Text(action.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [label, if (action.subtitle != null) action.subtitle!].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: scheme.onSurfaceVariant),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: route == null ? null : () => context.push(route),
    );
  }
}

class _DeadlinesCard extends StatelessWidget {
  const _DeadlinesCard({required this.deadlines});

  final List<Deadline> deadlines;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SectionCard(
      title: 'Prochaines échéances',
      child: deadlines.isEmpty
          ? Text(
              'Aucune échéance dans les 60 prochains jours.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            )
          : Column(
              children: [
                for (final deadline in deadlines)
                  InkWell(
                    borderRadius: BorderRadius.circular(ClientTheme.radiusSmall),
                    onTap: () {
                      final route = Routes.forEntity(deadline.entityType, deadline.entityId);
                      if (route != null) context.push(route);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: Space.sm),
                      child: Row(
                        children: [
                          _DateBadge(date: deadline.dueDate),
                          const SizedBox(width: Space.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(deadline.title, style: Theme.of(context).textTheme.titleSmall),
                                Text(
                                  '${_kindLabel(deadline.kind)} · ${formatDue(deadline.dueDate)}',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: deadline.dueDate.isBefore(DateTime.now())
                                        ? scheme.error
                                        : scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  static String _kindLabel(String kind) => switch (kind) {
    'project' => 'Fin de projet',
    'deliverable' => 'Livrable',
    'delivery' => 'Livraison prévue',
    'invoice' => 'Facture',
    _ => 'Échéance',
  };
}

class _DateBadge extends StatelessWidget {
  const _DateBadge({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final parts = formatDateShort(date).split(' ');
    return Container(
      width: 48,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(ClientTheme.radiusSmall),
      ),
      child: Column(
        children: [
          Text(parts.first, style: Theme.of(context).textTheme.titleMedium?.copyWith(height: 1)),
          Text(
            parts.length > 1 ? parts[1].toUpperCase() : '',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.primary),
          ),
        ],
      ),
    );
  }
}

class _Metrics extends StatelessWidget {
  const _Metrics({required this.dashboard});

  final Dashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      MetricTile(
        icon: Icons.work_outline_rounded,
        label: 'Projets actifs · ${dashboard.completedProjects} terminés',
        value: '${dashboard.activeProjects}',
        onTap: () => context.go(Routes.projects),
      ),
      MetricTile(
        icon: Icons.fact_check_outlined,
        label: 'Validations en attente',
        value: '${dashboard.pendingValidations}',
        tone: dashboard.pendingValidations > 0 ? Tone.warning : Tone.neutral,
        onTap: () => context.go(Routes.projects),
      ),
      MetricTile(
        icon: Icons.chat_bubble_outline_rounded,
        label: 'Messages non lus',
        value: '${dashboard.unreadMessages}',
        tone: dashboard.unreadMessages > 0 ? Tone.brand : Tone.neutral,
        onTap: () => context.go(Routes.messages),
      ),
      if (dashboard.pendingInvoices != null)
        MetricTile(
          icon: Icons.receipt_long_outlined,
          label: 'Factures en attente',
          value: '${dashboard.pendingInvoices}',
          tone: (dashboard.pendingInvoices ?? 0) > 0 ? Tone.danger : Tone.neutral,
          onTap: () => context.push(Routes.invoices),
        ),
      if (dashboard.openTickets != null)
        MetricTile(
          icon: Icons.support_agent_outlined,
          label: 'Tickets ouverts',
          value: '${dashboard.openTickets}',
          tone: Tone.info,
          onTap: () => context.push(Routes.tickets),
        ),
    ];
    return ResponsiveGrid(minItemWidth: 180, children: tiles);
  }
}

class _RecentDocuments extends StatelessWidget {
  const _RecentDocuments({required this.dashboard});

  final Dashboard dashboard;

  @override
  Widget build(BuildContext context) {
    if (dashboard.recentDocuments.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          'Documents récents',
          trailing: TextButton(
            onPressed: () => context.go(Routes.documents),
            child: const Text('Tout voir'),
          ),
        ),
        for (final document in dashboard.recentDocuments) ...[
          DocumentTile(document: document),
          const SizedBox(height: Space.sm),
        ],
      ],
    );
  }
}

/// Invitation à décrire son projet (questionnaire de cadrage).
class _OnboardingCard extends StatelessWidget {
  const _OnboardingCard({this.draftId});

  final String? draftId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final resume = draftId != null;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ClientTheme.radius),
        side: BorderSide(color: scheme.primary, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Wrap(
          spacing: Space.lg,
          runSpacing: Space.lg,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const ToneIcon(Icons.assignment_outlined, size: 56),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    resume ? 'Terminez votre cahier des charges' : 'Parlez-nous de votre projet',
                    style: text.titleLarge,
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    'Un questionnaire en 6 étapes pour cadrer précisément votre demande. '
                    'Astra en déduit le plan et les tâches de votre projet.',
                    style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: () => context.push(resume ? Routes.editBrief(draftId!) : Routes.newBrief),
              icon: const Icon(Icons.edit_note_rounded),
              label: Text(resume ? 'Reprendre' : 'Commencer'),
            ),
          ],
        ),
      ),
    );
  }
}

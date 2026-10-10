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
import 'package:astra_client/features/auth/data/session.dart';
import 'package:astra_client/features/auth/presentation/auth_controller.dart';
import 'package:astra_client/features/deliverables/data/deliverable_repository.dart';
import 'package:astra_client/features/deliverables/presentation/deliverable_card.dart';
import 'package:astra_client/features/documents/data/document_repository.dart';
import 'package:astra_client/features/documents/presentation/document_tile.dart';
import 'package:astra_client/features/projects/data/project.dart';
import 'package:astra_client/features/projects/data/project_repository.dart';

class ProjectDetailScreen extends ConsumerWidget {
  const ProjectDetailScreen({required this.projectId, super.key});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(projectProvider(projectId));
    return Scaffold(
      appBar: AppBar(title: Text(project.value?.name ?? 'Projet')),
      body: AsyncView(
        value: project,
        onRetry: () => ref.invalidate(projectProvider(projectId)),
        builder: (data) => FramedListView(
          onRefresh: () async {
            ref
              ..invalidate(deliverablesProvider((projectId: projectId, pendingOnly: false)))
              ..invalidate(documentsProvider((category: null, projectId: projectId)))
              ..invalidate(projectTimelineProvider(projectId))
              ..invalidate(projectProvider(projectId));
            await ref.read(projectProvider(projectId).future);
          },
          children: [
            _Header(project: data),
            const SizedBox(height: Space.lg),
            SplitLayout(
              main: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if ((data.summary ?? data.description) != null)
                    SectionCard(
                      title: 'À propos',
                      child: Text(data.summary ?? data.description ?? ''),
                    ),
                  _Deliverables(projectId: projectId),
                  _Documents(projectId: projectId),
                  _Timeline(projectId: projectId),
                ],
              ),
              side: _SidePanel(project: data),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.project});

  final ProjectDetail project;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                StatusPill(label: project.status.label, tone: project.status.tone),
                if (project.pendingValidations > 0)
                  StatusPill(
                    label: '${project.pendingValidations} à valider',
                    tone: Tone.warning,
                    icon: Icons.fact_check_outlined,
                  ),
              ],
            ),
            const SizedBox(height: Space.md),
            Text(project.name, style: text.headlineSmall),
            const SizedBox(height: Space.lg),
            Text('Avancement', style: text.labelLarge),
            const SizedBox(height: Space.sm),
            ProgressMeter(percent: project.progress, height: 10),
          ],
        ),
      ),
    );
  }
}

class _SidePanel extends ConsumerWidget {
  const _SidePanel({required this.project});

  final ProjectDetail project;

  Future<void> _openConversation(BuildContext context, WidgetRef ref) async {
    try {
      final id =
          project.conversationId ??
          await ref.read(projectRepositoryProvider).openConversation(project.id);
      if (context.mounted) unawaited(context.push(Routes.conversation(id)));
    } on Exception catch (error) {
      if (context.mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final lead = project.lead;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: 'Informations',
          child: Column(
            children: [
              InfoRow('Démarré le', formatDate(project.createdAt)),
              if (project.dueDate != null)
                InfoRow(
                  'Échéance estimée',
                  '${formatDate(project.dueDate!)} · ${formatDue(project.dueDate!)}',
                ),
              InfoRow('Livrables', '${project.deliverableCount}'),
              InfoRow('Documents partagés', '${project.documentCount}'),
            ],
          ),
        ),
        const SizedBox(height: Space.lg),
        if (project.team.isNotEmpty)
          SectionCard(
            title: 'Votre équipe Astra',
            child: Column(
              children: [
                for (final member in project.team)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: InitialsAvatar(
                      initials(member.fullName),
                      tone: member.isLead ? Tone.brand : Tone.neutral,
                    ),
                    title: Text(member.fullName),
                    subtitle: Text(
                      [if (member.isLead) 'Responsable du projet', ?member.jobTitle].join(' · '),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: Space.lg),
        if (session?.can(ClientPermission.sendMessage) ?? false)
          FilledButton.icon(
            onPressed: () => _openConversation(context, ref),
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            label: Text(
              lead == null ? 'Écrire à l\'équipe' : 'Écrire à ${lead.fullName.split(' ').first}',
            ),
          ),
        if (session?.can(ClientPermission.createTicket) ?? false) ...[
          const SizedBox(height: Space.sm),
          OutlinedButton.icon(
            onPressed: () => context.push('${Routes.newTicket}?project=${project.id}'),
            icon: const Icon(Icons.support_agent_outlined),
            label: const Text('Ouvrir une demande'),
          ),
        ],
      ],
    );
  }
}

class _Deliverables extends ConsumerWidget {
  const _Deliverables({required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deliverables = ref.watch(
      deliverablesProvider((projectId: projectId, pendingOnly: false)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Livrables'),
        AsyncView(
          value: deliverables,
          compact: true,
          isEmpty: (list) => list.isEmpty,
          empty: const SectionCard(
            child: StateMessage(
              icon: Icons.inventory_2_outlined,
              title: 'Pas encore de livrable',
              message: 'Les livrables apparaîtront ici dès leur publication.',
              compact: true,
            ),
          ),
          builder: (list) => Column(
            children: [
              for (final d in list) ...[
                DeliverableCard(deliverable: d, showProject: false),
                const SizedBox(height: Space.sm),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Documents extends ConsumerWidget {
  const _Documents({required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    if (!(session?.can(ClientPermission.viewDocument) ?? false)) return const SizedBox.shrink();
    final documents = ref.watch(documentsProvider((category: null, projectId: projectId)));
    return AsyncView(
      value: documents,
      compact: true,
      builder: (list) {
        final shared = list.where((d) => d.source != 'deliverable_version').toList();
        if (shared.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader('Documents'),
            for (final document in shared) ...[
              DocumentTile(document: document),
              const SizedBox(height: Space.sm),
            ],
          ],
        );
      },
    );
  }
}

class _Timeline extends ConsumerWidget {
  const _Timeline({required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(projectTimelineProvider(projectId));
    final scheme = Theme.of(context).colorScheme;
    return AsyncView(
      value: events,
      compact: true,
      builder: (list) {
        if (list.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader('Historique'),
            SectionCard(
              child: Column(
                children: [
                  for (final (i, event) in list.indexed)
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Column(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                margin: const EdgeInsets.only(top: 4),
                                decoration: BoxDecoration(
                                  color: i == 0 ? scheme.primary : scheme.outline,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              if (i < list.length - 1)
                                Expanded(child: Container(width: 2, color: scheme.outlineVariant)),
                            ],
                          ),
                          const SizedBox(width: Space.md),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: Space.lg),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    event.label,
                                    style: Theme.of(context).textTheme.bodyMedium
                                        ?.copyWith(fontWeight: FontWeight.w500),
                                  ),
                                  Text(
                                    '${event.actorName ?? 'Astra'} · ${formatRelative(event.createdAt)}',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(color: scheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

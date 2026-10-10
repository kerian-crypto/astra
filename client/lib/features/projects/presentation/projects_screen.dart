import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:astra_client/core/layout/page_frame.dart';
import 'package:astra_client/core/router/routes.dart';
import 'package:astra_client/core/theme/client_theme.dart';
import 'package:astra_client/core/utils/formatting.dart';
import 'package:astra_client/core/widgets/state_views.dart';
import 'package:astra_client/core/widgets/ui.dart';
import 'package:astra_client/features/projects/data/project.dart';
import 'package:astra_client/features/projects/data/project_repository.dart';

class ProjectsScreen extends ConsumerStatefulWidget {
  const ProjectsScreen({super.key});

  @override
  ConsumerState<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends ConsumerState<ProjectsScreen> {
  bool _showFinished = false;

  @override
  Widget build(BuildContext context) {
    final projects = ref.watch(projectsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Projets')),
      body: AsyncView(
        value: projects,
        onRetry: () => ref.invalidate(projectsProvider),
        isEmpty: (list) => list.isEmpty,
        empty: const StateMessage(
          icon: Icons.work_outline_rounded,
          title: 'Aucun projet disponible',
          message: 'Votre équipe Astra vous informera lorsqu\'un projet sera créé.',
          tone: Tone.brand,
        ),
        builder: (list) {
          final active = list.where((p) => !p.status.isFinished).toList();
          final finished = list.where((p) => p.status.isFinished).toList();
          final shown = _showFinished ? finished : active;
          return FramedListView(
            onRefresh: () => ref.refresh(projectsProvider.future),
            children: [
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: false, label: Text('En cours (${active.length})')),
                  ButtonSegment(value: true, label: Text('Terminés (${finished.length})')),
                ],
                selected: {_showFinished},
                showSelectedIcon: false,
                onSelectionChanged: (value) => setState(() => _showFinished = value.first),
              ),
              const SizedBox(height: Space.lg),
              if (shown.isEmpty)
                StateMessage(
                  icon: Icons.inbox_outlined,
                  title: _showFinished ? 'Aucun projet terminé' : 'Aucun projet en cours',
                  compact: true,
                )
              else
                ResponsiveGrid(
                  minItemWidth: 340,
                  children: [for (final project in shown) ProjectCard(project: project)],
                ),
            ],
          );
        },
      ),
    );
  }
}

class ProjectCard extends StatelessWidget {
  const ProjectCard({required this.project, super.key});

  final ProjectSummary project;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card(
      child: InkWell(
        onTap: () => context.go(Routes.project(project.id)),
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ToneIcon(Icons.work_outline_rounded, tone: project.status.tone, size: 44),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          project.name,
                          style: text.titleMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: Space.xs),
                        StatusPill(label: project.status.label, tone: project.status.tone),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.lg),
              ProgressMeter(percent: project.progress),
              const SizedBox(height: Space.md),
              Wrap(
                spacing: Space.lg,
                runSpacing: Space.xs,
                children: [
                  if (project.dueDate != null)
                    _Meta(Icons.event_outlined, 'Échéance ${formatDate(project.dueDate!)}'),
                  _Meta(Icons.update_rounded, 'Mis à jour ${formatRelative(project.updatedAt)}'),
                  if (project.pendingValidations > 0)
                    Text(
                      '${project.pendingValidations} validation(s) en attente',
                      style: text.labelMedium?.copyWith(color: Tone.warning.foreground(scheme)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

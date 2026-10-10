import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:astra_hub/core/layout/responsive.dart';
import 'package:astra_hub/core/router/routes.dart';
import 'package:astra_hub/core/theme/astra_theme.dart';
import 'package:astra_hub/core/utils/formatting.dart';
import 'package:astra_hub/core/widgets/async_value_view.dart';
import 'package:astra_hub/features/clients/data/brief.dart';
import 'package:astra_hub/features/clients/presentation/client_widgets.dart';
import 'package:astra_hub/features/members/data/member_repository.dart';

/// Lecture d'un cahier des charges client et du plan qui en est déduit.
/// Sur grand écran : réponses à gauche, plan proposé à droite.
class BriefReviewScreen extends ConsumerWidget {
  const BriefReviewScreen({required this.briefId, super.key});

  final String briefId;

  Future<void> _convert(BuildContext context, WidgetRef ref, HubBrief brief) async {
    final members = await ref.read(membersProvider.future);
    if (!context.mounted) return;
    final name = TextEditingController(text: brief.planJson['name'] as String? ?? brief.title);
    String? leadId;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Créer le projet'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${brief.plan.length} phases et ${brief.taskCount} tâches seront créées, '
                'et le projet sera visible par ${brief.companyName}.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Nom du projet'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: leadId,
                decoration: const InputDecoration(labelText: 'Responsable'),
                items: [
                  const DropdownMenuItem(child: Text('Moi')),
                  for (final m in members.where((m) => m.isActive))
                    DropdownMenuItem(value: m.id, child: Text(m.fullName)),
                ],
                onChanged: (value) => setState(() => leadId = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Créer le projet'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      final plan = {
        ...brief.planJson,
        if (name.text.trim().isNotEmpty) 'name': name.text.trim(),
        'lead_id': ?leadId,
      };
      final converted = await ref.read(briefRepositoryProvider).convert(brief.id, plan: plan);
      ref
        ..invalidate(hubBriefProvider(briefId))
        ..invalidate(hubBriefsProvider);
      if (context.mounted && converted.projectId != null) {
        showMessage(context, 'Projet créé et ouvert au client.');
        await context.push(Routes.project(converted.projectId!));
      }
    } on Exception catch (error) {
      if (context.mounted) showMessage(context, error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brief = ref.watch(hubBriefProvider(briefId));
    final questionnaire = ref.watch(briefQuestionnaireProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cahier des charges'),
        actions: [
          if (brief.value?.canConvert ?? false)
            IconButton(
              tooltip: 'Archiver',
              icon: const Icon(Icons.archive_outlined),
              onPressed: () async {
                await ref.read(briefRepositoryProvider).archive(briefId);
                ref.invalidate(hubBriefProvider(briefId));
              },
            ),
        ],
      ),
      floatingActionButton: (brief.value?.canConvert ?? false)
          ? FloatingActionButton.extended(
              onPressed: () => _convert(context, ref, brief.requireValue),
              icon: const Icon(Icons.rocket_launch_outlined),
              label: const Text('Créer le projet'),
            )
          : null,
      body: AsyncValueView(
        value: brief,
        onRetry: () => ref.invalidate(hubBriefProvider(briefId)),
        data: (b) => AsyncValueView(
          value: questionnaire,
          onRetry: () => ref.invalidate(briefQuestionnaireProvider),
          data: (sections) {
            final answers = _Answers(brief: b, sections: sections);
            final plan = _Plan(brief: b);
            return LayoutBuilder(
              builder: (context, constraints) {
                final gutter = Breakpoints.gutter(context);
                final header = _Header(brief: b);
                if (constraints.maxWidth < 1000) {
                  return ResponsiveCenter(
                    maxWidth: Breakpoints.readingMaxWidth,
                    child: ListView(
                      padding: EdgeInsets.all(gutter),
                      children: [header, plan, answers, const SizedBox(height: 80)],
                    ),
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ListView(padding: EdgeInsets.all(gutter), children: [header, answers]),
                    ),
                    SizedBox(
                      width: 420,
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(0, gutter, gutter, 96),
                        children: [plan],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.brief});

  final HubBrief brief;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Pill(brief.status.label, color: brief.status.color),
                if (brief.companySelfRegistered)
                  const Pill(
                    'Prospect inscrit',
                    color: AstraTheme.secondary,
                    icon: Icons.person_add_alt,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(brief.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '${brief.companyName}${brief.authorName != null ? ' · ${brief.authorName}' : ''}'
              '${brief.submittedAt != null ? ' · reçu le ${formatDate(brief.submittedAt!)}' : ''}',
            ),
            if (brief.projectId != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => context.push(Routes.project(brief.projectId!)),
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('Ouvrir le projet'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Plan extends StatelessWidget {
  const _Plan({required this.brief});

  final HubBrief brief;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListSectionTitle('Plan déduit · ${brief.plan.length} phases, ${brief.taskCount} tâches'),
        Text(
          'Proposition générée à partir des réponses. Les tâches restent modifiables dans le '
          'projet une fois créé.',
          style: text.bodySmall,
        ),
        const SizedBox(height: 8),
        for (final phase in brief.plan)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ExpansionTile(
              title: Text(phase.name),
              subtitle: Text(
                '${phase.tasks.length} tâche(s)'
                '${phase.dueDate != null ? ' · échéance ${formatDate(phase.dueDate!)}' : ''}',
              ),
              children: [
                for (final task in phase.tasks)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      task.priority == 'high' ? Icons.priority_high : Icons.check_box_outline_blank,
                      size: 18,
                      color: task.priority == 'high' ? AstraTheme.warning : null,
                    ),
                    title: Text(task.title),
                    subtitle: task.description == null
                        ? null
                        : Text(task.description!, maxLines: 3, overflow: TextOverflow.ellipsis),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Answers extends ConsumerWidget {
  const _Answers({required this.brief, required this.sections});

  final HubBrief brief;
  final List<BriefSection> sections;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final section in sections) ...[
          ListSectionTitle(section.title),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final q in section.questions)
                    if (q.type == 'files'
                        ? brief.files.any((f) => f.questionId == q.id)
                        : brief.answers[q.id] != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              q.label,
                              style: text.labelLarge?.copyWith(color: AstraTheme.textSecondary),
                            ),
                            const SizedBox(height: 4),
                            if (q.type == 'files')
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final f in brief.files.where((f) => f.questionId == q.id))
                                    ActionChip(
                                      avatar: const Icon(Icons.image_outlined, size: 18),
                                      label: Text(f.file.name),
                                      onPressed: () => openClientFile(
                                        context,
                                        ref,
                                        '/clients/briefs/${brief.id}/files/${f.id}',
                                        f.file.name,
                                      ),
                                    ),
                                ],
                              )
                            else
                              SelectableText(q.describe(brief.answers[q.id])),
                          ],
                        ),
                      ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

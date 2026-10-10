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
import 'package:astra_client/features/briefs/data/brief.dart';
import 'package:astra_client/features/briefs/data/brief_repository.dart';
import 'package:astra_client/features/briefs/presentation/question_fields.dart';
import 'package:astra_client/features/documents/presentation/document_tile.dart';

class BriefsScreen extends ConsumerWidget {
  const BriefsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final briefs = ref.watch(briefsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Mes cahiers des charges')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.newBrief),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nouveau projet'),
      ),
      body: AsyncView(
        value: briefs,
        onRetry: () => ref.invalidate(briefsProvider),
        isEmpty: (list) => list.isEmpty,
        empty: StateMessage(
          icon: Icons.assignment_outlined,
          title: 'Décrivez votre projet',
          message: 'Répondez au questionnaire de cadrage : Astra en déduira un plan de projet.',
          tone: Tone.brand,
          action: FilledButton.icon(
            onPressed: () => context.push(Routes.newBrief),
            icon: const Icon(Icons.edit_note_rounded),
            label: const Text('Commencer'),
          ),
        ),
        builder: (list) => FramedListView(
          maxWidth: 860,
          onRefresh: () => ref.refresh(briefsProvider.future),
          children: [
            for (final brief in list)
              Card(
                margin: const EdgeInsets.only(bottom: Space.sm),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: Space.lg,
                    vertical: Space.sm,
                  ),
                  leading: ToneIcon(Icons.assignment_outlined, tone: brief.status.tone),
                  title: Text(brief.title),
                  subtitle: Text(
                    brief.isDraft
                        ? 'Modifié ${formatRelative(brief.updatedAt)}'
                        : 'Transmis le ${formatDate(brief.submittedAt ?? brief.updatedAt)}',
                  ),
                  trailing: BriefStatusPill(brief.status),
                  onTap: () => context.push(
                    brief.isDraft ? Routes.editBrief(brief.id) : Routes.brief(brief.id),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Cahier des charges transmis, en lecture seule.
class BriefScreen extends ConsumerWidget {
  const BriefScreen({required this.briefId, super.key});

  final String briefId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brief = ref.watch(briefProvider(briefId));
    final questionnaire = ref.watch(questionnaireProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Cahier des charges')),
      body: AsyncView(
        value: brief,
        onRetry: () => ref.invalidate(briefProvider(briefId)),
        builder: (b) => AsyncView(
          value: questionnaire,
          builder: (q) => FramedListView(
            maxWidth: 860,
            children: [
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BriefStatusPill(b.status),
                    const SizedBox(height: Space.md),
                    Text(b.title, style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: Space.sm),
                    Text(switch (b.status) {
                      BriefStatus.converted =>
                        'Votre projet a été créé à partir de ce cahier des charges.',
                      BriefStatus.inReview => 'Votre équipe Astra étudie vos réponses.',
                      _ => 'Transmis à Astra. Vous serez notifié dès que le projet sera planifié.',
                    }),
                    if (b.projectId != null) ...[
                      const SizedBox(height: Space.md),
                      FilledButton.icon(
                        onPressed: () => context.go(Routes.project(b.projectId!)),
                        icon: const Icon(Icons.work_outline_rounded),
                        label: const Text('Voir le projet'),
                      ),
                    ],
                  ],
                ),
              ),
              for (final section in q.sections) ...[
                SectionHeader(section.title),
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final question in section.questions)
                        if (question.type == QuestionType.files
                            ? b.filesFor(question.id).isNotEmpty
                            : b.answers[question.id] != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: Space.md),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  question.label,
                                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                if (question.type == QuestionType.files)
                                  for (final file in b.filesFor(question.id))
                                    TextButton.icon(
                                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                                      onPressed: () => unawaited(
                                        openApiFile(
                                          context,
                                          ref,
                                          'client/briefs/${b.id}/files/${file.id}',
                                          file.file.name,
                                        ),
                                      ),
                                      icon: const Icon(Icons.image_outlined, size: 18),
                                      label: Text(file.file.name),
                                    )
                                else
                                  Text(describeAnswer(question, b.answers[question.id])),
                              ],
                            ),
                          ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

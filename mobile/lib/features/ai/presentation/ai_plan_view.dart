import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:astra_hub/core/network/api_exception.dart';
import 'package:astra_hub/core/router/routes.dart';
import 'package:astra_hub/features/ai/data/ai.dart';
import 'package:astra_hub/features/ai/data/ai_repository.dart';
import 'package:astra_hub/features/auth/presentation/auth_controller.dart';
import 'package:astra_hub/features/projects/data/project_repository.dart';
import 'package:astra_hub/features/tasks/presentation/task_widgets.dart';

/// Idée → plan de projet proposé par ASTRA AI → validation humaine (spec §13).
class AiPlanView extends ConsumerStatefulWidget {
  const AiPlanView({super.key});

  @override
  ConsumerState<AiPlanView> createState() => _AiPlanViewState();
}

class _AiPlanViewState extends ConsumerState<AiPlanView> {
  static const _minIdeaLength = 10;

  final _idea = TextEditingController();
  PlanProposal? _proposal;
  bool _isBusy = false;
  String? _error;

  @override
  void dispose() {
    _idea.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _isBusy = true;
      _error = null;
    });
    try {
      await action();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _propose() => _run(() async {
    final proposal = await ref.read(aiRepositoryProvider).proposePlan(_idea.text);
    if (mounted) setState(() => _proposal = proposal);
  });

  Future<void> _apply(PlanProposal proposal) => _run(() async {
    final project = await ref.read(aiRepositoryProvider).applyPlan(proposal.plan);
    ref.invalidate(projectListProvider);
    if (mounted) context.go(Routes.project(project.project.id));
  });

  @override
  Widget build(BuildContext context) {
    final canCreate = ref.watch(authControllerProvider).value?.canCreateProjects ?? false;
    final proposal = _proposal;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _idea,
          minLines: 3,
          maxLines: 8,
          maxLength: 4000,
          decoration: const InputDecoration(
            labelText: 'Décrivez l\'idée',
            hintText: 'Ex. : créer une plateforme web de gestion des formations.',
            alignLabelWithHint: true,
          ),
          onChanged: (_) => setState(() {}),
        ),
        ElevatedButton.icon(
          onPressed: _isBusy || _idea.text.trim().length < _minIdeaLength ? null : _propose,
          icon: const Icon(Icons.auto_awesome),
          label: const Text('Proposer un plan'),
        ),
        if (_isBusy) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
          const Text('Ronda prépare le plan… cela peut prendre quelques minutes.'),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        if (proposal != null) ...[
          SectionTitle(proposal.name),
          if (proposal.objective != null) Text(proposal.objective!),
          const SizedBox(height: 4),
          Text(
            'Charge estimée : ${proposal.estimatedWorkloadDays} jours·personne',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          for (final (index, phase) in proposal.phases.indexed) ...[
            SectionTitle('Phase ${index + 1} — ${phase.name}'),
            for (final task in phase.tasks) Text('• $task'),
          ],
          if (proposal.deliverables.isNotEmpty) ...[
            const SectionTitle('Livrables'),
            for (final d in proposal.deliverables) Text('• $d'),
          ],
          if (proposal.risks.isNotEmpty) ...[
            const SectionTitle('Risques'),
            for (final r in proposal.risks) Text('• $r'),
          ],
          if (proposal.requiredSkills.isNotEmpty) ...[
            const SectionTitle('Compétences nécessaires'),
            Wrap(
              spacing: 8,
              children: [for (final s in proposal.requiredSkills) Chip(label: Text(s))],
            ),
          ],
          const SizedBox(height: 24),
          if (canCreate)
            ElevatedButton(
              onPressed: _isBusy ? null : () => _apply(proposal),
              child: const Text('Valider et créer le projet'),
            )
          else
            const Text(
              'Seuls les managers et administrateurs peuvent créer le projet : '
              'partagez cette proposition avec eux.',
            ),
        ],
      ],
    );
  }
}

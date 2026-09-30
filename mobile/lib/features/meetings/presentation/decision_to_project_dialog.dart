import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:astra_hub/core/network/api_exception.dart';
import 'package:astra_hub/core/router/routes.dart';
import 'package:astra_hub/features/meetings/data/meeting.dart';
import 'package:astra_hub/features/meetings/data/meeting_repository.dart';
import 'package:astra_hub/features/projects/data/project_repository.dart';

/// « Une décision devient immédiatement une action opérationnelle » (spec §9).
Future<void> showDecisionToProjectDialog(BuildContext context, Decision decision) async {
  final projectId = await showDialog<String>(
    context: context,
    builder: (_) => _DecisionToProjectDialog(decision: decision),
  );
  if (projectId != null && context.mounted) context.go(Routes.project(projectId));
}

class _DecisionToProjectDialog extends ConsumerStatefulWidget {
  const _DecisionToProjectDialog({required this.decision});

  final Decision decision;

  @override
  ConsumerState<_DecisionToProjectDialog> createState() => _State();
}

class _State extends ConsumerState<_DecisionToProjectDialog> {
  late final _name = TextEditingController(text: widget.decision.title);
  final _phases = TextEditingController(text: 'Architecture\nBackend\nMobile\nTests');
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phases.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty || _isSubmitting) return;
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      final project = await ref
          .read(meetingRepositoryProvider)
          .decisionToProject(
            widget.decision.id,
            name: _name.text,
            phases: _phases.text.split('\n'),
          );
      ref
        ..invalidate(projectListProvider)
        ..invalidate(meetingDetailProvider(widget.decision.meetingId ?? ''));
      if (mounted) Navigator.pop(context, project.project.id);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Créer le projet'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nom du projet'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phases,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: 'Phases (une par ligne)',
                alignLabelWithHint: true,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(onPressed: _isSubmitting ? null : _submit, child: const Text('Créer')),
      ],
    );
  }
}

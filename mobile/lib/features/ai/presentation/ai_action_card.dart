import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:astra_hub/core/router/routes.dart';
import 'package:astra_hub/features/ai/data/ai.dart';

/// Proposition d'action de Ronda : le membre la valide (exécutée avec ses
/// droits) ou l'écarte. Rien n'est créé avant la validation.
class AiActionCard extends StatefulWidget {
  const AiActionCard({required this.action, required this.onDecide, super.key});

  final AiAction action;
  final Future<void> Function({required bool apply}) onDecide;

  @override
  State<AiActionCard> createState() => _AiActionCardState();
}

class _AiActionCardState extends State<AiActionCard> {
  bool _isBusy = false;

  Future<void> _decide({required bool apply}) async {
    setState(() => _isBusy = true);
    try {
      await widget.onDecide(apply: apply);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  String? get _resultRoute {
    final id = widget.action.resultId;
    if (id == null) return null;
    return switch (widget.action.resultType) {
      'project' => Routes.project(id),
      'meeting' => Routes.meeting(id),
      'task' => Routes.task(id),
      _ => null,
    };
  }

  Widget _footer(BuildContext context) {
    return switch (widget.action.status) {
      AiActionStatus.proposed => Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: _isBusy ? null : () => _decide(apply: false),
            child: const Text('Ignorer'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _isBusy ? null : () => _decide(apply: true),
            child: const Text('Valider'),
          ),
        ],
      ),
      AiActionStatus.applied => Row(
        children: [
          const Icon(Icons.check_circle, size: 18, color: Colors.green),
          const SizedBox(width: 6),
          const Expanded(child: Text('Fait')),
          if (_resultRoute case final route?)
            TextButton(
              // Projets et réunions vivent dans les onglets : `push` depuis
              // l'assistant dupliquerait leurs pages. La conversation reste
              // accessible via le bouton Ronda.
              onPressed: () => widget.action.resultType == 'task'
                  ? unawaited(context.push(route))
                  : context.go(route),
              child: const Text('Ouvrir'),
            ),
        ],
      ),
      AiActionStatus.dismissed => Text(
        'Proposition ignorée',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ronda propose', style: theme.textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(widget.action.title, style: theme.textTheme.titleSmall),
            for (final detail in widget.action.details)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(detail, style: theme.textTheme.bodySmall),
              ),
            const SizedBox(height: 8),
            _footer(context),
          ],
        ),
      ),
    );
  }
}

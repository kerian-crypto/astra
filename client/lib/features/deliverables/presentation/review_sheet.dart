import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_client/core/theme/client_theme.dart';
import 'package:astra_client/core/utils/picked_file.dart';
import 'package:astra_client/core/widgets/state_views.dart';
import 'package:astra_client/features/deliverables/data/deliverable.dart';
import 'package:astra_client/features/deliverables/data/deliverable_repository.dart';

const _reasons = ['Contenu', 'Design / visuel', 'Fonctionnalité', 'Texte / orthographe', 'Autre'];

/// Confirmation d'approbation ou formulaire de demande de modification
/// (motif, commentaire, pièce jointe — §19). Renvoie `true` si envoyé.
Future<bool?> showReviewSheet(
  BuildContext context, {
  required DeliverableDetail deliverable,
  required ReviewAction action,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (_) => _ReviewSheet(deliverable: deliverable, action: action),
  );
}

class _ReviewSheet extends ConsumerStatefulWidget {
  const _ReviewSheet({required this.deliverable, required this.action});

  final DeliverableDetail deliverable;
  final ReviewAction action;

  @override
  ConsumerState<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends ConsumerState<_ReviewSheet> {
  final _comment = TextEditingController();
  String? _reason;
  PickedFile? _attachment;
  bool _sending = false;

  bool get _approve => widget.action == ReviewAction.approve;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _attach() async {
    final file = await pickDocument();
    if (file != null) setState(() => _attachment = file);
  }

  Future<void> _send() async {
    if (!_approve && _reason == null && _comment.text.trim().isEmpty) {
      showError(context, 'Précisez le motif de la modification.');
      return;
    }
    setState(() => _sending = true);
    try {
      await ref
          .read(deliverableRepositoryProvider)
          .review(
            widget.deliverable.id,
            action: widget.action,
            reason: _reason,
            comment: _comment.text,
            attachment: _attachment,
          );
      if (mounted) Navigator.of(context).pop(true);
    } on Exception catch (error) {
      if (mounted) {
        setState(() => _sending = false);
        showError(context, error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final version = widget.deliverable.currentVersion?.number ?? 1;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Space.xl,
        0,
        Space.xl,
        MediaQuery.viewInsetsOf(context).bottom + Space.xl,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _approve ? 'Approuver le livrable' : 'Demander une modification',
              style: text.titleLarge,
            ),
            const SizedBox(height: Space.xs),
            Text('${widget.deliverable.title} · version $version', style: text.bodyMedium),
            const SizedBox(height: Space.xl),
            if (!_approve) ...[
              Text('Motif', style: text.labelLarge),
              const SizedBox(height: Space.sm),
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  for (final reason in _reasons)
                    ChoiceChip(
                      label: Text(reason),
                      selected: _reason == reason,
                      onSelected: (selected) => setState(() => _reason = selected ? reason : null),
                    ),
                ],
              ),
              const SizedBox(height: Space.lg),
            ],
            TextField(
              controller: _comment,
              minLines: 3,
              maxLines: 6,
              maxLength: 2000,
              decoration: InputDecoration(
                labelText: _approve
                    ? 'Commentaire (facultatif)'
                    : 'Décrivez la modification souhaitée',
                alignLabelWithHint: true,
              ),
            ),
            if (!_approve) ...[
              OutlinedButton.icon(
                onPressed: _sending ? null : _attach,
                icon: const Icon(Icons.attach_file_rounded),
                label: Text(_attachment?.name ?? 'Joindre une pièce (capture, document…)'),
              ),
              const SizedBox(height: Space.lg),
            ],
            if (_approve)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.lg),
                child: Text(
                  'Votre validation est enregistrée et horodatée. Elle sera visible par votre équipe Astra.',
                  style: text.bodySmall,
                ),
              ),
            FilledButton(
              onPressed: _sending ? null : _send,
              child: _sending
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : Text(_approve ? 'Confirmer l\'approbation' : 'Envoyer la demande'),
            ),
          ],
        ),
      ),
    );
  }
}

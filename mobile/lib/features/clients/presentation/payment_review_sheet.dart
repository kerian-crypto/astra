import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_hub/core/theme/astra_theme.dart';
import 'package:astra_hub/core/utils/formatting.dart';
import 'package:astra_hub/features/clients/data/clients.dart';
import 'package:astra_hub/features/clients/data/clients_repository.dart';
import 'package:astra_hub/features/clients/presentation/client_widgets.dart';

/// Vérification d'un paiement déclaré par un client : jamais confirmé
/// automatiquement, un refus est toujours motivé (§30-31).
Future<void> showPaymentReviewSheet(BuildContext context, PaymentDeclaration declaration) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (_) => _PaymentReviewSheet(declaration: declaration),
  );
}

class _PaymentReviewSheet extends ConsumerStatefulWidget {
  const _PaymentReviewSheet({required this.declaration});

  final PaymentDeclaration declaration;

  @override
  ConsumerState<_PaymentReviewSheet> createState() => _PaymentReviewSheetState();
}

class _PaymentReviewSheetState extends ConsumerState<_PaymentReviewSheet> {
  late final _amount = TextEditingController(text: widget.declaration.amount.toStringAsFixed(0));
  final _reason = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _review({required bool confirm}) async {
    if (!confirm && _reason.text.trim().isEmpty) {
      showMessage(context, 'Indiquez le motif du refus : le client doit savoir quoi corriger.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(clientsRepositoryProvider)
          .reviewDeclaration(
            widget.declaration.id,
            confirm: confirm,
            confirmedAmount: confirm
                ? double.tryParse(_amount.text.replaceAll(' ', '').replaceAll(',', '.'))
                : null,
            rejectionReason: confirm ? null : _reason.text.trim(),
          );
      ref.invalidate(pendingDeclarationsProvider);
      if (mounted) {
        Navigator.pop(context);
        showMessage(
          context,
          confirm ? 'Paiement confirmé, le client est notifié.' : 'Refus envoyé au client.',
        );
      }
    } on Exception catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        showMessage(context, error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.declaration;
    final proof = d.proof;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Vérifier le paiement', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text('${d.companyName} · facture ${d.invoiceNumber}'),
            Text(
              '${formatMoney(d.amount, d.currency)} · ${paymentMethodLabels[d.method] ?? d.method}',
            ),
            Text(
              'Payé le ${formatDate(d.paidOn)}${d.reference != null ? ' · réf. ${d.reference}' : ''}',
            ),
            if (d.declaredByName != null) Text('Déclaré par ${d.declaredByName}'),
            if (d.note != null) ...[const SizedBox(height: 8), Text('« ${d.note} »')],
            const SizedBox(height: 12),
            if (proof != null)
              OutlinedButton.icon(
                onPressed: () => openClientFile(
                  context,
                  ref,
                  '/clients/payment-declarations/${d.id}/proof',
                  proof.name,
                ),
                icon: const Icon(Icons.receipt_outlined),
                label: Text('Voir la preuve · ${proof.name}', overflow: TextOverflow.ellipsis),
              )
            else
              const Text(
                'Aucune preuve jointe : vérifiez la référence de transaction.',
                style: TextStyle(color: AstraTheme.warning),
              ),
            const Divider(height: 32),
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Montant reçu',
                suffixText: d.currency == 'XOF' ? 'FCFA' : d.currency,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : () => _review(confirm: true),
              icon: const Icon(Icons.verified_outlined),
              label: const Text('Confirmer la réception'),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _reason,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Motif du refus',
                hintText:
                    'Ex. La preuve transmise est illisible. Merci d\'envoyer une preuve complète.',
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: AstraTheme.error),
              onPressed: _busy ? null : () => _review(confirm: false),
              icon: const Icon(Icons.block),
              label: const Text('Refuser le paiement'),
            ),
          ],
        ),
      ),
    );
  }
}

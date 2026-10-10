import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:astra_client/core/layout/breakpoints.dart';
import 'package:astra_client/core/layout/page_frame.dart';
import 'package:astra_client/core/theme/client_theme.dart';
import 'package:astra_client/core/utils/formatting.dart';
import 'package:astra_client/core/utils/picked_file.dart';
import 'package:astra_client/core/widgets/state_views.dart';
import 'package:astra_client/core/widgets/ui.dart';
import 'package:astra_client/features/billing/data/billing.dart';
import 'package:astra_client/features/billing/data/billing_repository.dart';
import 'package:astra_client/features/billing/presentation/invoice_screen.dart';
import 'package:astra_client/features/dashboard/data/dashboard.dart';

/// Déclaration d'un paiement effectué hors de l'application (§28-29).
class DeclarePaymentScreen extends ConsumerWidget {
  const DeclarePaymentScreen({required this.invoiceId, super.key});

  final String invoiceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(invoiceProvider(invoiceId));
    return Scaffold(
      appBar: AppBar(title: const Text('Déclarer un paiement')),
      body: AsyncView(
        value: detail,
        onRetry: () => ref.invalidate(invoiceProvider(invoiceId)),
        builder: (d) => _DeclarationForm(invoice: d.invoice),
      ),
    );
  }
}

class _DeclarationForm extends ConsumerStatefulWidget {
  const _DeclarationForm({required this.invoice});

  final Invoice invoice;

  @override
  ConsumerState<_DeclarationForm> createState() => _DeclarationFormState();
}

class _DeclarationFormState extends ConsumerState<_DeclarationForm> {
  final _formKey = GlobalKey<FormState>();
  late final _amount = TextEditingController(
    text: widget.invoice.remainingAmount.toStringAsFixed(widget.invoice.currency == 'XOF' ? 0 : 2),
  );
  final _reference = TextEditingController();
  final _note = TextEditingController();
  PaymentMethod _method = PaymentMethod.bankTransfer;
  DateTime _paidOn = DateTime.now();
  PickedFile? _proof;
  bool _sending = false;

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _note.dispose();
    super.dispose();
  }

  double? get _parsedAmount =>
      double.tryParse(_amount.text.replaceAll(' ', '').replaceAll(',', '.'));

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _paidOn,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _paidOn = picked);
  }

  Future<void> _pickProof({required bool camera}) async {
    final file = camera
        ? await takePhoto()
        : await pickDocument(extensions: const ['pdf', 'png', 'jpg', 'jpeg']);
    if (file != null) setState(() => _proof = file);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_proof == null && _reference.text.trim().isEmpty) {
      showError(context, 'Joignez une preuve ou indiquez la référence de la transaction.');
      return;
    }
    setState(() => _sending = true);
    try {
      await ref
          .read(billingRepositoryProvider)
          .declarePayment(
            widget.invoice.id,
            amount: _parsedAmount!,
            paidOn: _paidOn,
            method: _method,
            reference: _reference.text,
            note: _note.text,
            proof: _proof,
          );
      ref
        ..invalidate(invoiceProvider(widget.invoice.id))
        ..invalidate(invoicesProvider)
        ..invalidate(declarationsProvider)
        ..invalidate(dashboardProvider);
      if (!mounted) return;
      showSuccess(context, 'Paiement déclaré. Astra va le vérifier et vous tiendra informé.');
      context.pop();
    } on Exception catch (error) {
      if (mounted) {
        setState(() => _sending = false);
        showError(context, error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final invoice = widget.invoice;
    final text = Theme.of(context).textTheme;
    return Form(
      key: _formKey,
      child: FramedListView(
        maxWidth: Breakpoints.formMaxWidth,
        children: [
          SectionCard(
            child: Column(
              children: [
                InfoRow('Facture', '#${invoice.number}'),
                InfoRow('Montant de la facture', formatMoney(invoice.amount, invoice.currency)),
                InfoRow(
                  'Reste à payer',
                  formatMoney(invoice.remainingAmount, invoice.currency),
                  emphasize: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.lg),
          const NoOnlinePaymentNotice(),
          const SizedBox(height: Space.xl),
          TextFormField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 ,.]'))],
            decoration: InputDecoration(
              labelText: 'Montant payé',
              suffixText: invoice.currency == 'XOF' ? 'FCFA' : invoice.currency,
            ),
            validator: (_) {
              final amount = _parsedAmount;
              if (amount == null || amount <= 0) return 'Indiquez le montant payé.';
              if (amount > invoice.remainingAmount + 0.001) {
                return 'Le montant dépasse le reste à payer.';
              }
              return null;
            },
          ),
          const SizedBox(height: Space.lg),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(ClientTheme.radiusSmall),
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Date du paiement',
                suffixIcon: Icon(Icons.event_outlined),
              ),
              child: Text(formatDate(_paidOn)),
            ),
          ),
          const SizedBox(height: Space.lg),
          DropdownButtonFormField<PaymentMethod>(
            isExpanded: true,
            initialValue: _method,
            decoration: const InputDecoration(labelText: 'Méthode'),
            items: [
              for (final m in PaymentMethod.values)
                DropdownMenuItem(value: m, child: Text(m.label)),
            ],
            onChanged: (value) => setState(() => _method = value ?? _method),
          ),
          const SizedBox(height: Space.lg),
          TextFormField(
            controller: _reference,
            maxLength: 120,
            decoration: const InputDecoration(
              labelText: 'Référence de transaction',
              hintText: 'Ex. numéro de virement ou de transaction Mobile Money',
            ),
          ),
          const SizedBox(height: Space.sm),
          Text('Preuve de paiement', style: text.labelLarge),
          const SizedBox(height: Space.sm),
          if (_proof != null)
            Card(
              child: ListTile(
                leading: const ToneIcon(Icons.attach_file_rounded, tone: Tone.success),
                title: Text(_proof!.name, overflow: TextOverflow.ellipsis),
                subtitle: _proof!.size == null ? null : Text(formatFileSize(_proof!.size!)),
                trailing: IconButton(
                  tooltip: 'Retirer',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => setState(() => _proof = null),
                ),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickProof(camera: false),
                    icon: const Icon(Icons.upload_file_rounded),
                    label: const Text('Fichier'),
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickProof(camera: true),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Photo'),
                  ),
                ),
              ],
            ),
          const SizedBox(height: Space.lg),
          TextFormField(
            controller: _note,
            minLines: 2,
            maxLines: 4,
            maxLength: 2000,
            decoration: const InputDecoration(
              labelText: 'Commentaire (facultatif)',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: Space.xl),
          FilledButton.icon(
            onPressed: _sending ? null : _submit,
            icon: _sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded),
            label: const Text('Envoyer la déclaration'),
          ),
        ],
      ),
    );
  }
}

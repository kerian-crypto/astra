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
import 'package:astra_client/features/billing/data/billing.dart';
import 'package:astra_client/features/billing/data/billing_repository.dart';
import 'package:astra_client/features/documents/presentation/document_tile.dart';

class InvoiceScreen extends ConsumerWidget {
  const InvoiceScreen({required this.invoiceId, super.key});

  final String invoiceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(invoiceProvider(invoiceId));
    return Scaffold(
      appBar: AppBar(
        title: Text(detail.value == null ? 'Facture' : '#${detail.value!.invoice.number}'),
      ),
      body: AsyncView(
        value: detail,
        onRetry: () => ref.invalidate(invoiceProvider(invoiceId)),
        builder: (d) => FramedListView(
          onRefresh: () => ref.refresh(invoiceProvider(invoiceId).future),
          children: [
            SplitLayout(
              main: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _InvoiceSummary(invoice: d.invoice),
                  if (d.declarations.isNotEmpty) ...[
                    const SectionHeader('Paiements déclarés'),
                    for (final declaration in d.declarations) ...[
                      DeclarationCard(declaration: declaration),
                      const SizedBox(height: Space.sm),
                    ],
                  ],
                ],
              ),
              side: _InvoiceActions(detail: d),
            ),
          ],
        ),
      ),
    );
  }
}

class _InvoiceSummary extends StatelessWidget {
  const _InvoiceSummary({required this.invoice});

  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                StatusPill(
                  label: invoice.cancelled
                      ? 'Annulée'
                      : invoice.isOverdue
                      ? 'En retard'
                      : invoice.paymentStatus.label,
                  tone: invoice.cancelled
                      ? Tone.neutral
                      : invoice.isOverdue
                      ? Tone.danger
                      : invoice.paymentStatus.tone,
                ),
              ],
            ),
            const SizedBox(height: Space.md),
            Text(invoice.title, style: text.headlineSmall),
            const SizedBox(height: Space.lg),
            Text(formatMoney(invoice.amount, invoice.currency), style: text.displaySmall),
            const SizedBox(height: Space.lg),
            ProgressMeter(percent: (invoice.paidRatio * 100).round()),
            const SizedBox(height: Space.lg),
            InfoRow('Montant payé', formatMoney(invoice.paidAmount, invoice.currency)),
            InfoRow(
              'Reste à payer',
              formatMoney(invoice.remainingAmount, invoice.currency),
              emphasize: true,
            ),
            const Divider(height: Space.xl),
            InfoRow('Date d\'émission', formatDate(invoice.issueDate)),
            if (invoice.dueDate != null) InfoRow('Échéance', formatDate(invoice.dueDate!)),
            if (invoice.projectName != null) InfoRow('Projet', invoice.projectName!),
          ],
        ),
      ),
    );
  }
}

class _InvoiceActions extends ConsumerWidget {
  const _InvoiceActions({required this.detail});

  final InvoiceDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoice = detail.invoice;
    final file = invoice.file;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (file != null)
          OutlinedButton.icon(
            onPressed: () => unawaited(
              openApiFile(context, ref, 'client/invoices/${invoice.id}/download', file.name),
            ),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Télécharger la facture'),
          ),
        if (detail.canDeclare) ...[
          const SizedBox(height: Space.md),
          FilledButton.icon(
            onPressed: () => context.push(Routes.declarePayment(invoice.id)),
            icon: const Icon(Icons.task_alt_rounded),
            label: const Text('Déclarer un paiement'),
          ),
        ],
        const SizedBox(height: Space.lg),
        const NoOnlinePaymentNotice(),
      ],
    );
  }
}

/// Rappel (§27) : aucun paiement n'est effectué dans l'application.
class NoOnlinePaymentNotice extends StatelessWidget {
  const NoOnlinePaymentNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: Tone.info.background(scheme),
        borderRadius: BorderRadius.circular(ClientTheme.radius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: Tone.info.foreground(scheme)),
          const SizedBox(width: Space.md),
          Expanded(
            child: Text(
              'Aucun paiement n\'est effectué dans l\'application. Réglez par votre moyen '
              'habituel (virement, Mobile Money…), puis déclarez le paiement avec sa preuve : '
              'Astra le vérifiera et vous confirmera sa réception.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Tone.info.foreground(scheme)),
            ),
          ),
        ],
      ),
    );
  }
}

class DeclarationCard extends ConsumerWidget {
  const DeclarationCard({required this.declaration, this.showInvoice = false, super.key});

  final PaymentDeclaration declaration;
  final bool showInvoice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final proof = declaration.proof;
    final (icon, tone) = switch (declaration.status) {
      DeclarationStatus.confirmed => (Icons.verified_rounded, Tone.success),
      DeclarationStatus.rejected => (Icons.report_gmailerrorred_rounded, Tone.danger),
      _ => (Icons.hourglass_top_rounded, Tone.info),
    };
    return Card(
      child: InkWell(
        onTap: showInvoice ? () => context.push(Routes.invoice(declaration.invoiceId)) : null,
        child: Padding(
          padding: const EdgeInsets.all(Space.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ToneIcon(icon, tone: tone),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            formatMoney(
                              declaration.confirmedAmount ?? declaration.amount,
                              declaration.currency,
                            ),
                            style: text.titleSmall,
                          ),
                        ),
                        StatusPill(label: declaration.status.label, tone: declaration.status.tone),
                      ],
                    ),
                    Text(
                      [
                        if (showInvoice) 'Facture #${declaration.invoiceNumber}',
                        declaration.method.label,
                        'payé le ${formatDate(declaration.paidOn)}',
                        if (declaration.reference != null) 'réf. ${declaration.reference}',
                      ].join(' · '),
                      style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    if (declaration.status == DeclarationStatus.rejected &&
                        declaration.rejectionReason != null) ...[
                      const SizedBox(height: Space.sm),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(Space.sm),
                        decoration: BoxDecoration(
                          color: Tone.danger.background(scheme),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Motif : ${declaration.rejectionReason}',
                          style: text.bodySmall?.copyWith(color: scheme.error),
                        ),
                      ),
                    ],
                    if (proof != null)
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => unawaited(
                          openApiFile(
                            context,
                            ref,
                            'client/payment-declarations/${declaration.id}/proof',
                            proof.name,
                          ),
                        ),
                        icon: const Icon(Icons.attach_file_rounded, size: 18),
                        label: Text('Preuve : ${proof.name}', overflow: TextOverflow.ellipsis),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

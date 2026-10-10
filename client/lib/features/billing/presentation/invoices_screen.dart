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

class InvoicesScreen extends ConsumerWidget {
  const InvoicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoices = ref.watch(invoicesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Factures'),
        actions: [
          TextButton.icon(
            onPressed: () => context.push(Routes.payments),
            icon: const Icon(Icons.history_rounded),
            label: const Text('Paiements'),
          ),
          const SizedBox(width: Space.sm),
        ],
      ),
      body: AsyncView(
        value: invoices,
        onRetry: () => ref.invalidate(invoicesProvider),
        isEmpty: (list) => list.isEmpty,
        empty: const StateMessage(
          icon: Icons.receipt_long_outlined,
          title: 'Aucune facture',
          message: 'Vos factures Astra apparaîtront ici.',
        ),
        builder: (list) {
          final active = list.where((i) => !i.cancelled).toList();
          final open = active.where((i) => i.paymentStatus != PaymentStatus.confirmed).toList();
          final currency = active.isEmpty ? 'XOF' : active.first.currency;
          final due = open
              .where((i) => i.currency == currency)
              .fold<double>(0, (s, i) => s + i.remainingAmount);
          return FramedListView(
            maxWidth: 960,
            onRefresh: () => ref.refresh(invoicesProvider.future),
            children: [
              ResponsiveGrid(
                minItemWidth: 240,
                children: [
                  MetricTile(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'Reste à payer',
                    value: formatMoney(due, currency),
                    tone: due > 0 ? Tone.danger : Tone.success,
                  ),
                  MetricTile(
                    icon: Icons.pending_actions_outlined,
                    label: 'Factures en attente',
                    value: '${open.length}',
                    tone: open.isEmpty ? Tone.neutral : Tone.warning,
                  ),
                ],
              ),
              const SectionHeader('Toutes les factures'),
              for (final invoice in list) ...[
                InvoiceCard(invoice: invoice),
                const SizedBox(height: Space.sm),
              ],
            ],
          );
        },
      ),
    );
  }
}

class InvoiceCard extends StatelessWidget {
  const InvoiceCard({required this.invoice, super.key});

  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final status = invoice.cancelled
        ? const StatusPill(label: 'Annulée', tone: Tone.neutral)
        : StatusPill(
            label: invoice.isOverdue ? 'En retard' : invoice.paymentStatus.label,
            tone: invoice.isOverdue ? Tone.danger : invoice.paymentStatus.tone,
          );
    return Card(
      child: InkWell(
        onTap: () => context.push(Routes.invoice(invoice.id)),
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '#${invoice.number}',
                          style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        Text(invoice.title, style: text.titleSmall),
                      ],
                    ),
                  ),
                  Text(formatMoney(invoice.amount, invoice.currency), style: text.titleMedium),
                ],
              ),
              const SizedBox(height: Space.md),
              if (!invoice.cancelled &&
                  invoice.paidAmount > 0 &&
                  invoice.paymentStatus != PaymentStatus.confirmed) ...[
                ProgressMeter(percent: (invoice.paidRatio * 100).round(), height: 6),
                const SizedBox(height: Space.sm),
              ],
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  status,
                  Text(
                    [
                      'Émise le ${formatDate(invoice.issueDate)}',
                      if (invoice.dueDate != null) 'échéance ${formatDate(invoice.dueDate!)}',
                    ].join(' · '),
                    style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
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

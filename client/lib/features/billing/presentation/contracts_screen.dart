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

class ContractsScreen extends ConsumerWidget {
  const ContractsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contracts = ref.watch(contractsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Contrats')),
      body: AsyncView(
        value: contracts,
        onRetry: () => ref.invalidate(contractsProvider),
        isEmpty: (list) => list.isEmpty,
        empty: const StateMessage(
          icon: Icons.handshake_outlined,
          title: 'Aucun contrat',
          message: 'Vos contrats avec Astra apparaîtront ici.',
        ),
        builder: (list) => FramedListView(
          onRefresh: () => ref.refresh(contractsProvider.future),
          children: [
            ResponsiveGrid(
              minItemWidth: 380,
              children: [for (final contract in list) _ContractCard(contract: contract)],
            ),
          ],
        ),
      ),
    );
  }
}

class _ContractCard extends StatelessWidget {
  const _ContractCard({required this.contract});

  final Contract contract;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final period = [
      if (contract.startDate != null) 'du ${formatDate(contract.startDate!)}',
      if (contract.endDate != null) 'au ${formatDate(contract.endDate!)}',
    ].join(' ');
    return Card(
      child: InkWell(
        onTap: () => context.push(Routes.contract(contract.id)),
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Row(
            children: [
              ToneIcon(Icons.handshake_outlined, tone: contract.status.tone, size: 44),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(contract.title, style: Theme.of(context).textTheme.titleSmall),
                    Text(
                      [contract.number, if (period.isNotEmpty) period].join(' · '),
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: Space.xs),
                    Wrap(
                      spacing: Space.sm,
                      children: [
                        StatusPill(label: contract.status.label, tone: contract.status.tone),
                        if (contract.isExpiringSoon)
                          const StatusPill(
                            label: 'Expire bientôt',
                            tone: Tone.warning,
                            icon: Icons.schedule_rounded,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class ContractScreen extends ConsumerWidget {
  const ContractScreen({required this.contractId, super.key});

  final String contractId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contract = ref.watch(contractProvider(contractId));
    return Scaffold(
      appBar: AppBar(title: const Text('Contrat')),
      body: AsyncView(
        value: contract,
        onRetry: () => ref.invalidate(contractProvider(contractId)),
        builder: (c) => FramedListView(
          maxWidth: 860,
          children: [
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: StatusPill(label: c.status.label, tone: c.status.tone),
                  ),
                  const SizedBox(height: Space.md),
                  Text(c.title, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: Space.lg),
                  InfoRow('Numéro', c.number),
                  if (c.projectName != null) InfoRow('Projet', c.projectName!),
                  if (c.startDate != null) InfoRow('Début', formatDate(c.startDate!)),
                  if (c.endDate != null) InfoRow('Fin', formatDate(c.endDate!)),
                  if (c.amount != null)
                    InfoRow('Montant', formatMoney(c.amount!, c.currency), emphasize: true),
                  if (c.renewalTerms != null) InfoRow('Renouvellement', c.renewalTerms!),
                ],
              ),
            ),
            if (c.services != null) ...[
              const SizedBox(height: Space.lg),
              SectionCard(title: 'Prestations', child: Text(c.services!)),
            ],
            if (c.paymentSchedule != null) ...[
              const SizedBox(height: Space.lg),
              SectionCard(title: 'Échéancier', child: Text(c.paymentSchedule!)),
            ],
            if (c.file != null) ...[
              const SizedBox(height: Space.lg),
              FilledButton.tonalIcon(
                onPressed: () => unawaited(
                  openApiFile(context, ref, 'client/contracts/${c.id}/download', c.file!.name),
                ),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Télécharger le contrat'),
              ),
            ],
            const SizedBox(height: Space.lg),
            Text(
              'Les modifications contractuelles se font avec votre interlocuteur Astra.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

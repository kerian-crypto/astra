import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:astra_client/core/layout/page_frame.dart';
import 'package:astra_client/core/router/routes.dart';
import 'package:astra_client/core/theme/client_theme.dart';
import 'package:astra_client/core/utils/formatting.dart';
import 'package:astra_client/core/widgets/state_views.dart';
import 'package:astra_client/core/widgets/ui.dart';
import 'package:astra_client/features/support/data/ticket.dart';
import 'package:astra_client/features/support/data/ticket_repository.dart';

class TicketsScreen extends ConsumerWidget {
  const TicketsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tickets = ref.watch(ticketsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Support')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.newTicket),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nouvelle demande'),
      ),
      body: AsyncView(
        value: tickets,
        onRetry: () => ref.invalidate(ticketsProvider),
        isEmpty: (list) => list.isEmpty,
        empty: const StateMessage(
          icon: Icons.support_agent_outlined,
          title: 'Aucune demande',
          message:
              'Une question, un problème, un document à demander ? '
              'Créez une demande, votre équipe Astra la prendra en charge.',
          tone: Tone.brand,
        ),
        builder: (list) {
          final open = list.where((t) => t.status.isOpen).toList();
          final closed = list.where((t) => !t.status.isOpen).toList();
          return FramedListView(
            maxWidth: 900,
            onRefresh: () => ref.refresh(ticketsProvider.future),
            children: [
              if (open.isNotEmpty) ...[
                SectionHeader('En cours (${open.length})'),
                for (final ticket in open) ...[
                  TicketCard(ticket: ticket),
                  const SizedBox(height: Space.sm),
                ],
              ],
              if (closed.isNotEmpty) ...[
                SectionHeader('Terminées (${closed.length})'),
                for (final ticket in closed) ...[
                  TicketCard(ticket: ticket),
                  const SizedBox(height: Space.sm),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

class TicketCard extends StatelessWidget {
  const TicketCard({required this.ticket, super.key});

  final Ticket ticket;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        onTap: () => context.push(Routes.ticket(ticket.id)),
        child: Padding(
          padding: const EdgeInsets.all(Space.md),
          child: Row(
            children: [
              ToneIcon(ticket.type.icon, tone: ticket.status.tone, size: 44),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '#${ticket.number}',
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    Text(ticket.subject, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: Space.xs),
                    Wrap(
                      spacing: Space.sm,
                      runSpacing: Space.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        StatusPill(label: ticket.status.label, tone: ticket.status.tone),
                        Text(
                          '${ticket.type.label} · ${formatRelative(ticket.updatedAt)}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
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

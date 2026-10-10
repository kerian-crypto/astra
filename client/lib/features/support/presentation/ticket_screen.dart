import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_client/core/layout/breakpoints.dart';
import 'package:astra_client/core/theme/client_theme.dart';
import 'package:astra_client/core/utils/formatting.dart';
import 'package:astra_client/core/widgets/state_views.dart';
import 'package:astra_client/core/widgets/ui.dart';
import 'package:astra_client/features/messages/presentation/conversation_pane.dart';
import 'package:astra_client/features/support/data/ticket.dart';
import 'package:astra_client/features/support/data/ticket_repository.dart';

/// Ticket et sa conversation. Grand écran : fiche à gauche, échanges à droite.
class TicketScreen extends ConsumerWidget {
  const TicketScreen({required this.ticketId, super.key});

  final String ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticket = ref.watch(ticketProvider(ticketId));
    return Scaffold(
      appBar: AppBar(title: Text(ticket.value == null ? 'Demande' : '#${ticket.value!.number}')),
      body: AsyncView(
        value: ticket,
        onRetry: () => ref.invalidate(ticketProvider(ticketId)),
        builder: (t) {
          final details = _TicketDetails(ticket: t);
          final conversationId = t.conversationId;
          final thread = conversationId == null
              ? const SizedBox.shrink()
              : ConversationPane(conversationId: conversationId);
          if (context.windowSize == WindowSize.compact) {
            return Column(
              children: [
                ExpansionTile(
                  initiallyExpanded: false,
                  title: Text(t.subject, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Align(
                    alignment: Alignment.centerLeft,
                    child: StatusPill(label: t.status.label, tone: t.status.tone),
                  ),
                  children: [Padding(padding: const EdgeInsets.all(Space.lg), child: details)],
                ),
                const Divider(),
                Expanded(child: thread),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 380,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(Space.xl),
                  child: details,
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: thread),
            ],
          );
        },
      ),
    );
  }
}

class _TicketDetails extends StatelessWidget {
  const _TicketDetails({required this.ticket});

  final Ticket ticket;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StatusPill(label: ticket.status.label, tone: ticket.status.tone),
        const SizedBox(height: Space.md),
        Text(ticket.subject, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: Space.md),
        Text(ticket.description),
        const SizedBox(height: Space.lg),
        InfoRow('Type', ticket.type.label),
        InfoRow('Priorité', ticket.priority.label),
        if (ticket.projectName != null) InfoRow('Projet', ticket.projectName!),
        if (ticket.createdByName != null) InfoRow('Créée par', ticket.createdByName!),
        InfoRow('Créée le', formatDateTime(ticket.createdAt)),
        if (ticket.status == TicketStatus.waitingClient) ...[
          const SizedBox(height: Space.lg),
          Container(
            padding: const EdgeInsets.all(Space.md),
            decoration: BoxDecoration(
              color: Tone.warning.background(Theme.of(context).colorScheme),
              borderRadius: BorderRadius.circular(ClientTheme.radiusSmall),
            ),
            child: const Text('Astra attend votre réponse pour avancer sur cette demande.'),
          ),
        ],
      ],
    );
  }
}

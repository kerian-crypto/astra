import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_hub/core/layout/responsive.dart';
import 'package:astra_hub/core/widgets/async_value_view.dart';
import 'package:astra_hub/features/auth/presentation/auth_controller.dart';
import 'package:astra_hub/features/clients/data/clients.dart';
import 'package:astra_hub/features/clients/data/clients_repository.dart';
import 'package:astra_hub/features/clients/presentation/client_conversation_screen.dart';
import 'package:astra_hub/features/clients/presentation/client_widgets.dart';

/// Demande de support : statut, priorité, assignation et échanges.
class ClientTicketScreen extends ConsumerWidget {
  const ClientTicketScreen({required this.ticketId, super.key});

  final String ticketId;

  Future<void> _update(BuildContext context, WidgetRef ref, Map<String, Object?> data) async {
    try {
      await ref.read(clientsRepositoryProvider).updateTicket(ticketId, data);
      ref
        ..invalidate(clientTicketProvider(ticketId))
        ..invalidate(clientTicketsProvider);
    } on Exception catch (error) {
      if (context.mounted) showMessage(context, error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticket = ref.watch(clientTicketProvider(ticketId));
    final me = ref.watch(authControllerProvider).value;
    return Scaffold(
      appBar: AppBar(title: Text(ticket.value == null ? 'Ticket' : '#${ticket.value!.number}')),
      body: AsyncValueView(
        value: ticket,
        onRetry: () => ref.invalidate(clientTicketProvider(ticketId)),
        data: (t) {
          final details = ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(t.subject, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                '${t.companyName}${t.createdByName != null ? ' · ${t.createdByName}' : ''}'
                '${t.projectName != null ? ' · ${t.projectName}' : ''}',
              ),
              const SizedBox(height: 12),
              Text(t.description),
              const SizedBox(height: 16),
              DropdownButtonFormField<TicketStatus>(
                isExpanded: true,
                initialValue: t.status,
                decoration: const InputDecoration(labelText: 'Statut (visible du client)'),
                items: [
                  for (final s in TicketStatus.values)
                    DropdownMenuItem(value: s, child: Text(s.label)),
                ],
                onChanged: (s) => _update(context, ref, {'status': s!.value}),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<TicketPriority>(
                isExpanded: true,
                initialValue: t.priority,
                decoration: const InputDecoration(labelText: 'Priorité'),
                items: [
                  for (final p in TicketPriority.values)
                    DropdownMenuItem(value: p, child: Text(p.label)),
                ],
                onChanged: (p) => _update(context, ref, {'priority': p!.value}),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline),
                title: Text(t.assigneeName ?? 'Non assigné'),
                trailing: me != null && t.assigneeId != me.id
                    ? TextButton(
                        onPressed: () => _update(context, ref, {'assignee_id': me.id}),
                        child: const Text('Me l\'assigner'),
                      )
                    : null,
              ),
            ],
          );
          final thread = t.conversationId == null
              ? const SizedBox.shrink()
              : ClientThread(conversationId: t.conversationId!);
          if (context.isCompact) {
            return DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  const TabBar(
                    tabs: [
                      Tab(text: 'Demande'),
                      Tab(text: 'Échanges'),
                    ],
                  ),
                  Expanded(child: TabBarView(children: [details, thread])),
                ],
              ),
            );
          }
          return Row(
            children: [
              SizedBox(width: 400, child: details),
              const VerticalDivider(width: 1),
              Expanded(child: thread),
            ],
          );
        },
      ),
    );
  }
}

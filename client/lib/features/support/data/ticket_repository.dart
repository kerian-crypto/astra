import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_client/core/network/api_client.dart';
import 'package:astra_client/core/utils/json.dart';
import 'package:astra_client/features/support/data/ticket.dart';

final ticketRepositoryProvider = Provider<TicketRepository>(
  (ref) => TicketRepository(ref.watch(apiProvider)),
);

class TicketRepository {
  TicketRepository(this._api);

  final Api _api;

  Future<List<Ticket>> list() =>
      _api.get('/client/tickets', parse: (data) => listOf(data, Ticket.fromJson));

  Future<Ticket> get(String id) =>
      _api.get('/client/tickets/$id', parse: (data) => Ticket.fromJson(data! as Json));

  Future<Ticket> create({
    required TicketType type,
    required String subject,
    required String description,
    TicketPriority priority = TicketPriority.normal,
    String? projectId,
  }) => _api.post(
    '/client/tickets',
    data: {
      'type': type.value,
      'subject': subject.trim(),
      'description': description.trim(),
      'priority': priority.value,
      'project_id': ?projectId,
    },
    parse: (data) => Ticket.fromJson(data! as Json),
  );
}

final ticketsProvider = FutureProvider.autoDispose<List<Ticket>>(
  (ref) => ref.watch(ticketRepositoryProvider).list(),
);

final ticketProvider = FutureProvider.autoDispose.family<Ticket, String>(
  (ref, id) => ref.watch(ticketRepositoryProvider).get(id),
);

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import 'package:astra_hub/core/network/api_client.dart';
import 'package:astra_hub/core/network/api_exception.dart';
import 'package:astra_hub/core/utils/json.dart';
import 'package:astra_hub/features/clients/data/clients.dart';

final clientsRepositoryProvider = Provider<ClientsRepository>(
  (ref) => ClientsRepository(ref.watch(dioProvider)),
);

/// Fichier local choisi pour un envoi.
typedef LocalFile = ({String path, String name});

/// Administration du domaine client depuis Astra Hub (routes `/clients/*`,
/// livrables des projets et partage des documents).
class ClientsRepository {
  ClientsRepository(this._dio);

  final Dio _dio;

  Future<T> _get<T>(String path, T Function(Object? data) parse, {Map<String, Object?>? query}) =>
      guardApi(() async => parse((await _dio.get<Object?>(path, queryParameters: query)).data));

  Future<T> _send<T>(String method, String path, T Function(Object? data) parse, {Object? data}) =>
      guardApi(() async {
        final response = await _dio.request<Object?>(
          path,
          data: data,
          options: Options(method: method),
        );
        return parse(response.data);
      });

  // ---------- Entreprises et comptes ----------

  Future<List<ClientCompany>> companies() =>
      _get('/clients/companies', (d) => listOf(d, ClientCompany.fromJson));

  Future<ClientCompany> company(String id) =>
      _get('/clients/companies/$id', (d) => ClientCompany.fromJson(d! as Json));

  Future<ClientCompany> createCompany(Json data) =>
      _send('POST', '/clients/companies', (d) => ClientCompany.fromJson(d! as Json), data: data);

  Future<ClientCompany> updateCompany(String id, Json data) => _send(
    'PATCH',
    '/clients/companies/$id',
    (d) => ClientCompany.fromJson(d! as Json),
    data: data,
  );

  Future<List<ClientAccount>> accounts(String companyId) =>
      _get('/clients/companies/$companyId/accounts', (d) => listOf(d, ClientAccount.fromJson));

  Future<(ClientAccount, InvitationLink)> createAccount(
    String companyId, {
    required String email,
    required String fullName,
    String? jobTitle,
    Set<ClientPermission>? permissions,
  }) => _send(
    'POST',
    '/clients/companies/$companyId/accounts',
    (d) {
      final json = d! as Json;
      return (
        ClientAccount.fromJson(json['account'] as Json),
        InvitationLink.fromJson(json['invitation'] as Json),
      );
    },
    data: {
      'email': email.trim(),
      'full_name': fullName.trim(),
      if (jobTitle != null && jobTitle.trim().isNotEmpty) 'job_title': jobTitle.trim(),
      if (permissions != null) 'permissions': [for (final p in permissions) p.value],
    },
  );

  Future<ClientAccount> updateAccount(String accountId, Json data) => _send(
    'PATCH',
    '/clients/accounts/$accountId',
    (d) => ClientAccount.fromJson(d! as Json),
    data: data,
  );

  Future<InvitationLink> reissueInvitation(String accountId) => _send(
    'POST',
    '/clients/accounts/$accountId/invitation',
    (d) => InvitationLink.fromJson(d! as Json),
  );

  // ---------- Projets : rattachement, livrables, documents ----------

  Future<void> updateProjectClient(String projectId, Json data) =>
      _send('PATCH', '/projects/$projectId', (_) {}, data: data);

  Future<List<Deliverable>> deliverables(String projectId) =>
      _get('/projects/$projectId/deliverables', (d) => listOf(d, Deliverable.fromJson));

  Future<Deliverable> deliverable(String id) =>
      _get('/deliverables/$id', (d) => Deliverable.fromJson(d! as Json));

  Future<Deliverable> createDeliverable(
    String projectId, {
    required String title,
    String? description,
    bool requiresValidation = true,
  }) => _send(
    'POST',
    '/projects/$projectId/deliverables',
    (d) => Deliverable.fromJson(d! as Json),
    data: {
      'title': title.trim(),
      if (description != null && description.trim().isNotEmpty) 'description': description.trim(),
      'requires_validation': requiresValidation,
    },
  );

  /// Publie une version au client : fichier et/ou lien https.
  Future<Deliverable> publishVersion(
    String deliverableId, {
    String? notes,
    String? linkUrl,
    LocalFile? file,
  }) async {
    final form = FormData.fromMap({
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      if (linkUrl != null && linkUrl.trim().isNotEmpty) 'link_url': linkUrl.trim(),
      if (file != null) 'file': await MultipartFile.fromFile(file.path, filename: file.name),
    });
    return _send(
      'POST',
      '/deliverables/$deliverableId/versions',
      (d) => Deliverable.fromJson(d! as Json),
      data: form,
    );
  }

  Future<void> setDocumentVisibility(String documentId, {required bool shared}) => _send(
    'PUT',
    '/documents/$documentId/visibility',
    (_) {},
    data: {'visibility': shared ? 'client' : 'internal'},
  );

  // ---------- Conversations ----------

  Future<List<ClientConversation>> conversations({String? companyId}) => _get(
    '/clients/conversations',
    (d) => listOf(d, ClientConversation.fromJson),
    query: {'company_id': ?companyId},
  );

  Future<ClientConversation> conversation(String id) =>
      _get('/clients/conversations/$id', (d) => ClientConversation.fromJson(d! as Json));

  Future<List<ClientMessage>> messages(String conversationId) => _get(
    '/clients/conversations/$conversationId/messages',
    (d) => listOf(d, ClientMessage.fromJson),
  );

  Future<ClientMessage> sendMessage(String conversationId, String body, {LocalFile? file}) async {
    final form = FormData.fromMap({
      'body': body.trim(),
      if (file != null) 'file': await MultipartFile.fromFile(file.path, filename: file.name),
    });
    return _send(
      'POST',
      '/clients/conversations/$conversationId/messages',
      (d) => ClientMessage.fromJson(d! as Json),
      data: form,
    );
  }

  Future<ClientConversation> startConversation({
    required String companyId,
    required String subject,
    required String body,
    String? projectId,
  }) => _send(
    'POST',
    '/clients/conversations',
    (d) => ClientConversation.fromJson(d! as Json),
    data: {
      'company_id': companyId,
      'subject': subject.trim(),
      'body': body.trim(),
      'project_id': ?projectId,
    },
  );

  Future<void> markConversationRead(String id) =>
      _send('POST', '/clients/conversations/$id/read', (_) {});

  // ---------- Tickets ----------

  Future<List<SupportTicket>> tickets({bool openOnly = false}) => _get(
    '/clients/tickets',
    (d) => listOf(d, SupportTicket.fromJson),
    query: {if (openOnly) 'open_only': true},
  );

  Future<SupportTicket> ticket(String id) =>
      _get('/clients/tickets/$id', (d) => SupportTicket.fromJson(d! as Json));

  Future<SupportTicket> updateTicket(String id, Json data) =>
      _send('PATCH', '/clients/tickets/$id', (d) => SupportTicket.fromJson(d! as Json), data: data);

  // ---------- Factures et paiements ----------

  Future<List<Invoice>> invoices({String? companyId}) => _get(
    '/clients/invoices',
    (d) => listOf(d, Invoice.fromJson),
    query: {'company_id': ?companyId},
  );

  Future<Invoice> createInvoice(
    String companyId, {
    required String title,
    required double amount,
    required DateTime issueDate,
    DateTime? dueDate,
    String? projectId,
    LocalFile? file,
  }) async {
    final form = FormData.fromMap({
      'title': title.trim(),
      'amount': amount.toStringAsFixed(2),
      'issue_date': isoDate(issueDate),
      if (dueDate != null) 'due_date': isoDate(dueDate),
      'project_id': ?projectId,
      if (file != null) 'file': await MultipartFile.fromFile(file.path, filename: file.name),
    });
    return _send(
      'POST',
      '/clients/companies/$companyId/invoices',
      (d) => Invoice.fromJson(d! as Json),
      data: form,
    );
  }

  Future<List<PaymentDeclaration>> declarations({bool pendingOnly = false}) => _get(
    '/clients/payment-declarations',
    (d) => listOf(d, PaymentDeclaration.fromJson),
    query: {if (pendingOnly) 'pending_only': true},
  );

  Future<PaymentDeclaration> reviewDeclaration(
    String id, {
    required bool confirm,
    double? confirmedAmount,
    String? rejectionReason,
  }) => _send(
    'POST',
    '/clients/payment-declarations/$id/review',
    (d) => PaymentDeclaration.fromJson(d! as Json),
    data: {
      'confirm': confirm,
      if (confirmedAmount != null) 'confirmed_amount': confirmedAmount.toStringAsFixed(2),
      'rejection_reason': ?rejectionReason,
    },
  );

  // ---------- Contrats ----------

  Future<List<Contract>> contracts(String companyId) => _get(
    '/clients/contracts',
    (d) => listOf(d, Contract.fromJson),
    query: {'company_id': companyId},
  );

  Future<Contract> createContract(String companyId, Json data) => _send(
    'POST',
    '/clients/companies/$companyId/contracts',
    (d) => Contract.fromJson(d! as Json),
    data: data,
  );

  Future<Contract> updateContract(String id, Json data) =>
      _send('PATCH', '/clients/contracts/$id', (d) => Contract.fromJson(d! as Json), data: data);

  Future<void> setContractFile(String id, LocalFile file) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(file.path, filename: file.name),
    });
    await _send('PUT', '/clients/contracts/$id/file', (_) {}, data: form);
  }

  /// Télécharge un fichier protégé de l'API puis l'ouvre sur le téléphone.
  Future<void> openFile(String apiPath, String filename) async {
    final folder = await getTemporaryDirectory();
    final target = '${folder.path}/${filename.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}';
    await guardApi(() => _dio.download(apiPath, target));
    final result = await OpenFilex.open(target);
    if (result.type != ResultType.done) {
      await File(target).delete().catchError((Object _) => File(target));
      throw ApiException('Aucune application ne peut ouvrir « $filename ».');
    }
  }
}

final clientCompaniesProvider = FutureProvider.autoDispose<List<ClientCompany>>(
  (ref) => ref.watch(clientsRepositoryProvider).companies(),
);

final clientCompanyProvider = FutureProvider.autoDispose.family<ClientCompany, String>(
  (ref, id) => ref.watch(clientsRepositoryProvider).company(id),
);

final clientAccountsProvider = FutureProvider.autoDispose.family<List<ClientAccount>, String>(
  (ref, companyId) => ref.watch(clientsRepositoryProvider).accounts(companyId),
);

final projectDeliverablesProvider = FutureProvider.autoDispose.family<List<Deliverable>, String>(
  (ref, projectId) => ref.watch(clientsRepositoryProvider).deliverables(projectId),
);

final hubDeliverableProvider = FutureProvider.autoDispose.family<Deliverable, String>(
  (ref, id) => ref.watch(clientsRepositoryProvider).deliverable(id),
);

final clientConversationsProvider = FutureProvider.autoDispose<List<ClientConversation>>(
  (ref) => ref.watch(clientsRepositoryProvider).conversations(),
);

final clientConversationProvider = FutureProvider.autoDispose.family<ClientConversation, String>(
  (ref, id) => ref.watch(clientsRepositoryProvider).conversation(id),
);

final clientMessagesProvider = FutureProvider.autoDispose.family<List<ClientMessage>, String>(
  (ref, id) => ref.watch(clientsRepositoryProvider).messages(id),
);

final clientTicketsProvider = FutureProvider.autoDispose<List<SupportTicket>>(
  (ref) => ref.watch(clientsRepositoryProvider).tickets(),
);

final clientTicketProvider = FutureProvider.autoDispose.family<SupportTicket, String>(
  (ref, id) => ref.watch(clientsRepositoryProvider).ticket(id),
);

final pendingDeclarationsProvider = FutureProvider.autoDispose<List<PaymentDeclaration>>(
  (ref) => ref.watch(clientsRepositoryProvider).declarations(),
);

final companyInvoicesProvider = FutureProvider.autoDispose.family<List<Invoice>, String>(
  (ref, companyId) => ref.watch(clientsRepositoryProvider).invoices(companyId: companyId),
);

final companyContractsProvider = FutureProvider.autoDispose.family<List<Contract>, String>(
  (ref, companyId) => ref.watch(clientsRepositoryProvider).contracts(companyId),
);

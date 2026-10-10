import 'package:flutter/material.dart';

import 'package:astra_hub/core/utils/json.dart';

double _amount(Object? value) => value == null ? 0 : double.parse(value.toString());

/// Permissions d'un compte client (vérifiées par le serveur).
enum ClientPermission {
  viewProject('view_project', 'Voir les projets'),
  viewDocument('view_document', 'Voir les documents'),
  downloadDocument('download_document', 'Télécharger les documents'),
  validateDeliverable('validate_deliverable', 'Valider les livrables'),
  sendMessage('send_message', 'Envoyer des messages'),
  createTicket('create_ticket', 'Créer des demandes de support'),
  viewInvoice('view_invoice', 'Voir les factures'),
  submitPaymentProof('submit_payment_proof', 'Déclarer des paiements'),
  viewContract('view_contract', 'Voir les contrats'),
  viewFinancialData('view_financial_data', 'Voir les montants des contrats'),
  manageCompanyUsers('manage_company_users', 'Administrer l\'entreprise');

  const ClientPermission(this.value, this.label);
  final String value;
  final String label;

  static ClientPermission? parse(Object? value) =>
      values.where((p) => p.value == value).firstOrNull;

  static const defaults = {
    viewProject,
    viewDocument,
    downloadDocument,
    validateDeliverable,
    sendMessage,
    createTicket,
  };
}

/// Statut affiché au client (§16), piloté depuis le Hub.
enum ClientProjectStatus {
  planning('planning', 'Planification'),
  inProgress('in_progress', 'En cours'),
  waitingClient('waiting_client', 'En attente du client'),
  inValidation('in_validation', 'En validation'),
  changesRequested('changes_requested', 'Modification demandée'),
  inCorrection('in_correction', 'En correction'),
  done('done', 'Terminé'),
  suspended('suspended', 'Suspendu'),
  cancelled('cancelled', 'Annulé');

  const ClientProjectStatus(this.value, this.label);
  final String value;
  final String label;

  static ClientProjectStatus? parse(Object? value) =>
      values.where((s) => s.value == value).firstOrNull;
}

class ClientCompany {
  const ClientCompany({
    required this.id,
    required this.name,
    required this.isActive,
    required this.accountCount,
    required this.projectCount,
    this.email,
    this.phone,
    this.address,
    this.website,
    this.sector,
    this.internalNotes,
  });

  factory ClientCompany.fromJson(Json json) => ClientCompany(
    id: json['id'] as String,
    name: json['name'] as String,
    email: json['email'] as String?,
    phone: json['phone'] as String?,
    address: json['address'] as String?,
    website: json['website'] as String?,
    sector: json['sector'] as String?,
    internalNotes: json['internal_notes'] as String?,
    isActive: json['is_active'] as bool? ?? true,
    accountCount: json['account_count'] as int? ?? 0,
    projectCount: json['project_count'] as int? ?? 0,
  );

  final String id;
  final String name;
  final String? email;
  final String? phone;
  final String? address;
  final String? website;
  final String? sector;
  final String? internalNotes;
  final bool isActive;
  final int accountCount;
  final int projectCount;
}

class ClientAccount {
  const ClientAccount({
    required this.id,
    required this.email,
    required this.fullName,
    required this.permissions,
    required this.isActive,
    this.jobTitle,
    this.phone,
    this.activatedAt,
    this.lastLoginAt,
  });

  factory ClientAccount.fromJson(Json json) => ClientAccount(
    id: json['id'] as String,
    email: json['email'] as String,
    fullName: json['full_name'] as String,
    jobTitle: json['job_title'] as String?,
    phone: json['phone'] as String?,
    permissions: stringsOf(json['permissions']).map(ClientPermission.parse).nonNulls.toSet(),
    isActive: json['is_active'] as bool? ?? true,
    activatedAt: dateOrNull(json['activated_at']),
    lastLoginAt: dateOrNull(json['last_login_at']),
  );

  final String id;
  final String email;
  final String fullName;
  final String? jobTitle;
  final String? phone;
  final Set<ClientPermission> permissions;
  final bool isActive;
  final DateTime? activatedAt;
  final DateTime? lastLoginAt;

  bool get isActivated => activatedAt != null;
}

/// Lien d'activation ou de nouveau mot de passe, montré une seule fois.
class InvitationLink {
  const InvitationLink({
    required this.token,
    required this.link,
    required this.purpose,
    required this.hours,
  });

  factory InvitationLink.fromJson(Json json) => InvitationLink(
    token: json['token'] as String,
    link: json['link'] as String,
    purpose: json['purpose'] as String,
    hours: json['expires_in_hours'] as int? ?? 72,
  );

  final String token;
  final String link;
  final String purpose;
  final int hours;

  bool get isReset => purpose == 'password_reset';
}

class AttachedFile {
  const AttachedFile({required this.name, required this.contentType, required this.sizeBytes});

  static AttachedFile? fromJson(Object? json) => json is Json
      ? AttachedFile(
          name: json['name'] as String,
          contentType: json['content_type'] as String,
          sizeBytes: json['size_bytes'] as int? ?? 0,
        )
      : null;

  final String name;
  final String contentType;
  final int sizeBytes;
}

enum DeliverableStatus {
  draft('draft', 'Brouillon', Icons.edit_outlined),
  published('published', 'Transmis', Icons.send_outlined),
  awaitingValidation('awaiting_validation', 'En attente du client', Icons.hourglass_top),
  approved('approved', 'Approuvé', Icons.verified_outlined),
  changesRequested('changes_requested', 'Modification demandée', Icons.edit_note);

  const DeliverableStatus(this.value, this.label, this.icon);
  final String value;
  final String label;
  final IconData icon;

  static DeliverableStatus parse(Object? value) =>
      values.where((s) => s.value == value).firstOrNull ?? draft;
}

class DeliverableVersion {
  const DeliverableVersion({
    required this.id,
    required this.number,
    required this.publishedAt,
    this.notes,
    this.linkUrl,
    this.file,
    this.publishedBy,
  });

  factory DeliverableVersion.fromJson(Json json) => DeliverableVersion(
    id: json['id'] as String,
    number: json['number'] as int,
    notes: json['notes'] as String?,
    linkUrl: json['link_url'] as String?,
    file: AttachedFile.fromJson(json['file']),
    publishedAt: DateTime.parse(json['published_at'] as String),
    publishedBy: json['published_by_name'] as String?,
  );

  final String id;
  final int number;
  final String? notes;
  final String? linkUrl;
  final AttachedFile? file;
  final DateTime publishedAt;
  final String? publishedBy;
}

class DeliverableReview {
  const DeliverableReview({
    required this.id,
    required this.versionNumber,
    required this.approved,
    required this.reviewerName,
    required this.createdAt,
    this.reason,
    this.comment,
    this.file,
  });

  factory DeliverableReview.fromJson(Json json) => DeliverableReview(
    id: json['id'] as String,
    versionNumber: json['version_number'] as int,
    approved: json['action'] == 'approve',
    reviewerName: json['reviewer_name'] as String,
    reason: json['reason'] as String?,
    comment: json['comment'] as String?,
    file: AttachedFile.fromJson(json['file']),
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  final String id;
  final int versionNumber;
  final bool approved;
  final String reviewerName;
  final String? reason;
  final String? comment;
  final AttachedFile? file;
  final DateTime createdAt;
}

class Deliverable {
  const Deliverable({
    required this.id,
    required this.projectId,
    required this.projectName,
    required this.title,
    required this.status,
    required this.requiresValidation,
    required this.versions,
    required this.reviews,
    this.description,
    this.dueDate,
  });

  factory Deliverable.fromJson(Json json) => Deliverable(
    id: json['id'] as String,
    projectId: json['project_id'] as String,
    projectName: json['project_name'] as String? ?? '',
    title: json['title'] as String,
    description: json['description'] as String?,
    status: DeliverableStatus.parse(json['status']),
    requiresValidation: json['requires_validation'] as bool? ?? true,
    dueDate: dateOrNull(json['due_date']),
    versions: listOf(json['versions'], DeliverableVersion.fromJson),
    reviews: listOf(json['reviews'], DeliverableReview.fromJson),
  );

  final String id;
  final String projectId;
  final String projectName;
  final String title;
  final String? description;
  final DeliverableStatus status;
  final bool requiresValidation;
  final DateTime? dueDate;
  final List<DeliverableVersion> versions;
  final List<DeliverableReview> reviews;

  DeliverableVersion? get current => versions.firstOrNull;
}

class ClientMessage {
  const ClientMessage({
    required this.id,
    required this.conversationId,
    required this.authorName,
    required this.fromAstra,
    required this.isMine,
    required this.body,
    required this.createdAt,
    this.file,
  });

  factory ClientMessage.fromJson(Json json) => ClientMessage(
    id: json['id'] as String,
    conversationId: json['conversation_id'] as String,
    authorName: json['author_name'] as String,
    fromAstra: json['from_astra'] as bool? ?? false,
    isMine: json['is_mine'] as bool? ?? false,
    body: json['body'] as String? ?? '',
    file: AttachedFile.fromJson(json['file']),
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  final String id;
  final String conversationId;
  final String authorName;
  final bool fromAstra;
  final bool isMine;
  final String body;
  final AttachedFile? file;
  final DateTime createdAt;
}

class ClientConversation {
  const ClientConversation({
    required this.id,
    required this.kind,
    required this.subject,
    required this.companyId,
    required this.companyName,
    required this.unreadCount,
    required this.createdAt,
    this.projectName,
    this.lastMessage,
    this.lastMessageAt,
  });

  factory ClientConversation.fromJson(Json json) => ClientConversation(
    id: json['id'] as String,
    kind: json['kind'] as String,
    subject: json['subject'] as String,
    companyId: json['company_id'] as String,
    companyName: json['company_name'] as String,
    projectName: json['project_name'] as String?,
    lastMessage: json['last_message'] == null
        ? null
        : ClientMessage.fromJson(json['last_message'] as Json),
    lastMessageAt: dateOrNull(json['last_message_at']),
    unreadCount: json['unread_count'] as int? ?? 0,
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  final String id;
  final String kind;
  final String subject;
  final String companyId;
  final String companyName;
  final String? projectName;
  final ClientMessage? lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final DateTime createdAt;
}

enum TicketStatus {
  newTicket('new', 'Nouveau'),
  acknowledged('acknowledged', 'Pris en charge'),
  inProgress('in_progress', 'En cours'),
  waitingClient('waiting_client', 'En attente du client'),
  resolved('resolved', 'Résolu'),
  closed('closed', 'Fermé');

  const TicketStatus(this.value, this.label);
  final String value;
  final String label;

  static TicketStatus parse(Object? value) =>
      values.where((s) => s.value == value).firstOrNull ?? newTicket;
}

enum TicketPriority {
  low('low', 'Basse'),
  normal('normal', 'Normale'),
  high('high', 'Haute'),
  urgent('urgent', 'Urgente');

  const TicketPriority(this.value, this.label);
  final String value;
  final String label;

  static TicketPriority parse(Object? value) =>
      values.where((p) => p.value == value).firstOrNull ?? normal;
}

class SupportTicket {
  const SupportTicket({
    required this.id,
    required this.number,
    required this.type,
    required this.subject,
    required this.description,
    required this.status,
    required this.priority,
    required this.companyName,
    required this.updatedAt,
    this.projectName,
    this.createdByName,
    this.conversationId,
    this.assigneeId,
    this.assigneeName,
  });

  factory SupportTicket.fromJson(Json json) => SupportTicket(
    id: json['id'] as String,
    number: json['number'] as String,
    type: json['type'] as String,
    subject: json['subject'] as String,
    description: json['description'] as String,
    status: TicketStatus.parse(json['status']),
    priority: TicketPriority.parse(json['priority']),
    companyName: json['company_name'] as String,
    projectName: json['project_name'] as String?,
    createdByName: json['created_by_name'] as String?,
    conversationId: json['conversation_id'] as String?,
    assigneeId: json['assignee_id'] as String?,
    assigneeName: json['assignee_name'] as String?,
    updatedAt: DateTime.parse(json['updated_at'] as String),
  );

  final String id;
  final String number;
  final String type;
  final String subject;
  final String description;
  final TicketStatus status;
  final TicketPriority priority;
  final String companyName;
  final String? projectName;
  final String? createdByName;
  final String? conversationId;
  final String? assigneeId;
  final String? assigneeName;
  final DateTime updatedAt;
}

const paymentMethodLabels = {
  'bank_transfer': 'Virement',
  'mobile_money': 'Mobile Money',
  'cash': 'Espèces',
  'check': 'Chèque',
  'card': 'Carte',
  'other': 'Autre',
};

const paymentStatusLabels = {
  'unpaid': 'Non payée',
  'payment_declared': 'Paiement déclaré',
  'under_review': 'En vérification',
  'confirmed': 'Payée',
  'rejected': 'Paiement refusé',
  'partially_confirmed': 'Partiellement payée',
};

class PaymentDeclaration {
  const PaymentDeclaration({
    required this.id,
    required this.invoiceId,
    required this.invoiceNumber,
    required this.companyName,
    required this.amount,
    required this.currency,
    required this.paidOn,
    required this.method,
    required this.status,
    required this.createdAt,
    this.reference,
    this.note,
    this.confirmedAmount,
    this.rejectionReason,
    this.proof,
    this.declaredByName,
    this.reviewedByName,
  });

  factory PaymentDeclaration.fromJson(Json json) => PaymentDeclaration(
    id: json['id'] as String,
    invoiceId: json['invoice_id'] as String,
    invoiceNumber: json['invoice_number'] as String,
    companyName: json['company_name'] as String? ?? '',
    amount: _amount(json['amount']),
    currency: json['currency'] as String? ?? 'XOF',
    paidOn: DateTime.parse(json['paid_on'] as String),
    method: json['method'] as String,
    reference: json['reference'] as String?,
    note: json['note'] as String?,
    status: json['status'] as String,
    confirmedAmount: json['confirmed_amount'] == null ? null : _amount(json['confirmed_amount']),
    rejectionReason: json['rejection_reason'] as String?,
    proof: AttachedFile.fromJson(json['proof']),
    declaredByName: json['declared_by_name'] as String?,
    reviewedByName: json['reviewed_by_name'] as String?,
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  final String id;
  final String invoiceId;
  final String invoiceNumber;
  final String companyName;
  final double amount;
  final String currency;
  final DateTime paidOn;
  final String method;
  final String status;
  final String? reference;
  final String? note;
  final double? confirmedAmount;
  final String? rejectionReason;
  final AttachedFile? proof;
  final String? declaredByName;
  final String? reviewedByName;
  final DateTime createdAt;

  bool get isPending => status == 'declared' || status == 'under_review';
}

class Invoice {
  const Invoice({
    required this.id,
    required this.number,
    required this.title,
    required this.companyId,
    required this.companyName,
    required this.amount,
    required this.currency,
    required this.issueDate,
    required this.paidAmount,
    required this.remainingAmount,
    required this.status,
    required this.paymentStatus,
    required this.declarations,
    this.dueDate,
    this.file,
  });

  factory Invoice.fromJson(Json json) => Invoice(
    id: json['id'] as String,
    number: json['number'] as String,
    title: json['title'] as String,
    companyId: json['company_id'] as String,
    companyName: json['company_name'] as String,
    amount: _amount(json['amount']),
    currency: json['currency'] as String? ?? 'XOF',
    issueDate: DateTime.parse(json['issue_date'] as String),
    dueDate: dateOrNull(json['due_date']),
    paidAmount: _amount(json['paid_amount']),
    remainingAmount: _amount(json['remaining_amount']),
    status: json['status'] as String,
    paymentStatus: json['payment_status'] as String,
    declarations: listOf(json['declarations'], PaymentDeclaration.fromJson),
    file: AttachedFile.fromJson(json['file']),
  );

  final String id;
  final String number;
  final String title;
  final String companyId;
  final String companyName;
  final double amount;
  final String currency;
  final DateTime issueDate;
  final DateTime? dueDate;
  final double paidAmount;
  final double remainingAmount;
  final String status;
  final String paymentStatus;
  final List<PaymentDeclaration> declarations;
  final AttachedFile? file;
}

const contractStatusLabels = {
  'draft': 'Brouillon',
  'active': 'Actif',
  'expired': 'Expiré',
  'terminated': 'Résilié',
};

class Contract {
  const Contract({
    required this.id,
    required this.number,
    required this.title,
    required this.status,
    required this.currency,
    this.amount,
    this.startDate,
    this.endDate,
    this.services,
    this.file,
  });

  factory Contract.fromJson(Json json) => Contract(
    id: json['id'] as String,
    number: json['number'] as String,
    title: json['title'] as String,
    status: json['status'] as String,
    currency: json['currency'] as String? ?? 'XOF',
    amount: json['amount'] == null ? null : _amount(json['amount']),
    startDate: dateOrNull(json['start_date']),
    endDate: dateOrNull(json['end_date']),
    services: json['services'] as String?,
    file: AttachedFile.fromJson(json['file']),
  );

  final String id;
  final String number;
  final String title;
  final String status;
  final String currency;
  final double? amount;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? services;
  final AttachedFile? file;
}

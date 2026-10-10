import 'package:astra_client/core/theme/client_theme.dart';
import 'package:astra_client/core/utils/json.dart';
import 'package:astra_client/features/deliverables/data/deliverable.dart';

double _amount(Object? value) => value == null ? 0 : double.parse(value.toString());

/// État de paiement d'une facture (§31), calculé par le serveur.
enum PaymentStatus {
  unpaid('unpaid', 'Non payée', Tone.danger),
  declared('payment_declared', 'Paiement déclaré', Tone.info),
  underReview('under_review', 'En vérification', Tone.info),
  confirmed('confirmed', 'Payée', Tone.success),
  rejected('rejected', 'Paiement refusé', Tone.danger),
  partial('partially_confirmed', 'Partiellement payée', Tone.warning);

  const PaymentStatus(this.value, this.label, this.tone);
  final String value;
  final String label;
  final Tone tone;

  static PaymentStatus parse(Object? value) =>
      values.where((s) => s.value == value).firstOrNull ?? unpaid;
}

enum DeclarationStatus {
  declared('declared', 'Déclaré', Tone.info),
  underReview('under_review', 'En vérification', Tone.info),
  confirmed('confirmed', 'Confirmé', Tone.success),
  rejected('rejected', 'Refusé', Tone.danger);

  const DeclarationStatus(this.value, this.label, this.tone);
  final String value;
  final String label;
  final Tone tone;

  static DeclarationStatus parse(Object? value) =>
      values.where((s) => s.value == value).firstOrNull ?? declared;
}

enum PaymentMethod {
  bankTransfer('bank_transfer', 'Virement bancaire'),
  mobileMoney('mobile_money', 'Mobile Money'),
  cash('cash', 'Espèces'),
  check('check', 'Chèque'),
  card('card', 'Carte bancaire'),
  other('other', 'Autre');

  const PaymentMethod(this.value, this.label);
  final String value;
  final String label;

  static PaymentMethod parse(Object? value) =>
      values.where((m) => m.value == value).firstOrNull ?? other;
}

class PaymentDeclaration {
  const PaymentDeclaration({
    required this.id,
    required this.invoiceId,
    required this.invoiceNumber,
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
    this.reviewedAt,
  });

  factory PaymentDeclaration.fromJson(Json json) => PaymentDeclaration(
    id: json['id'] as String,
    invoiceId: json['invoice_id'] as String,
    invoiceNumber: json['invoice_number'] as String,
    amount: _amount(json['amount']),
    currency: json['currency'] as String? ?? 'XOF',
    paidOn: DateTime.parse(json['paid_on'] as String),
    method: PaymentMethod.parse(json['method']),
    reference: json['reference'] as String?,
    note: json['note'] as String?,
    status: DeclarationStatus.parse(json['status']),
    confirmedAmount: json['confirmed_amount'] == null ? null : _amount(json['confirmed_amount']),
    rejectionReason: json['rejection_reason'] as String?,
    proof: AttachedFile.fromJson(json['proof']),
    declaredByName: json['declared_by_name'] as String?,
    reviewedAt: dateOrNull(json['reviewed_at']),
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  final String id;
  final String invoiceId;
  final String invoiceNumber;
  final double amount;
  final String currency;
  final DateTime paidOn;
  final PaymentMethod method;
  final String? reference;
  final String? note;
  final DeclarationStatus status;
  final double? confirmedAmount;
  final String? rejectionReason;
  final AttachedFile? proof;
  final String? declaredByName;
  final DateTime? reviewedAt;
  final DateTime createdAt;
}

class Invoice {
  const Invoice({
    required this.id,
    required this.number,
    required this.title,
    required this.amount,
    required this.currency,
    required this.issueDate,
    required this.paidAmount,
    required this.remainingAmount,
    required this.cancelled,
    required this.paymentStatus,
    required this.isOverdue,
    this.projectId,
    this.projectName,
    this.dueDate,
    this.file,
  });

  factory Invoice.fromJson(Json json) => Invoice(
    id: json['id'] as String,
    number: json['number'] as String,
    title: json['title'] as String,
    projectId: json['project_id'] as String?,
    projectName: json['project_name'] as String?,
    amount: _amount(json['amount']),
    currency: json['currency'] as String? ?? 'XOF',
    issueDate: DateTime.parse(json['issue_date'] as String),
    dueDate: dateOrNull(json['due_date']),
    paidAmount: _amount(json['paid_amount']),
    remainingAmount: _amount(json['remaining_amount']),
    cancelled: json['status'] == 'cancelled',
    paymentStatus: PaymentStatus.parse(json['payment_status']),
    isOverdue: json['is_overdue'] as bool? ?? false,
    file: AttachedFile.fromJson(json['file']),
  );

  final String id;
  final String number;
  final String title;
  final String? projectId;
  final String? projectName;
  final double amount;
  final String currency;
  final DateTime issueDate;
  final DateTime? dueDate;
  final double paidAmount;
  final double remainingAmount;
  final bool cancelled;
  final PaymentStatus paymentStatus;
  final bool isOverdue;
  final AttachedFile? file;

  double get paidRatio => amount <= 0 ? 0 : (paidAmount / amount).clamp(0, 1);
}

/// Facture et historique de ses déclarations de paiement.
class InvoiceDetail {
  const InvoiceDetail({
    required this.invoice,
    required this.declarations,
    required this.canDeclare,
  });

  factory InvoiceDetail.fromJson(Json json) => InvoiceDetail(
    invoice: Invoice.fromJson(json),
    declarations: listOf(json['declarations'], PaymentDeclaration.fromJson),
    canDeclare: json['can_declare'] as bool? ?? false,
  );

  final Invoice invoice;
  final List<PaymentDeclaration> declarations;
  final bool canDeclare;
}

enum ContractStatus {
  active('active', 'Actif', Tone.success),
  expired('expired', 'Expiré', Tone.neutral),
  terminated('terminated', 'Résilié', Tone.danger),
  draft('draft', 'Brouillon', Tone.neutral);

  const ContractStatus(this.value, this.label, this.tone);
  final String value;
  final String label;
  final Tone tone;

  static ContractStatus parse(Object? value) =>
      values.where((s) => s.value == value).firstOrNull ?? active;
}

class Contract {
  const Contract({
    required this.id,
    required this.number,
    required this.title,
    required this.currency,
    required this.status,
    this.projectId,
    this.projectName,
    this.services,
    this.amount,
    this.startDate,
    this.endDate,
    this.renewalTerms,
    this.paymentSchedule,
    this.file,
  });

  factory Contract.fromJson(Json json) => Contract(
    id: json['id'] as String,
    number: json['number'] as String,
    title: json['title'] as String,
    projectId: json['project_id'] as String?,
    projectName: json['project_name'] as String?,
    services: json['services'] as String?,
    amount: json['amount'] == null ? null : _amount(json['amount']),
    currency: json['currency'] as String? ?? 'XOF',
    startDate: dateOrNull(json['start_date']),
    endDate: dateOrNull(json['end_date']),
    renewalTerms: json['renewal_terms'] as String?,
    paymentSchedule: json['payment_schedule'] as String?,
    status: ContractStatus.parse(json['status']),
    file: AttachedFile.fromJson(json['file']),
  );

  final String id;
  final String number;
  final String title;
  final String? projectId;
  final String? projectName;
  final String? services;
  final double? amount;
  final String currency;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? renewalTerms;
  final String? paymentSchedule;
  final ContractStatus status;
  final AttachedFile? file;

  /// Contrat actif arrivant à échéance dans les 60 jours.
  bool get isExpiringSoon {
    final end = endDate;
    if (end == null || status != ContractStatus.active) return false;
    final days = end.difference(DateTime.now()).inDays;
    return days >= 0 && days <= 60;
  }
}

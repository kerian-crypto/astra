import 'package:astra_client/core/utils/json.dart';

/// Permissions d'un compte client, vérifiées par le serveur. L'app ne s'en
/// sert que pour masquer ce qui serait refusé (jamais comme sécurité).
enum ClientPermission {
  viewProject('view_project'),
  viewDocument('view_document'),
  downloadDocument('download_document'),
  viewInvoice('view_invoice'),
  submitPaymentProof('submit_payment_proof'),
  viewContract('view_contract'),
  sendMessage('send_message'),
  createTicket('create_ticket'),
  validateDeliverable('validate_deliverable'),
  viewFinancialData('view_financial_data'),
  manageCompanyUsers('manage_company_users'),
  submitBrief('submit_brief');

  const ClientPermission(this.value);
  final String value;

  static ClientPermission? parse(Object? value) =>
      values.where((p) => p.value == value).firstOrNull;
}

class Company {
  const Company({
    required this.id,
    required this.name,
    this.email,
    this.phone,
    this.address,
    this.website,
    this.sector,
    this.hasLogo = false,
  });

  factory Company.fromJson(Json json) => Company(
    id: json['id'] as String,
    name: json['name'] as String,
    email: json['email'] as String?,
    phone: json['phone'] as String?,
    address: json['address'] as String?,
    website: json['website'] as String?,
    sector: json['sector'] as String?,
    hasLogo: json['has_logo'] as bool? ?? false,
  );

  final String id;
  final String name;
  final String? email;
  final String? phone;
  final String? address;
  final String? website;
  final String? sector;
  final bool hasLogo;
}

/// Compte client connecté.
class ClientSession {
  const ClientSession({
    required this.id,
    required this.email,
    required this.fullName,
    required this.permissions,
    required this.company,
    this.jobTitle,
    this.phone,
  });

  factory ClientSession.fromJson(Json json) => ClientSession(
    id: json['id'] as String,
    email: json['email'] as String,
    fullName: json['full_name'] as String,
    jobTitle: json['job_title'] as String?,
    phone: json['phone'] as String?,
    permissions: Set.unmodifiable(
      stringsOf(json['permissions']).map(ClientPermission.parse).nonNulls,
    ),
    company: Company.fromJson(json['company'] as Json),
  );

  final String id;
  final String email;
  final String fullName;
  final String? jobTitle;
  final String? phone;
  final Set<ClientPermission> permissions;
  final Company company;

  bool can(ClientPermission permission) => permissions.contains(permission);

  String get firstName => fullName.split(' ').first;
}

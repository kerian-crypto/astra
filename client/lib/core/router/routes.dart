abstract final class Routes {
  static const splash = '/splash';
  static const login = '/login';
  static const activate = '/activate';
  static const register = '/register';

  // Onglets
  static const home = '/home';
  static const projects = '/projects';
  static const messages = '/messages';
  static const documents = '/documents';
  static const more = '/more';

  // Écrans empilés
  static const notifications = '/notifications';
  static const invoices = '/invoices';
  static const payments = '/payments';
  static const contracts = '/contracts';
  static const tickets = '/tickets';
  static const newTicket = '/tickets/new';
  static const profile = '/profile';
  static const company = '/company';
  static const team = '/team';
  static const security = '/security';
  static const briefs = '/briefs';
  static const newBrief = '/briefs/new';

  static String project(String id) => '$projects/$id';
  static String conversation(String id) => '$messages/$id';
  static String deliverable(String id) => '/deliverables/$id';
  static String invoice(String id) => '$invoices/$id';
  static String declarePayment(String invoiceId) => '$invoices/$invoiceId/declare';
  static String contract(String id) => '$contracts/$id';
  static String ticket(String id) => '$tickets/$id';
  static String brief(String id) => '$briefs/$id';
  static String editBrief(String id) => '$briefs/$id/edit';

  /// Écran d'une ressource ciblée par une notification ou un push (§50).
  static String? forEntity(String entityType, String entityId) => switch (entityType) {
    'project' => project(entityId),
    'deliverable' => deliverable(entityId),
    'document' => documents,
    'invoice' => invoice(entityId),
    'payment_declaration' => payments,
    'contract' => contract(entityId),
    'support_ticket' => ticket(entityId),
    'client_conversation' => conversation(entityId),
    'project_brief' => editBrief(entityId),
    _ => null,
  };
}

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:astra_client/core/network/api_client.dart';
import 'package:astra_client/core/network/realtime.dart';
import 'package:astra_client/core/storage/cache_store.dart';
import 'package:astra_client/core/storage/token_storage.dart';
import 'package:astra_client/core/utils/json.dart';
import 'package:astra_client/main.dart';

import 'fake_http.dart';

/// Temps réel inerte : aucun accès réseau ni minuterie dans les tests.
class SilentRealtime extends RealtimeService {
  SilentRealtime() : super(storage: InMemoryTokenStorage(), refreshSession: () async {});

  @override
  void start() {}
}

const allPermissions = [
  'view_project',
  'view_document',
  'download_document',
  'view_invoice',
  'submit_payment_proof',
  'view_contract',
  'send_message',
  'create_ticket',
  'validate_deliverable',
  'view_financial_data',
  'manage_company_users',
];

Json companyJson() => {
  'id': 'co1',
  'name': 'ABC Solutions',
  'email': 'contact@abc.example',
  'phone': null,
  'address': null,
  'website': null,
  'sector': 'Retail',
  'has_logo': false,
};

Json meJson({List<String> permissions = allPermissions}) => {
  'id': 'a1',
  'email': 'jean@abc.example',
  'full_name': 'Jean Dupont',
  'job_title': 'Directeur',
  'phone': null,
  'permissions': permissions,
  'company': companyJson(),
};

Json projectSummaryJson({String id = 'p1', String status = 'in_progress', int pending = 1}) => {
  'id': id,
  'name': 'Application mobile',
  'status': status,
  'progress': 65,
  'due_date': '2026-12-31',
  'updated_at': '2026-10-01T10:00:00Z',
  'pending_validations': pending,
};

Json projectDetailJson() => {
  ...projectSummaryJson(),
  'description': 'Refonte',
  'summary': 'Nouvelle application de fidélité',
  'created_at': '2026-09-01T10:00:00Z',
  'team': [
    {'full_name': 'Awa Diallo', 'job_title': 'Cheffe de projet', 'is_lead': true},
  ],
  'deliverable_count': 1,
  'document_count': 0,
  'conversation_id': null,
};

Json versionJson() => {
  'id': 'v1',
  'number': 1,
  'notes': 'Première version',
  'link_url': null,
  'file': {'name': 'maquette.pdf', 'content_type': 'application/pdf', 'size_bytes': 2048},
  'published_at': '2026-10-02T10:00:00Z',
};

Json deliverableJson({String status = 'awaiting_validation', bool canReview = true}) => {
  'id': 'd1',
  'project_id': 'p1',
  'project_name': 'Application mobile',
  'title': 'Maquette application',
  'description': null,
  'status': status,
  'requires_validation': true,
  'due_date': null,
  'current_version': versionJson(),
  'updated_at': '2026-10-02T10:00:00Z',
  'versions': [versionJson()],
  'reviews': <Json>[],
  'can_review': canReview,
};

Json invoiceJson({String status = 'unpaid', String remaining = '1500000.00'}) => {
  'id': 'i1',
  'number': 'AST-2026-042',
  'title': 'Acompte',
  'project_id': null,
  'project_name': null,
  'amount': '1500000.00',
  'currency': 'XOF',
  'issue_date': '2026-10-01',
  'due_date': '2026-10-31',
  'paid_amount': '0.00',
  'remaining_amount': remaining,
  'status': 'issued',
  'payment_status': status,
  'is_overdue': false,
  'file': null,
  'declarations': <Json>[],
  'can_declare': true,
};

Json dashboardJson() => {
  'company': companyJson(),
  'active_projects': 2,
  'completed_projects': 1,
  'pending_validations': 1,
  'unread_messages': 3,
  'unread_notifications': 0,
  'pending_invoices': 1,
  'open_tickets': 0,
  'actions': [
    {
      'kind': 'validation_required',
      'title': 'Maquette application',
      'subtitle': 'Application mobile',
      'entity_type': 'deliverable',
      'entity_id': 'd1',
      'created_at': '2026-10-02T10:00:00Z',
    },
    {
      'kind': 'payment_due',
      'title': 'Facture AST-2026-042',
      'subtitle': '1500000.00 XOF',
      'entity_type': 'invoice',
      'entity_id': 'i1',
      'created_at': null,
    },
  ],
  'deadlines': <Json>[],
  'recent_documents': <Json>[],
};

/// Backend simulé : `"GET /client/me"` → corps JSON (ou [FakeResponse]).
class FakeBackend {
  FakeBackend([Map<String, Object?>? routes]) : routes = {...defaultRoutes(), ...?routes};

  final Map<String, Object?> routes;
  late final adapter = FakeHttpAdapter(_handle);

  static Map<String, Object?> defaultRoutes() => {
    'GET /client/me': meJson(),
    'GET /client/dashboard': dashboardJson(),
    'GET /client/notifications': <Json>[],
    'GET /client/conversations': <Json>[],
    'GET /client/projects': [projectSummaryJson()],
    'GET /client/projects/p1': projectDetailJson(),
    'GET /client/projects/p1/timeline': <Json>[],
    'GET /client/deliverables': [deliverableJson()],
    'GET /client/deliverables/d1': deliverableJson(),
    'GET /client/documents': <Json>[],
    'GET /client/invoices': [invoiceJson()],
    'GET /client/invoices/i1': invoiceJson(),
    'PUT /client/devices': null,
    'GET /client/briefs': <Json>[],
    'GET /client/briefs/questionnaire': {
      'sections': [
        {
          'id': 'company',
          'title': 'Présentation de l\'entreprise',
          'intro': 'Parlez-nous de vous.',
          'questions': [
            {'id': 'company_name', 'label': 'Nom', 'type': 'long_text', 'required': true},
            {
              'id': 'logo_types',
              'label': 'Quel type de logo vous semble adapté ?',
              'type': 'multi_choice',
              'required': false,
              'choices': [
                {'value': 'wordmark', 'label': 'Logotype', 'description': 'Le nom seul (Google)'},
                {'value': 'icon', 'label': 'Icône', 'description': 'Un symbole seul (Apple)'},
              ],
            },
            {'id': 'deadline', 'label': 'Date', 'type': 'date', 'required': false},
            {'id': 'files', 'label': 'Références', 'type': 'files', 'required': false},
          ],
        },
      ],
    },
    'POST /client/briefs': {
      'id': 'b1',
      'status': 'draft',
      'title': 'Projet',
      'answers': <String, Object?>{},
      'current_section': 'company',
      'progress': <Object>[],
      'missing_required': <Object>[],
      'files': <Object>[],
      'submitted_at': null,
      'project_id': null,
      'created_at': '2026-10-07T10:00:00Z',
      'updated_at': '2026-10-07T10:00:00Z',
    },
  };

  List<RequestOptions> get requests => adapter.requests;

  Future<FakeResponse> _handle(RequestOptions options) async {
    final key = '${options.method} ${options.path}';
    if (!routes.containsKey(key)) return const FakeResponse(404, {'detail': 'Introuvable.'});
    final value = routes[key];
    if (value is FakeResponse) return value;
    if (value is FakeResponse Function(RequestOptions)) return value(options);
    return FakeResponse(200, value);
  }

  Dio dio() => fakeDio(adapter);
}

List<Override> appOverrides(FakeBackend backend, {bool loggedIn = true, CacheStore? cache}) => [
  tokenStorageProvider.overrideWithValue(
    InMemoryTokenStorage(
      loggedIn ? const AuthTokens(accessToken: 'access', refreshToken: 'refresh') : null,
    ),
  ),
  dioProvider.overrideWithValue(backend.dio()),
  cacheStoreProvider.overrideWithValue(cache ?? MemoryCacheStore()),
  realtimeServiceProvider.overrideWithValue(SilentRealtime()),
];

Widget clientApp(FakeBackend backend, {bool loggedIn = true, CacheStore? cache}) => ProviderScope(
  overrides: appOverrides(backend, loggedIn: loggedIn, cache: cache),
  child: const AstraClientApp(),
);

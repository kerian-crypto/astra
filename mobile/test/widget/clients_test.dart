import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:astra_hub/core/router/app_router.dart';
import 'package:astra_hub/core/storage/token_storage.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fake_http.dart';

/// Faux serveur enrichi des routes de l'Espace clients.
class ClientsBackend extends FakeBackend {
  ClientsBackend(this.extra);

  final Map<String, Object?> extra;
  final List<RequestOptions> sent = [];

  @override
  Future<FakeResponse> handle(RequestOptions options) async {
    final key = '${options.method} ${options.path}';
    if (extra.containsKey(key)) {
      sent.add(options);
      final value = extra[key];
      return value is FakeResponse ? value : FakeResponse(200, value);
    }
    return super.handle(options);
  }
}

const tokens = AuthTokens(accessToken: 'a', refreshToken: 'r');

Map<String, Object?> briefJson({String status = 'submitted', String? projectId}) => {
  'id': 'b1',
  'status': status,
  'title': 'Identité visuelle / logo — Sifter',
  'answers': {
    'company_name': 'Sifter',
    'colors': {
      'selected': ['orange', 'violet'],
      'other': null,
    },
  },
  'current_section': 'delivery',
  'progress': <Object>[],
  'missing_required': <Object>[],
  'files': <Object>[],
  'submitted_at': '2026-10-07T10:00:00Z',
  'project_id': projectId,
  'created_at': '2026-10-07T09:00:00Z',
  'updated_at': '2026-10-07T10:00:00Z',
  'company_id': 'co1',
  'company_name': 'Sifter',
  'company_self_registered': true,
  'author_name': 'Hermann Bonns',
  'proposed_plan': {
    'name': 'Identité visuelle / logo — Sifter',
    'description': null,
    'objective': null,
    'priority': 'medium',
    'due_date': '2027-08-03',
    'budget': null,
    'lead_id': null,
    'member_ids': <Object>[],
    'phases': [
      {
        'name': 'Cadrage',
        'description': null,
        'due_date': '2026-11-01',
        'tasks': [
          {'title': 'Étude du cahier des charges', 'description': null, 'priority': 'high'},
        ],
      },
      {
        'name': 'Création du logo',
        'description': null,
        'due_date': '2027-02-01',
        'tasks': [
          {
            'title': 'Moodboard et pistes graphiques',
            'description': 'Couleurs : Orange, Violet',
            'priority': 'high',
          },
        ],
      },
    ],
  },
};

Map<String, Object?> questionnaireJson() => {
  'sections': [
    {
      'id': 'company',
      'title': 'Présentation de l\'entreprise',
      'intro': '',
      'questions': [
        {
          'id': 'company_name',
          'label': 'Nom de votre entreprise',
          'type': 'long_text',
          'required': true,
          'choices': <Object>[],
        },
      ],
    },
    {
      'id': 'visual',
      'title': 'Univers graphique',
      'intro': '',
      'questions': [
        {
          'id': 'colors',
          'label': 'Couleurs souhaitées',
          'type': 'multi_choice',
          'required': false,
          'choices': [
            {'value': 'orange', 'label': 'Orange'},
            {'value': 'violet', 'label': 'Violet'},
          ],
        },
      ],
    },
  ],
};

void main() {
  setUpAll(() => initializeDateFormatting('fr'));

  Future<ClientsBackend> pump(WidgetTester tester, Size size, Map<String, Object?> extra) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = ClientsBackend(extra);
    await tester.pumpWidget(backend.app(storedTokens: tokens));
    await tester.pumpAndSettle();
    return backend;
  }

  void go(WidgetTester tester, String route) {
    ProviderScope.containerOf(tester.element(find.byType(MaterialApp)))
        .read(routerProvider)
        .go(route);
  }

  testWidgets('wide screens use a navigation rail with the client space entry', (tester) async {
    await pump(tester, const Size(1400, 900), {});

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Espace clients'), findsOneWidget);
  });

  testWidgets('phones keep the bottom navigation bar', (tester) async {
    await pump(tester, const Size(420, 900), {});

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('a client brief shows answers, deduced plan, and becomes a project', (tester) async {
    final backend = await pump(tester, const Size(1400, 1000), {
      'GET /clients/briefs/b1': briefJson(),
      'GET /clients/briefs/questionnaire': questionnaireJson(),
      'GET /users': <Object>[],
      'POST /clients/briefs/b1/convert': briefJson(status: 'converted', projectId: 'p1'),
    });

    go(tester, '/clients/briefs/b1');
    await tester.pumpAndSettle();

    expect(find.text('Prospect inscrit'), findsOneWidget);
    expect(find.text('Orange, Violet'), findsOneWidget);
    expect(find.textContaining('Plan déduit · 2 phases, 2 tâches'), findsOneWidget);

    await tester.tap(find.text('Créer le projet').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Créer le projet').last);
    await tester.pumpAndSettle();

    final convert = backend.sent.lastWhere((o) => o.path == '/clients/briefs/b1/convert');
    final plan = (convert.data as Map)['plan'] as Map;
    expect((plan['phases'] as List).length, 2);
  });

  testWidgets('client space lists companies and briefs', (tester) async {
    await pump(tester, const Size(1200, 900), {
      'GET /clients/companies': [
        {
          'id': 'co1',
          'name': 'Sifter',
          'email': null,
          'phone': null,
          'address': null,
          'website': null,
          'sector': 'Tertiaire',
          'internal_notes': null,
          'is_active': true,
          'has_logo': false,
          'created_at': '2026-10-07T10:00:00Z',
          'account_count': 1,
          'project_count': 0,
        },
      ],
      'GET /clients/briefs': [briefJson()],
    });

    go(tester, '/clients');
    await tester.pumpAndSettle();
    expect(find.text('Sifter'), findsOneWidget);

    await tester.tap(find.text('Cahiers des charges'));
    await tester.pumpAndSettle();
    expect(find.text('Identité visuelle / logo — Sifter'), findsOneWidget);
    expect(find.text('À étudier'), findsOneWidget);
  });
}

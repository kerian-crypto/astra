import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fake_http.dart';

Map<String, Object?> questionnaireJson() => {
  'sections': [
    {
      'id': 'company',
      'title': 'Présentation de l\'entreprise',
      'intro': 'Parlez-nous de vous.',
      'questions': [
        {
          'id': 'company_name',
          'label': 'Nom de votre entreprise',
          'type': 'long_text',
          'required': true,
        },
        {
          'id': 'competitors',
          'label': 'Vos concurrents',
          'type': 'list',
          'required': false,
          'max_items': 5,
        },
      ],
    },
    {
      'id': 'visual',
      'title': 'Univers graphique',
      'intro': 'Vos goûts.',
      'questions': [
        {
          'id': 'colors',
          'label': 'Couleurs souhaitées (2 à 3)',
          'type': 'multi_choice',
          'required': true,
          'max_items': 2,
          'allow_other': false,
          'choices': [
            {'value': 'orange', 'label': 'Orange'},
            {'value': 'violet', 'label': 'Violet'},
            {'value': 'blue', 'label': 'Bleu'},
          ],
        },
      ],
    },
  ],
};

Map<String, Object?> briefJson({String status = 'draft', Map<String, Object?>? answers}) => {
  'id': 'b1',
  'status': status,
  'title': 'Projet — Sifter',
  'answers': answers ?? <String, Object?>{},
  'current_section': 'company',
  'progress': <Object>[],
  'missing_required': <Object>[],
  'files': <Object>[],
  'submitted_at': null,
  'project_id': null,
  'created_at': '2026-10-07T10:00:00Z',
  'updated_at': '2026-10-07T10:00:00Z',
};

void main() {
  setUpAll(() => initializeDateFormatting('fr'));

  Future<void> phone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('questionnaire: required answers, choice limit, save per step and submit', (
    tester,
  ) async {
    await phone(tester);
    final saved = <Map<String, Object?>>[];
    final backend = FakeBackend({
      'GET /client/dashboard': {...dashboardJson(), 'needs_onboarding': true},
      'GET /client/briefs/questionnaire': questionnaireJson(),
      'POST /client/briefs': briefJson(),
      'PATCH /client/briefs/b1': (RequestOptions o) {
        final body =
            (o.data is String ? jsonDecode(o.data as String) : o.data) as Map<String, Object?>;
        saved.add(body);
        return FakeResponse(200, briefJson(answers: body['answers']! as Map<String, Object?>));
      },
      'POST /client/briefs/b1/submit': briefJson(status: 'submitted'),
      'GET /client/briefs': <Object>[],
    });
    await tester.pumpWidget(clientApp(backend));
    await tester.pumpAndSettle();

    expect(find.text('Parlez-nous de votre projet'), findsOneWidget);
    await tester.tap(find.text('Commencer'));
    await tester.pumpAndSettle();
    expect(find.text('Bienvenue !'), findsOneWidget);

    await tester.tap(find.text('Commencer'));
    await tester.pumpAndSettle();
    expect(find.text('Présentation de l\'entreprise'), findsOneWidget);

    // Réponse obligatoire manquante : on reste sur l'étape.
    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    expect(find.text('Cette réponse est obligatoire.'), findsOneWidget);
    // Seule la position (étape « entreprise ») a été enregistrée.
    expect(saved.single['answers'], isEmpty);

    await tester.enterText(find.byType(TextField).first, 'Sifter');
    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    expect(saved.last['answers'], {'company_name': 'Sifter'});
    expect(saved.last['current_section'], 'visual');

    await tester.tap(find.text('Orange'));
    await tester.tap(find.text('Violet'));
    await tester.tap(find.text('Bleu'));
    await tester.pump();
    expect(find.text('2 choix maximum.'), findsOneWidget);

    await tester.tap(find.text('Voir le récapitulatif'));
    await tester.pumpAndSettle();
    expect(find.text('Récapitulatif'), findsOneWidget);
    expect(find.text('Orange, Violet'), findsOneWidget);

    await tester.tap(find.text('Envoyer à Astra'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Merci infiniment'), findsOneWidget);
    expect(backend.requests.any((r) => r.path == '/client/briefs/b1/submit'), isTrue);
  });

  testWidgets('registration opens the questionnaire right away', (tester) async {
    await phone(tester);
    final backend = FakeBackend({
      'POST /client/auth/register': const FakeResponse(201, {
        'access_token': 'a',
        'refresh_token': 'r',
        'token_type': 'bearer',
        'expires_in': 900,
      }),
      'GET /client/briefs/questionnaire': questionnaireJson(),
      'POST /client/briefs': briefJson(),
    });
    await tester.pumpWidget(clientApp(backend, loggedIn: false));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Nouveau client ? Créer mon espace'));
    await tester.pumpAndSettle();
    Future<void> fill(String label, String value) async {
      final field = find.widgetWithText(TextFormField, label);
      await tester.ensureVisible(field);
      await tester.enterText(field, value);
    }

    await fill('Nom de votre entreprise', 'Sifter');
    await fill('Votre nom complet', 'Hermann Bonns');
    await fill('Adresse email', 'hermann@example.com');
    await fill('Mot de passe', 'mot-de-passe-solide');
    await fill('Confirmer le mot de passe', 'mot-de-passe-solide');
    await tester.ensureVisible(find.text('Créer mon espace').last);
    await tester.tap(find.text('Créer mon espace').last);
    await tester.pumpAndSettle();

    final register = backend.requests.firstWhere((r) => r.path == '/client/auth/register');
    expect((register.data as Map)['company_name'], 'Sifter');
    expect(find.text('Bienvenue !'), findsOneWidget);
  });
}

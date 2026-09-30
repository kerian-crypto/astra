import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../helpers/fake_backend.dart';

void main() {
  setUpAll(() => initializeDateFormatting('fr'));

  Future<FakeBackend> pumpApp(WidgetTester tester, {FakeBackend? backend}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    final fake = backend ?? FakeBackend();
    await tester.pumpWidget(fake.app());
    await tester.pumpAndSettle();
    return fake;
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  Future<void> next(WidgetTester tester) async {
    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
  }

  testWidgets('step by step registration sends every field', (tester) async {
    final backend = await pumpApp(tester);
    await tester.tap(find.text('Pas encore de compte ? Créer un compte'));
    await tester.pumpAndSettle();

    // Étape 1 : identité, validée avant de passer à la suite.
    expect(find.text('Étape 1 sur 6'), findsOneWidget);
    await next(tester);
    expect(find.text('Saisissez votre prénom.'), findsOneWidget);
    await tester.enterText(field('Prénom'), 'Awa');
    await tester.enterText(field('Nom'), 'Diallo');
    await tester.enterText(field('Email professionnel'), 'awa@astra');
    await next(tester);
    expect(find.text('Email invalide.'), findsOneWidget);
    await tester.enterText(field('Email professionnel'), 'awa@astra.example.com');
    await next(tester);

    // Étape 2 : photo facultative.
    expect(find.text('Photo de profil'), findsOneWidget);
    expect(find.text('AD'), findsOneWidget); // initiales en aperçu
    await next(tester);

    // Étape 3 : poste et rôle souhaité.
    await next(tester);
    expect(find.text('Indiquez votre poste.'), findsOneWidget);
    await tester.enterText(field('Poste'), 'Designer UX');
    await tester.tap(find.text('Manager'));
    await tester.pumpAndSettle();
    expect(find.text('Un manager peut créer et piloter des projets.'), findsOneWidget);
    await next(tester);

    // Étape 4 : compétences (saisie libre, suggestion, pas de doublon).
    await tester.enterText(find.widgetWithText(TextField, 'Ajouter une compétence'), 'Figma');
    await tester.tap(find.byTooltip('Ajouter la compétence'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Ajouter une compétence'), 'figma');
    await tester.tap(find.byTooltip('Ajouter la compétence'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('UX/UI'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, 'Figma'), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'UX/UI'), findsOneWidget);
    await next(tester);

    // Étape 5 : mot de passe.
    await tester.enterText(field('Mot de passe'), 'court');
    await tester.enterText(field('Confirmation du mot de passe'), 'autre');
    await next(tester);
    expect(find.text('Au moins 12 caractères.'), findsOneWidget);
    expect(find.text('Les mots de passe ne correspondent pas.'), findsOneWidget);
    await tester.enterText(field('Mot de passe'), 'un-mot-de-passe-solide');
    await tester.enterText(field('Confirmation du mot de passe'), 'un-mot-de-passe-solide');
    await next(tester);

    // Étape 6 : récapitulatif puis envoi.
    expect(find.text('Awa Diallo'), findsOneWidget);
    expect(find.text('Figma, UX/UI'), findsOneWidget);
    expect(find.text('Manager'), findsOneWidget);
    await tester.tap(find.text('Envoyer ma demande'));
    await tester.pumpAndSettle();

    expect(find.text('Demande envoyée'), findsOneWidget);
    final form = backend.writes['POST /auth/register']! as FormData;
    final fields = {for (final entry in form.fields) entry.key: entry.value};
    expect(fields['first_name'], 'Awa');
    expect(fields['last_name'], 'Diallo');
    expect(fields['email'], 'awa@astra.example.com');
    expect(fields['job_title'], 'Designer UX');
    expect(fields['requested_access_level'], 'manager');
    expect(fields['password'], 'un-mot-de-passe-solide');
    expect(form.fields.where((e) => e.key == 'skills').map((e) => e.value), ['Figma', 'UX/UI']);

    await tester.tap(find.text('Retour à la connexion'));
    await tester.pumpAndSettle();
    expect(find.text('Se connecter'), findsOneWidget);
  });

  testWidgets('summary lets you go back to edit a step', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Pas encore de compte ? Créer un compte'));
    await tester.pumpAndSettle();
    await tester.enterText(field('Prénom'), 'Awa');
    await tester.enterText(field('Nom'), 'Diallo');
    await tester.enterText(field('Email professionnel'), 'awa@astra.example.com');
    await next(tester);
    await next(tester);
    await tester.enterText(field('Poste'), 'Designer');
    await next(tester);
    await next(tester);
    await tester.enterText(field('Mot de passe'), 'un-mot-de-passe-solide');
    await tester.enterText(field('Confirmation du mot de passe'), 'un-mot-de-passe-solide');
    await next(tester);

    await tester.tap(find.byTooltip('Modifier : Poste'));
    await tester.pumpAndSettle();
    expect(find.text('Étape 3 sur 6'), findsOneWidget);

    await tester.tap(find.text('Précédent'));
    await tester.pumpAndSettle();
    expect(find.text('Étape 2 sur 6'), findsOneWidget);
  });

  testWidgets('pending account gets an explicit message at login', (tester) async {
    await pumpApp(tester, backend: FakeBackend()..pendingLogin = true);

    await tester.enterText(field('Email'), 'awa@astra.example.com');
    await tester.enterText(field('Mot de passe'), 'un-mot-de-passe-solide');
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();

    expect(
      find.text('Votre compte est en attente de validation par un administrateur.'),
      findsOneWidget,
    );
  });

  testWidgets('admin approves a request with the final role', (tester) async {
    final backend = await pumpApp(tester, backend: FakeBackend(accessLevel: 'admin'));
    await tester.enterText(field('Email'), 'ada@astra.example.com');
    await tester.enterText(field('Mot de passe'), 'secret-password');
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(NavigationBar), matching: find.text('Profil')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Demandes d\'inscription'));
    await tester.pumpAndSettle();
    expect(find.text('Awa Diallo'), findsOneWidget);
    expect(find.text('Rôle souhaité : Manager'), findsOneWidget);

    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Membre'));
    await tester.tap(find.text('Activer le compte'));
    await tester.pumpAndSettle();

    expect(backend.writes['POST /users/u9/approve'], {'access_level': 'member'});
    expect(find.text('Aucune demande en attente.'), findsOneWidget);
  });

  testWidgets('admin rejects a request after confirmation', (tester) async {
    final backend = await pumpApp(tester, backend: FakeBackend(accessLevel: 'admin'));
    await tester.enterText(field('Email'), 'ada@astra.example.com');
    await tester.enterText(field('Mot de passe'), 'secret-password');
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(NavigationBar), matching: find.text('Profil')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Demandes d\'inscription'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Refuser').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refuser').last);
    await tester.pumpAndSettle();

    expect(backend.calls, contains('POST /users/u9/reject'));
  });

  testWidgets('non-admins do not see registration requests', (tester) async {
    await pumpApp(tester, backend: FakeBackend(accessLevel: 'member'));
    await tester.enterText(field('Email'), 'ada@astra.example.com');
    await tester.enterText(field('Mot de passe'), 'secret-password');
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(NavigationBar), matching: find.text('Profil')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Demandes d\'inscription'), findsNothing);
  });
}

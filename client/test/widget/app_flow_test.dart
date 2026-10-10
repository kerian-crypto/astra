import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:astra_client/core/storage/cache_store.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fake_http.dart';

Future<void> setSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(() => initializeDateFormatting('fr'));

  testWidgets('phone: dashboard shows what to do now, with a bottom navigation bar', (
    tester,
  ) async {
    await setSize(tester, const Size(400, 860));
    final backend = FakeBackend();

    await tester.pumpWidget(clientApp(backend));
    await tester.pumpAndSettle();

    expect(find.text('À faire maintenant'), findsOneWidget);
    expect(find.text('Maquette application'), findsOneWidget);
    expect(find.text('Facture AST-2026-042'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('large screen: navigation rail with brand and company', (tester) async {
    await setSize(tester, const Size(1366, 900));
    await tester.pumpWidget(clientApp(FakeBackend()));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Espace client'), findsOneWidget);
    expect(find.text('ABC Solutions'), findsWidgets);
  });

  testWidgets('tablet: compact rail with labels', (tester) async {
    await setSize(tester, const Size(800, 1100));
    await tester.pumpWidget(clientApp(FakeBackend()));
    await tester.pumpAndSettle();

    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.extended, isFalse);
  });

  testWidgets('approving a deliverable sends the review and confirms', (tester) async {
    await setSize(tester, const Size(400, 860));
    final backend = FakeBackend({
      'POST /client/deliverables/d1/reviews': (RequestOptions o) =>
          FakeResponse(201, deliverableJson(status: 'approved', canReview: false)),
    });
    await tester.pumpWidget(clientApp(backend));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Maquette application'));
    await tester.pumpAndSettle();
    expect(find.text('Votre validation est attendue'), findsOneWidget);

    await tester.tap(find.text('Approuver'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmer l\'approbation'));
    await tester.pumpAndSettle();

    final review = backend.requests.lastWhere((r) => r.path == '/client/deliverables/d1/reviews');
    final form = review.data as FormData;
    expect(Map.fromEntries(form.fields)['action'], 'approve');
    expect(find.textContaining('validation a été transmise'), findsOneWidget);
  });

  testWidgets('requesting changes requires a reason', (tester) async {
    await setSize(tester, const Size(400, 860));
    final backend = FakeBackend();
    await tester.pumpWidget(clientApp(backend));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Maquette application'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Demander une modification'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Envoyer la demande'));
    await tester.pump();

    expect(find.text('Précisez le motif de la modification.'), findsOneWidget);
    expect(backend.requests.where((r) => r.method == 'POST'), isEmpty);
  });

  testWidgets('declaring a payment validates the amount then posts the form', (tester) async {
    await setSize(tester, const Size(400, 900));
    final backend = FakeBackend({
      'POST /client/invoices/i1/payment-declarations': (RequestOptions o) =>
          const FakeResponse(201, {
            'id': 'pd1',
            'invoice_id': 'i1',
            'invoice_number': 'AST-2026-042',
            'amount': '1500000.00',
            'currency': 'XOF',
            'paid_on': '2026-10-07',
            'method': 'mobile_money',
            'reference': 'OM-1',
            'note': null,
            'status': 'declared',
            'confirmed_amount': null,
            'rejection_reason': null,
            'proof': null,
            'declared_by_name': 'Jean Dupont',
            'reviewed_at': null,
            'created_at': '2026-10-07T10:00:00Z',
          }),
    });
    await tester.pumpWidget(clientApp(backend));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Facture AST-2026-042'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Aucun paiement n\'est effectué'), findsOneWidget);

    await tester.tap(find.text('Déclarer un paiement'));
    await tester.pumpAndSettle();
    final amount = find.widgetWithText(TextFormField, 'Montant payé');
    await tester.enterText(amount, '2000000');
    await tester.dragUntilVisible(
      find.text('Envoyer la déclaration'),
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.tap(find.text('Envoyer la déclaration'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(amount, find.byType(ListView), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(find.text('Le montant dépasse le reste à payer.'), findsOneWidget);

    await tester.enterText(amount, '1500000');
    await tester.enterText(find.widgetWithText(TextFormField, 'Référence de transaction'), 'OM-1');
    await tester.dragUntilVisible(
      find.text('Envoyer la déclaration'),
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.tap(find.text('Envoyer la déclaration'));
    await tester.pumpAndSettle();

    final post = backend.requests.lastWhere((r) => r.method == 'POST');
    final fields = Map.fromEntries((post.data as FormData).fields);
    expect(fields['amount'], '1500000.00');
    expect(fields['reference'], 'OM-1');
  });

  testWidgets('empty project list explains what happens next', (tester) async {
    await setSize(tester, const Size(400, 860));
    await tester.pumpWidget(clientApp(FakeBackend({'GET /client/projects': <Object>[]})));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Projets').last);
    await tester.pumpAndSettle();

    expect(find.text('Aucun projet disponible'), findsOneWidget);
  });

  testWidgets('forbidden section shows an access message', (tester) async {
    await setSize(tester, const Size(400, 860));
    await tester.pumpWidget(
      clientApp(
        FakeBackend({
          'GET /client/projects': const FakeResponse(403, {'detail': 'Refusé'}),
        }),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Projets').last);
    await tester.pumpAndSettle();

    expect(find.text('Accès non autorisé'), findsOneWidget);
  });

  testWidgets('offline start shows cached data with a banner', (tester) async {
    await setSize(tester, const Size(400, 860));
    final cache = MemoryCacheStore();
    await cache.write('/client/me', meJson());
    await cache.write('/client/dashboard', dashboardJson());
    final backend = FakeBackend();
    final offline = FakeBackend({
      for (final key in backend.routes.keys)
        key: (RequestOptions o) =>
            throw DioException(requestOptions: o, type: DioExceptionType.connectionError),
    });

    await tester.pumpWidget(clientApp(offline, cache: cache));
    await tester.pumpAndSettle();

    expect(find.textContaining('Hors ligne'), findsOneWidget);
    expect(find.text('À faire maintenant'), findsOneWidget);
  });

  testWidgets('logged out users see the login screen with the activation entry', (tester) async {
    await setSize(tester, const Size(400, 860));
    await tester.pumpWidget(clientApp(FakeBackend(), loggedIn: false));
    await tester.pumpAndSettle();

    expect(find.text('Se connecter'), findsOneWidget);
    await tester.tap(find.text('J\'ai un lien d\'activation'));
    await tester.pumpAndSettle();
    expect(find.text('Activer mon accès'), findsOneWidget);
  });

  testWidgets('login screen shows backend errors', (tester) async {
    await setSize(tester, const Size(400, 860));
    final backend = FakeBackend({
      'POST /client/auth/login': const FakeResponse(401, {
        'detail': 'Email ou mot de passe incorrect.',
      }),
    });
    await tester.pumpWidget(clientApp(backend, loggedIn: false));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Adresse email'), 'jean@abc.example');
    await tester.enterText(find.widgetWithText(TextFormField, 'Mot de passe'), 'mauvais');
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();

    expect(find.text('Email ou mot de passe incorrect.'), findsOneWidget);
  });
}

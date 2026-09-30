import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:astra_hub/features/ai/presentation/ai_plan_view.dart';

import '../helpers/fake_backend.dart';

/// Parcours des formulaires et des écrans « connaissance » / IA.
void main() {
  setUpAll(() => initializeDateFormatting('fr'));

  Future<FakeBackend> start(WidgetTester tester, {FakeBackend? backend}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    final fake = backend ?? FakeBackend();
    await tester.pumpWidget(fake.app());
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'ada@astra.example.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Mot de passe'), 'secret-password');
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();
    return fake;
  }

  Future<void> tab(WidgetTester tester, String label) async {
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
    await tester.pumpAndSettle();
  }

  Future<void> openProject(WidgetTester tester) async {
    await tab(tester, 'Projets');
    await tester.tap(find.text('MarketCM V2'));
    await tester.pumpAndSettle();
  }

  testWidgets('create a task from the project then comment and tick the checklist', (tester) async {
    final backend = await start(tester);
    await openProject(tester);

    await tester.tap(find.byTooltip('Nouvelle tâche'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Créer la tâche'));
    await tester.pump();
    expect(find.text('Le titre est requis.'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Titre'), 'Écran de connexion');
    await tester.tap(find.text('Créer la tâche'));
    await tester.pumpAndSettle();

    final created = backend.writes['POST /projects/p1/tasks']! as Map<String, dynamic>;
    expect(created['title'], 'Écran de connexion');
    expect(created['priority'], 'medium');
    expect(find.text('Écrans principaux'), findsOneWidget); // détail ouvert

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(backend.writes['PATCH /tasks/t1/checklist/i1'], {'is_done': true});

    await tester.enterText(find.widgetWithText(TextField, 'Ajouter un élément'), 'Profil');
    await tester.tap(find.byTooltip('Ajouter'));
    await tester.pumpAndSettle();
    expect(backend.writes['POST /tasks/t1/checklist'], {'label': 'Profil'});

    await tester.scrollUntilVisible(
      find.widgetWithText(TextField, 'Écrire un commentaire'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.enterText(find.widgetWithText(TextField, 'Écrire un commentaire'), 'Top');
    await tester.tap(find.byTooltip('Envoyer'));
    await tester.pumpAndSettle();
    expect(backend.writes['POST /tasks/t1/comments'], {'body': 'Top'});
  });

  testWidgets('assignee picker shows ranked suggestions with reasons', (tester) async {
    final backend = await start(tester);
    await openProject(tester);
    await tester.tap(find.text('Tâches'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Maquettes'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Non attribuée'));
    await tester.pumpAndSettle();
    expect(find.text('Compétences utiles : Flutter'), findsOneWidget);
    await tester.tap(find.text('Ada Lovelace · suggéré'));
    await tester.pumpAndSettle();

    expect(backend.writes['PATCH /tasks/t1'], {'assignee_id': 'u1'});
  });

  testWidgets('kanban long press moves a card', (tester) async {
    final backend = await start(tester);
    await openProject(tester);
    await tester.tap(find.text('Tâches'));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Maquettes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review').last);
    await tester.pumpAndSettle();

    expect(backend.writes['PATCH /tasks/t1'], {'status': 'review'});
  });

  testWidgets('project documents list is shown', (tester) async {
    await start(tester);
    await openProject(tester);

    await tester.tap(find.text('Documents'));
    await tester.pumpAndSettle();

    expect(find.text('Cahier des charges'), findsOneWidget);
    expect(find.byTooltip('Ajouter un document'), findsOneWidget);
  });

  testWidgets('plan a meeting', (tester) async {
    final backend = await start(tester);
    await tab(tester, 'Réunions');

    await tester.tap(find.text('Planifier'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Titre'), 'Kick-off');
    await tester.tap(find.text('Planifier').last);
    await tester.pumpAndSettle();
    expect(find.text('Choisissez la date et l\'heure.'), findsOneWidget);

    await tester.tap(find.text('Date et heure'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Bob Martin'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Planifier').last);
    await tester.pumpAndSettle();

    final body = backend.writes['POST /meetings']! as Map<String, dynamic>;
    expect(body['title'], 'Kick-off');
    expect(body['participant_ids'], ['u2']);
  });

  testWidgets('meeting: AI summary is validated before saving', (tester) async {
    final backend = await start(tester);
    await tab(tester, 'Réunions');
    await tester.tap(find.text('Point hebdo'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Analyser avec ASTRA AI'));
    await tester.pumpAndSettle();
    expect(find.text('Choix de FastAPI.'), findsOneWidget);
    expect(find.text('Hébergement ?', findRichText: true), findsNothing);
    // Réunion sans projet : les tâches ne peuvent pas être créées.
    expect(find.text('Rattachez la réunion à un projet pour créer ces tâches.'), findsOneWidget);

    await tester.tap(find.text('Valider et enregistrer'));
    await tester.pumpAndSettle();

    expect(backend.writes['POST /meetings/mt1/decisions'], {
      'title': 'Adopter FastAPI',
      'description': 'Backend',
    });
    expect(backend.writes.containsKey('POST /meetings/mt1/tasks'), isFalse);
  });

  testWidgets('meeting: edit minutes and add a decision', (tester) async {
    final backend = await start(tester);
    await tab(tester, 'Réunions');
    await tester.tap(find.text('Point hebdo'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Modifier le compte rendu'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Nouveau compte rendu');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(backend.writes['PATCH /meetings/mt1'], {
      'minutes': 'Nouveau compte rendu',
      'status': 'done',
    });

    await tester.tap(find.byTooltip('Ajouter une décision'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Recruter');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(backend.writes['POST /meetings/mt1/decisions'], {'title': 'Recruter'});
  });

  testWidgets('validated decision becomes a project', (tester) async {
    final backend = FakeBackend();
    backend.decisions.add({
      'id': 'd1',
      'title': 'MarketCM V2',
      'description': null,
      'status': 'validated',
      'meeting_id': 'mt1',
      'project_id': null,
      'resulting_project_id': null,
    });
    await start(tester, backend: backend);
    await tab(tester, 'Réunions');
    await tester.tap(find.text('Point hebdo'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Créer le projet'), 200);
    await tester.tap(find.text('Créer le projet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Créer'));
    await tester.pumpAndSettle();

    final body = backend.writes['POST /decisions/d1/project']! as Map<String, dynamic>;
    expect(body['name'], 'MarketCM V2');
    expect((body['phases'] as List).length, 4);
    expect(find.text('Aperçu'), findsOneWidget);
  });

  testWidgets('AI plan: propose then validate', (tester) async {
    final backend = await start(tester);
    await tester.tap(find.text('Planifier un projet'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Décrivez l\'idée'),
      'Une plateforme de gestion des formations',
    );
    await tester.pump();
    await tester.tap(find.text('Proposer un plan'));
    await tester.pumpAndSettle();
    expect(find.text('Plateforme de formations'), findsOneWidget);
    expect(find.text('Phase 1 — Analyse'), findsOneWidget);
    expect(backend.writes.containsKey('POST /projects/from-plan'), isFalse);

    await tester.scrollUntilVisible(
      find.text('Valider et créer le projet'),
      200,
      scrollable: find
          .descendant(of: find.byType(AiPlanView), matching: find.byType(Scrollable))
          .first,
    );
    await tester.tap(find.text('Valider et créer le projet'));
    await tester.pumpAndSettle();

    expect(
      (backend.writes['POST /projects/from-plan']! as Map<String, dynamic>)['name'],
      'Plateforme de formations',
    );
  });

  testWidgets('health screen with AI synthesis', (tester) async {
    await start(tester);
    await tester.scrollUntilVisible(
      find.text('État de santé d\'Astra'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('État de santé d\'Astra'));
    await tester.pumpAndSettle();
    expect(find.text('Migrer la base'), findsOneWidget);

    await tester.tap(find.text('Synthèse par ASTRA AI'));
    await tester.pumpAndSettle();

    expect(find.text('- Décision à exécuter.'), findsOneWidget);
  });

  testWidgets('general documents from the profile', (tester) async {
    await start(tester);
    await tab(tester, 'Profil');

    await tester.tap(find.text('Documents d\'Astra'));
    await tester.pumpAndSettle();

    expect(find.text('Cahier des charges'), findsOneWidget);
  });

  testWidgets('start a direct conversation and react to a message', (tester) async {
    final backend = await start(tester);
    await tab(tester, 'Messages');

    await tester.tap(find.byTooltip('Nouvelle conversation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bob Martin'));
    await tester.pumpAndSettle();
    expect(backend.writes['POST /channels/direct'], {'user_id': 'u2'});

    await tester.longPress(find.text('Bonjour à tous'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Réagir 👍'));
    await tester.pumpAndSettle();

    expect(find.text('👍 1'), findsOneWidget);
  });
}

import 'package:astra_hub/core/storage/token_storage.dart';
import 'package:astra_hub/features/ai/presentation/ai_chat_view.dart';
import 'package:astra_hub/features/ai/presentation/ronda_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intl/date_symbol_data_local.dart';

import '../helpers/fake_backend.dart';

void main() {
  setUpAll(() => initializeDateFormatting('fr'));

  Future<FakeBackend> pumpApp(
    WidgetTester tester, {
    FakeBackend? backend,
    AuthTokens? storedTokens,
  }) async {
    // Écran de téléphone réaliste : les grilles et listes s'y affichent entières.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    final fake = backend ?? FakeBackend();
    await tester.pumpWidget(fake.app(storedTokens: storedTokens));
    await tester.pumpAndSettle();
    return fake;
  }

  Future<void> logIn(WidgetTester tester) async {
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'ada@astra.example.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Mot de passe'), 'secret-password');
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
    await tester.pumpAndSettle();
  }

  testWidgets('dashboard shows today, Astra stats and my work', (tester) async {
    await pumpApp(tester);
    expect(find.byType(Image), findsOneWidget); // logo sur l'écran de connexion

    await logIn(tester);

    expect(find.text('Bonjour Ada'), findsOneWidget);
    expect(find.text('Projets actifs'), findsOneWidget);
    expect(find.text('Projets à surveiller'), findsOneWidget);
    expect(find.text('1 tâche(s) en retard'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Point hebdo'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('En retard (1)'), findsOneWidget);
    expect(find.text('Maquettes'), findsOneWidget);
  });

  testWidgets('kanban, task detail and status change', (tester) async {
    final backend = await pumpApp(tester);
    await logIn(tester);
    await openTab(tester, 'Projets');
    await tester.tap(find.text('MarketCM V2'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tâches'));
    await tester.pumpAndSettle();
    expect(find.text('À FAIRE · 1'), findsOneWidget);

    await tester.tap(find.text('Maquettes'));
    await tester.pumpAndSettle();
    expect(find.text('Écrans principaux'), findsOneWidget);
    expect(find.text('Checklist (0/1)'), findsOneWidget);

    await tester.tap(find.text('En cours'));
    await tester.pumpAndSettle();

    expect(backend.calls, contains('PATCH /tasks/t1'));
    expect(backend.tasks.first['status'], 'in_progress');
  });

  testWidgets('restores an existing session straight to the dashboard', (tester) async {
    await pumpApp(
      tester,
      storedTokens: const AuthTokens(accessToken: 'a', refreshToken: 'r'),
    );

    expect(find.text('Bonjour Ada'), findsOneWidget);
  });

  testWidgets('manager creates a project and lands on its page', (tester) async {
    await pumpApp(tester, backend: FakeBackend(projects: []));
    await logIn(tester);
    await openTab(tester, 'Projets');
    expect(find.text('Vous ne participez encore à aucun projet.'), findsOneWidget);

    await tester.tap(find.text('Nouveau'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Créer'));
    await tester.pump();
    expect(find.text('Le nom est requis.'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Nom'), 'Astra Hub');
    await tester.tap(find.text('Créer'));
    await tester.pumpAndSettle();

    expect(find.text('Astra Hub'), findsWidgets);
    expect(find.text('Idée'), findsOneWidget);
  });

  testWidgets('plain members do not see the create button', (tester) async {
    await pumpApp(tester, backend: FakeBackend(accessLevel: 'member'));
    await logIn(tester);
    await openTab(tester, 'Projets');

    expect(find.text('Nouveau'), findsNothing);
  });

  testWidgets('dashboard error offers a retry', (tester) async {
    final backend = FakeBackend()..failDashboard = true;
    await pumpApp(tester, backend: backend);
    await logIn(tester);
    expect(find.text('Serveur indisponible.'), findsOneWidget);

    backend.failDashboard = false;
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();

    expect(find.text('Projets actifs'), findsOneWidget);
  });

  testWidgets('messages: open channel and send a message', (tester) async {
    final backend = await pumpApp(tester);
    await logIn(tester);

    await openTab(tester, 'Messages');
    await tester.tap(find.text('# général'));
    await tester.pumpAndSettle();
    expect(find.text('Bonjour à tous'), findsOneWidget);
    expect(backend.calls, contains('POST /channels/c1/read'));

    // Micro tant que le champ est vide, bouton Envoyer dès qu'on écrit.
    expect(find.byTooltip('Message vocal'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Message'), 'Salut Bob');
    await tester.pump();
    expect(find.byTooltip('Message vocal'), findsNothing);
    await tester.tap(find.byTooltip('Envoyer'));
    await tester.pumpAndSettle();

    expect(find.text('Salut Bob'), findsOneWidget);
  });

  testWidgets('meeting detail: validate a decision', (tester) async {
    final backend = FakeBackend();
    backend.decisions.add({
      'id': 'd1',
      'meeting_id': 'mt1',
      'project_id': null,
      'title': 'Adopter FastAPI',
      'description': null,
      'status': 'proposed',
      'created_by_id': 'u1',
      'validated_by_id': null,
      'validated_at': null,
      'resulting_project_id': null,
      'created_at': '2026-09-01T10:00:00Z',
    });
    await pumpApp(tester, backend: backend);
    await logIn(tester);
    await openTab(tester, 'Réunions');
    await tester.tap(find.text('Point hebdo'));
    await tester.pumpAndSettle();
    expect(find.text('On valide FastAPI.'), findsOneWidget);
    expect(find.text('Analyser avec ASTRA AI'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Valider'), 200);
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();

    expect(backend.decisions.first['status'], 'validated');
    expect(find.text('Créer le projet'), findsOneWidget);
  });

  final utcOffset = DateTime.now().timeZoneOffset.inMinutes;

  Future<void> openAi(WidgetTester tester) async {
    await tester.tap(find.byTooltip('ASTRA AI').first);
    await tester.pumpAndSettle();
  }

  /// Envoie la question sans avancer jusqu'à la relecture (Ronda « réfléchit »).
  Future<void> sendOnly(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  Future<void> waitForRonda(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  }

  testWidgets('ASTRA AI answers with sources once Ronda is done', (tester) async {
    await pumpApp(tester);
    await logIn(tester);
    await openAi(tester);

    await tester.tap(find.text('Quels sont mes travaux prioritaires aujourd\'hui ?'));
    await sendOnly(tester);
    expect(find.textContaining('Ronda réfléchit'), findsOneWidget);

    await waitForRonda(tester);

    expect(find.text(FakeBackend.aiAnswer), findsOneWidget);
    expect(find.text('[1] Maquettes'), findsOneWidget);
    expect(find.textContaining('Ronda réfléchit'), findsNothing);
  });

  testWidgets('ASTRA AI conversations are kept in the history', (tester) async {
    final backend = await pumpApp(tester);
    await logIn(tester);
    await openAi(tester);
    await tester.tap(find.text('Quels projets sont actuellement en retard ?'));
    await tester.pumpAndSettle();
    await waitForRonda(tester);

    await tester.tap(find.byTooltip('Nouvelle conversation'));
    await tester.pumpAndSettle();
    expect(find.text(FakeBackend.aiAnswer), findsNothing);

    await tester.tap(find.byTooltip('Historique'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quels projets sont actuellement en retard ?').last);
    await tester.pumpAndSettle();

    expect(find.text(FakeBackend.aiAnswer), findsOneWidget);
    expect(backend.calls, contains('GET /ai/conversations/ac1'));
  });

  testWidgets('Ronda keeps answering after leaving the conversation', (tester) async {
    await pumpApp(tester);
    await logIn(tester);
    await openAi(tester);
    await tester.tap(find.text('Quelles décisions ont été prises récemment ?'));
    await sendOnly(tester);
    expect(find.textContaining('Ronda réfléchit'), findsOneWidget);

    // Le membre quitte l'écran avant la fin de la réponse…
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AiChatView), findsNothing);

    // … et la retrouve terminée en revenant.
    await openAi(tester);
    expect(find.text(FakeBackend.aiAnswer), findsOneWidget);
    expect(find.text('Quelles décisions ont été prises récemment ?'), findsWidgets);
  });

  testWidgets('a follow-up question continues the same conversation', (tester) async {
    final backend = await pumpApp(tester);
    await logIn(tester);
    await openAi(tester);
    await tester.tap(find.text('Quels sont mes travaux prioritaires aujourd\'hui ?'));
    await tester.pumpAndSettle();
    await waitForRonda(tester);

    await tester.enterText(find.byType(TextField), 'Et demain ?');
    await tester.tap(find.byTooltip('Envoyer'));
    await tester.pumpAndSettle();
    await waitForRonda(tester);

    expect(backend.writes['POST /ai/conversations/ac1/messages'], {
      'question': 'Et demain ?',
      'utc_offset_minutes': utcOffset,
    });
    expect(find.text(FakeBackend.aiAnswer), findsNWidgets(2));
  });

  testWidgets('delete a conversation from the history', (tester) async {
    final backend = await pumpApp(tester);
    await logIn(tester);
    await openAi(tester);
    await tester.tap(find.text('Quels sont mes travaux prioritaires aujourd\'hui ?'));
    await tester.pumpAndSettle();
    await waitForRonda(tester);

    await tester.tap(find.byTooltip('Historique'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Supprimer'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
    await tester.pumpAndSettle();

    expect(backend.aiConversations, isEmpty);
    expect(find.text('Aucune conversation avec Ronda pour le moment.'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Nouvelle conversation'), findsOneWidget);
  });

  testWidgets('the Ronda button reads the screen being viewed', (tester) async {
    final backend = await pumpApp(tester);
    await logIn(tester);
    await openTab(tester, 'Projets');
    await tester.tap(find.text('MarketCM V2'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(RondaOverlay.buttonKey));
    await tester.pumpAndSettle();
    expect(find.text('Ronda lit : Ce projet'), findsOneWidget);
    // Déjà dans l'assistant : le bouton global disparaît.
    expect(find.byKey(RondaOverlay.buttonKey), findsNothing);

    await tester.enterText(find.byType(TextField), 'Résume ce projet');
    await tester.tap(find.byTooltip('Envoyer'));
    await waitForRonda(tester);

    expect(backend.writes['POST /ai/conversations'], {
      'question': 'Résume ce projet',
      'focus': {'type': 'project', 'id': 'p1'},
      'utc_offset_minutes': utcOffset,
    });
    expect(find.text('À propos de : project'), findsOneWidget);
    expect(find.text(FakeBackend.aiAnswer), findsOneWidget);
  });

  testWidgets('the screen context can be removed before asking', (tester) async {
    final backend = await pumpApp(tester);
    await logIn(tester);
    await openTab(tester, 'Projets');
    await tester.tap(find.text('MarketCM V2'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(RondaOverlay.buttonKey));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Retirer ce contexte'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Bonjour');
    await tester.tap(find.byTooltip('Envoyer'));
    await waitForRonda(tester);

    expect(backend.writes['POST /ai/conversations'], {
      'question': 'Bonjour',
      'utc_offset_minutes': utcOffset,
    });
  });

  testWidgets('the Ronda button is hidden before login', (tester) async {
    await pumpApp(tester);

    expect(find.byKey(RondaOverlay.buttonKey), findsNothing);
    await logIn(tester);
    expect(find.byKey(RondaOverlay.buttonKey), findsOneWidget);
  });

  testWidgets('Ronda proposes an action that the member validates', (tester) async {
    final backend = await pumpApp(tester);
    await logIn(tester);
    await openAi(tester);
    await tester.enterText(find.byType(TextField), 'Crée le projet Livreurs');
    await tester.tap(find.byTooltip('Envoyer'));
    await waitForRonda(tester);

    expect(find.text('Ronda propose'), findsOneWidget);
    expect(find.text('Créer le projet « Livreurs »'), findsOneWidget);
    expect(backend.writes.keys.where((k) => k.endsWith('/action')), isEmpty);

    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();

    final decided = backend.writes.entries.singleWhere((e) => e.key.endsWith('/action'));
    expect(decided.value, {'apply': true});
    expect(find.text('Fait'), findsOneWidget);

    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();
    expect(backend.calls, contains('GET /projects/p1'));
  });

  testWidgets('an action proposed by Ronda can be ignored', (tester) async {
    await pumpApp(tester);
    await logIn(tester);
    await openAi(tester);
    await tester.enterText(find.byType(TextField), 'Crée le projet Livreurs');
    await tester.tap(find.byTooltip('Envoyer'));
    await waitForRonda(tester);

    await tester.tap(find.text('Ignorer'));
    await tester.pumpAndSettle();

    expect(find.text('Proposition ignorée'), findsOneWidget);
    expect(find.text('Valider'), findsNothing);
  });

  testWidgets('ASTRA AI explains when disabled', (tester) async {
    await pumpApp(tester, backend: FakeBackend(aiEnabled: false));
    await logIn(tester);

    await openAi(tester);

    expect(find.text('ASTRA AI n\'est pas activée sur ce serveur.'), findsOneWidget);
  });

  testWidgets('search shows hits and opens the task', (tester) async {
    await pumpApp(tester);
    await logIn(tester);

    await tester.tap(find.byTooltip('Rechercher dans Astra').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'maquettes');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('Tâche'), findsOneWidget);

    await tester.tap(find.text('Maquettes'));
    await tester.pumpAndSettle();
    expect(find.text('Écrans principaux'), findsOneWidget);
  });

  testWidgets('notifications open their target and are marked read', (tester) async {
    final backend = await pumpApp(tester);
    await logIn(tester);

    await tester.tap(find.byTooltip('Notifications').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lead vous a attribué une tâche'));
    await tester.pumpAndSettle();

    expect(backend.calls, contains('POST /notifications/n1/read'));
    expect(find.text('Écrans principaux'), findsOneWidget);
  });

  testWidgets('profile links and logout', (tester) async {
    await pumpApp(tester);
    await logIn(tester);
    await openTab(tester, 'Profil');
    expect(find.text('Manager'), findsOneWidget);
    expect(find.text('État de santé d\'Astra'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Se déconnecter'), 200);
    await tester.tap(find.text('Se déconnecter'));
    await tester.pumpAndSettle();

    expect(find.text('Se connecter'), findsOneWidget);
  });
}

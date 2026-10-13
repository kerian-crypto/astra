import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fake_http.dart';

Future<void> _openSecurity(WidgetTester tester, FakeBackend backend) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(clientApp(backend));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Plus'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Sécurité'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Sécurité'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Supprimer mon compte'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Supprimer mon compte'));
  await tester.pumpAndSettle();
}

Future<void> _confirmWith(WidgetTester tester, String password) async {
  await tester.enterText(find.widgetWithText(TextField, 'Mot de passe'), password);
  // La déconnexion efface des fichiers : de vraies E/S, lancées hors du temps simulé.
  await tester.runAsync(() async {
    await tester.tap(find.text('Supprimer définitivement'));
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('fr'));

  // La déconnexion vide le dossier des téléchargements : path_provider simulé.
  setUp(() {
    final temp = Directory.systemTemp.createTempSync('astra-test-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => temp.path,
    );
    addTearDown(() => temp.deleteSync(recursive: true));
  });

  testWidgets('deleting the account sends the password and returns to login', (tester) async {
    final backend = FakeBackend({
      'DELETE /client/me': (RequestOptions o) => const FakeResponse(204),
    });
    await _openSecurity(tester, backend);

    expect(find.textContaining('définitive'), findsWidgets);
    await _confirmWith(tester, 'mon-mot-de-passe');

    final request = backend.requests.lastWhere((r) => r.method == 'DELETE');
    expect(request.path, '/client/me');
    expect(request.data, {'password': 'mon-mot-de-passe'});
    expect(find.text('Se connecter'), findsOneWidget);
    expect(find.text('Votre compte a été supprimé.'), findsOneWidget);
  });

  testWidgets('a wrong password keeps the user signed in and shows the error', (tester) async {
    final backend = FakeBackend({
      'DELETE /client/me': const FakeResponse(400, {'detail': 'Mot de passe incorrect.'}),
    });
    await _openSecurity(tester, backend);

    await _confirmWith(tester, 'mauvais');

    expect(find.text('Mot de passe incorrect.'), findsOneWidget);
    expect(find.text('Se connecter'), findsNothing);
  });

  testWidgets('cancelling sends nothing', (tester) async {
    final backend = FakeBackend();
    await _openSecurity(tester, backend);

    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();

    expect(backend.requests.where((r) => r.method == 'DELETE'), isEmpty);
  });
}

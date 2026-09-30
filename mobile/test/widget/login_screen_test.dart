import 'package:astra_hub/core/network/api_client.dart';
import 'package:astra_hub/core/storage/token_storage.dart';
import 'package:astra_hub/features/auth/presentation/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_http.dart';

void main() {
  late FakeHttpAdapter adapter;

  Future<void> pumpLogin(WidgetTester tester, FakeHandler handler) async {
    adapter = FakeHttpAdapter(handler);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
          dioProvider.overrideWithValue(fakeDio(adapter)),
        ],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  testWidgets('validates empty and malformed input without calling the API', (tester) async {
    await pumpLogin(tester, (_) async => const FakeResponse(500));

    await tester.tap(find.text('Se connecter'));
    await tester.pump();
    expect(find.text('Saisissez votre email.'), findsOneWidget);
    expect(find.text('Saisissez votre mot de passe.'), findsOneWidget);

    await tester.enterText(field('Email'), 'not-an-email');
    await tester.tap(find.text('Se connecter'));
    await tester.pump();
    expect(find.text('Email invalide.'), findsOneWidget);
    expect(adapter.requests, isEmpty);
  });

  testWidgets('shows the backend error when credentials are wrong', (tester) async {
    await pumpLogin(
      tester,
      (_) async => const FakeResponse(401, {'detail': 'Email ou mot de passe incorrect.'}),
    );

    await tester.enterText(field('Email'), 'ada@astra.example.com');
    await tester.enterText(field('Mot de passe'), 'wrong-password');
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('login-error')), findsOneWidget);
    expect(find.text('Email ou mot de passe incorrect.'), findsOneWidget);
  });

  testWidgets('toggles password visibility', (tester) async {
    await pumpLogin(tester, (_) async => const FakeResponse(500));

    TextField passwordField() => tester.widget<TextField>(
      find.descendant(of: field('Mot de passe'), matching: find.byType(TextField)),
    );

    expect(passwordField().obscureText, isTrue);
    await tester.tap(find.byTooltip('Afficher'));
    await tester.pump();
    expect(passwordField().obscureText, isFalse);
  });
}

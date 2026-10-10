import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:astra_client/core/router/app_router.dart';

import '../helpers/fake_backend.dart';

/// Parcourt les écrans principaux à plusieurs largeurs : un débordement de
/// mise en page (RenderFlex overflowed) fait échouer le test.
void main() {
  setUpAll(() => initializeDateFormatting('fr'));

  const sizes = {
    'petit téléphone': Size(340, 720),
    'tablette': Size(820, 1180),
    'grand écran': Size(1440, 900),
  };
  const routes = [
    '/home',
    '/projects',
    '/projects/p1',
    '/deliverables/d1',
    '/messages',
    '/documents',
    '/more',
    '/invoices',
    '/invoices/i1',
    '/invoices/i1/declare',
    '/tickets/new',
    '/profile',
    '/company',
    '/security',
    '/briefs',
    '/briefs/new',
  ];

  for (final MapEntry(key: label, value: size) in sizes.entries) {
    testWidgets('aucun débordement — $label', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(clientApp(FakeBackend()));
      await tester.pumpAndSettle();

      final router = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)))
          .read(routerProvider);
      for (final route in routes) {
        router.go(route);
        await tester.pumpAndSettle();
        final error = tester.takeException();
        expect(
          error,
          isNull,
          reason: '$route ($label)\n${error is FlutterError ? error.toStringDeep() : ''}',
        );
      }
    });
  }
}

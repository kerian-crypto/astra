import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:astra_hub/core/update/app_update.dart';

Map<String, dynamic> release({int build = 3, int minBuild = 1}) => {
  'version': '1.2.0',
  'build_number': build,
  'min_build_number': minBuild,
  'notes': 'Nouveautés',
  'size_bytes': 61000000,
  'sha256': 'a' * 64,
  'download_path': 'releases/$updateAppId/download',
};

void main() {
  test('a newer build is available, an equal one is not', () {
    expect(AppUpdate.fromJson(release(), 2).isAvailable, isTrue);
    expect(AppUpdate.fromJson(release(build: 2), 2).isAvailable, isFalse);
  });

  test('builds below the minimum must update', () {
    expect(AppUpdate.fromJson(release(minBuild: 3), 2).isMandatory, isTrue);
    expect(AppUpdate.fromJson(release(), 2).isMandatory, isFalse);
  });

  testWidgets('optional update can be postponed, mandatory one cannot', (tester) async {
    Future<void> show(AppUpdate update) => tester.pumpWidget(
      MaterialApp(home: UpdateDialog(update: update, service: UpdateService())),
    );

    await show(AppUpdate.fromJson(release(), 2));
    expect(find.text('Nouvelle version disponible'), findsOneWidget);
    expect(find.text('Plus tard'), findsOneWidget);
    expect(find.textContaining('Version 1.2.0'), findsOneWidget);

    await show(AppUpdate.fromJson(release(minBuild: 3), 2));
    expect(find.text('Mise à jour requise'), findsOneWidget);
    expect(find.text('Plus tard'), findsNothing);
  });
}

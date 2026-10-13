import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:astra_client/core/config/app_config.dart';
import 'package:astra_client/core/push/push_messaging.dart';
import 'package:astra_client/core/push/push_service.dart';
import 'package:astra_client/core/router/app_router.dart';
import 'package:astra_client/core/theme/client_theme.dart';
import 'package:astra_client/core/update/app_update.dart';

Future<void> main() async {
  if (kReleaseMode && !AppConfig.apiBaseUrl.startsWith('https://')) {
    throw StateError('API_BASE_URL doit être en HTTPS pour une build release.');
  }
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr');
  final messaging = await FirebasePushMessaging.initialize();
  runApp(
    ProviderScope(
      overrides: [pushMessagingProvider.overrideWithValue(messaging)],
      child: const AstraClientApp(),
    ),
  );
}

class AstraClientApp extends ConsumerWidget {
  const AstraClientApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Astra Client',
      debugShowCheckedModeBanner: false,
      theme: ClientTheme.light,
      darkTheme: ClientTheme.dark,
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: router,
      // Version Play : les mises à jour passent par le Store, jamais par un APK.
      builder: (_, child) => AppConfig.isPlayStoreBuild
          ? child ?? const SizedBox.shrink()
          : UpdateGate(
              navigatorKey: router.routerDelegate.navigatorKey,
              child: child ?? const SizedBox.shrink(),
            ),
    );
  }
}

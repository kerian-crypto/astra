import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:astra_hub/core/config/app_config.dart';
import 'package:astra_hub/core/push/push_messaging.dart';
import 'package:astra_hub/core/push/push_service.dart';
import 'package:astra_hub/core/router/app_router.dart';
import 'package:astra_hub/core/theme/astra_theme.dart';
import 'package:astra_hub/features/ai/presentation/ronda_overlay.dart';

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
      child: const AstraApp(),
    ),
  );
}

class AstraApp extends ConsumerWidget {
  const AstraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Astra Hub',
      debugShowCheckedModeBanner: false,
      theme: AstraTheme.darkTheme,
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: ref.watch(routerProvider),
      builder: (_, child) => RondaOverlay(child: child ?? const SizedBox.shrink()),
    );
  }
}

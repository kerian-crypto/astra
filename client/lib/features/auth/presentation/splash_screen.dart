import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_client/core/theme/client_theme.dart';
import 'package:astra_client/core/widgets/state_views.dart';
import 'package:astra_client/core/widgets/ui.dart';
import 'package:astra_client/features/auth/presentation/auth_controller.dart';

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    return Scaffold(
      body: Center(
        child: auth.hasError
            ? ErrorStateView(
                error: auth.error!,
                onRetry: () => ref.read(authControllerProvider.notifier).retry(),
              )
            : const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BrandMark(size: 64),
                  SizedBox(height: Space.xxl),
                  SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
                ],
              ),
      ),
    );
  }
}

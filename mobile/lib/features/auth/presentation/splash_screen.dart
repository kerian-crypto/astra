import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_hub/core/widgets/astra_logo.dart';
import 'package:astra_hub/core/widgets/async_value_view.dart';
import 'package:astra_hub/features/auth/presentation/auth_controller.dart';

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    return Scaffold(
      body: auth.hasError
          ? ErrorRetry(
              message: '${auth.error}',
              onRetry: () => ref.read(authControllerProvider.notifier).retry(),
            )
          : const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AstraMark(width: 160),
                  SizedBox(height: 32),
                  CircularProgressIndicator(),
                ],
              ),
            ),
    );
  }
}

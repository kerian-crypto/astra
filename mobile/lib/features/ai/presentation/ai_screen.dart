import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:astra_hub/core/widgets/async_value_view.dart';
import 'package:astra_hub/features/ai/data/ai.dart';
import 'package:astra_hub/features/ai/data/ai_repository.dart';
import 'package:astra_hub/features/ai/presentation/ai_chat_view.dart';
import 'package:astra_hub/features/ai/presentation/ai_plan_view.dart';

/// ASTRA AI (spec §11-13) : assistant et planification. L'IA propose,
/// l'humain décide.
class AiScreen extends ConsumerWidget {
  const AiScreen({super.key});

  static const analyseWorkPrompt =
      'Analyse mon travail : qu\'est-ce qui est prioritaire aujourd\'hui et qu\'est-ce qui est en retard ?';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = GoRouterState.of(context).uri.queryParameters;
    final status = ref.watch(aiStatusProvider);
    return DefaultTabController(
      length: 2,
      initialIndex: query['tab'] == 'plan' ? 1 : 0,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('ASTRA AI'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Assistant'),
              Tab(text: 'Planifier un projet'),
            ],
          ),
        ),
        body: AsyncValueView(
          value: status,
          onRetry: () => ref.invalidate(aiStatusProvider),
          data: (s) => !s.isAvailable
              ? EmptyState(
                  icon: Icons.cloud_off,
                  message: s.enabled
                      ? 'Ronda est injoignable pour le moment. Réessayez plus tard.'
                      : 'ASTRA AI n\'est pas activée sur ce serveur.',
                )
              : TabBarView(
                  children: [
                    AiChatView(
                      initialQuestion: query['ask'] == 'analyse' ? analyseWorkPrompt : null,
                      focus: AiFocus.parse(query['focus']),
                    ),
                    const AiPlanView(),
                  ],
                ),
        ),
      ),
    );
  }
}

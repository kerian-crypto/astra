import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_hub/core/network/api_exception.dart';
import 'package:astra_hub/core/utils/formatting.dart';
import 'package:astra_hub/core/widgets/async_value_view.dart';
import 'package:astra_hub/features/ai/data/ai.dart';
import 'package:astra_hub/features/ai/data/ai_repository.dart';

/// Historique ASTRA AI du compte connecté. Renvoie l'id de la conversation
/// choisie, ou `null` si la feuille est fermée sans choix.
Future<String?> showAiHistory(BuildContext context) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => const FractionallySizedBox(heightFactor: 0.75, child: _AiHistorySheet()),
);

class _AiHistorySheet extends ConsumerWidget {
  const _AiHistorySheet();

  Future<void> _delete(BuildContext context, WidgetRef ref, AiConversationSummary item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer la conversation ?'),
        content: Text('« ${item.title} » et les réponses de Ronda seront supprimées.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(aiRepositoryProvider).deleteConversation(item.id);
      if (ref.read(currentAiConversationProvider) == item.id) {
        ref.read(currentAiConversationProvider.notifier).open(null);
      }
      ref.invalidate(aiConversationsProvider);
    } on ApiException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref.watch(aiConversationsProvider);
    final current = ref.watch(currentAiConversationProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('Historique', style: Theme.of(context).textTheme.titleMedium),
        ),
        Expanded(
          child: AsyncValueView(
            value: conversations,
            onRetry: () => ref.invalidate(aiConversationsProvider),
            data: (items) => items.isEmpty
                ? const EmptyState(
                    icon: Icons.history,
                    message: 'Aucune conversation avec Ronda pour le moment.',
                  )
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (_, index) {
                      final item = items[index];
                      return ListTile(
                        selected: item.id == current,
                        title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          item.isPending ? 'Ronda répond…' : formatShortMoment(item.updatedAt),
                        ),
                        leading: item.isPending
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.chat_bubble_outline),
                        trailing: IconButton(
                          tooltip: 'Supprimer',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(context, ref, item),
                        ),
                        onTap: () => Navigator.pop(context, item.id),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

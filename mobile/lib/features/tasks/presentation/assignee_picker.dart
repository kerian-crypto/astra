import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_hub/core/widgets/async_value_view.dart';
import 'package:astra_hub/features/knowledge/data/knowledge.dart';
import 'package:astra_hub/features/members/presentation/member_avatar.dart';
import 'package:astra_hub/features/projects/data/project.dart';
import 'package:astra_hub/features/tasks/data/task.dart';
import 'package:astra_hub/features/tasks/data/task_repository.dart';

/// Choix fait par l'humain : `memberId` nul = retirer l'attribution.
typedef AssigneeChoice = ({String? memberId});

final _suggestionsProvider = FutureProvider.autoDispose.family<List<AssignmentSuggestion>, String>(
  (ref, taskId) => ref.watch(taskRepositoryProvider).suggestions(taskId),
);

/// Liste des membres, classés par pertinence (compétences, charge) : l'outil
/// propose avec ses raisons, le responsable décide (spec §14).
Future<AssigneeChoice?> showAssigneePicker(
  BuildContext context, {
  required Task task,
  required ProjectDetail project,
}) {
  return showModalBottomSheet<AssigneeChoice>(
    context: context,
    isScrollControlled: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      builder: (_, controller) => _Picker(task: task, scrollController: controller),
    ),
  );
}

class _Picker extends ConsumerWidget {
  const _Picker({required this.task, required this.scrollController});

  final Task task;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestions = ref.watch(_suggestionsProvider(task.id));
    return AsyncValueView(
      value: suggestions,
      onRetry: () => ref.invalidate(_suggestionsProvider(task.id)),
      data: (items) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.all(16),
        children: [
          Text('Attribuer la tâche', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Classement suggéré selon les compétences et la charge actuelle.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          for (final (index, s) in items.indexed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: MemberAvatar(member: s.member),
              title: Text(index == 0 ? '${s.member.fullName} · suggéré' : s.member.fullName),
              subtitle: Text(s.reasons.join('\n')),
              isThreeLine: s.reasons.length > 1,
              selected: s.member.id == task.assignee?.id,
              onTap: () => Navigator.pop(context, (memberId: s.member.id)),
            ),
          if (task.assignee != null)
            TextButton.icon(
              onPressed: () => Navigator.pop(context, (memberId: null)),
              icon: const Icon(Icons.person_off_outlined),
              label: const Text('Retirer l\'attribution'),
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:astra_hub/core/network/api_exception.dart';
import 'package:astra_hub/core/router/routes.dart';
import 'package:astra_hub/core/theme/astra_theme.dart';
import 'package:astra_hub/core/utils/formatting.dart';
import 'package:astra_hub/core/widgets/async_value_view.dart';
import 'package:astra_hub/features/home/data/work.dart';
import 'package:astra_hub/features/projects/data/project.dart';
import 'package:astra_hub/features/tasks/data/task.dart';
import 'package:astra_hub/features/tasks/data/task_repository.dart';
import 'package:astra_hub/features/tasks/presentation/task_widgets.dart';

/// Kanban À FAIRE → EN COURS → REVIEW → TERMINÉ (spec §8).
///
/// Sur mobile, les colonnes défilent horizontalement ; une carte se déplace
/// par appui long (menu des statuts), plus fiable qu'un glisser-déposer
/// sur petit écran.
class KanbanBoard extends ConsumerWidget {
  const KanbanBoard({required this.project, super.key});

  final ProjectDetail project;

  static const columnWidth = 280.0;

  Future<void> _move(BuildContext context, WidgetRef ref, Task task, TaskStatus status) async {
    try {
      await ref.read(taskRepositoryProvider).update(task.id, {'status': status.apiName});
      ref
        ..invalidate(projectTasksProvider(project.project.id))
        ..invalidate(myWorkProvider);
    } on ApiException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _chooseStatus(BuildContext context, WidgetRef ref, Task task) async {
    final status = await showModalBottomSheet<TaskStatus>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text('Déplacer « ${task.title} »')),
            for (final status in TaskStatus.values)
              ListTile(
                leading: Icon(Icons.circle, size: 12, color: taskStatusColor(status)),
                title: Text(status.label),
                selected: status == task.status,
                onTap: () => Navigator.pop(sheetContext, status),
              ),
          ],
        ),
      ),
    );
    if (status != null && status != task.status && context.mounted) {
      await _move(context, ref, task, status);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectId = project.project.id;
    final tasks = ref.watch(projectTasksProvider(projectId));
    return RefreshIndicator(
      onRefresh: () => ref.refresh(projectTasksProvider(projectId).future),
      child: AsyncValueView(
        value: tasks,
        onRetry: () => ref.invalidate(projectTasksProvider(projectId)),
        data: (items) => ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(12),
          children: [
            for (final status in TaskStatus.values)
              _Column(
                status: status,
                tasks: items.where((t) => t.status == status).toList(),
                onLongPress: project.canContribute
                    ? (task) => _chooseStatus(context, ref, task)
                    : null,
              ),
          ],
        ),
      ),
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({required this.status, required this.tasks, this.onLongPress});

  final TaskStatus status;
  final List<Task> tasks;
  final void Function(Task task)? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: KanbanBoard.columnWidth,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AstraTheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AstraTheme.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Icon(Icons.circle, size: 10, color: taskStatusColor(status)),
                const SizedBox(width: 8),
                Text(
                  '${status.label.toUpperCase()} · ${tasks.length}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
          ),
          Expanded(
            child: tasks.isEmpty
                ? Center(child: Text('Aucune tâche', style: Theme.of(context).textTheme.bodySmall))
                : ListView.separated(
                    itemCount: tasks.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, index) => _Card(task: tasks[index], onLongPress: onLongPress),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.task, this.onLongPress});

  final Task task;
  final void Function(Task task)? onLongPress;

  @override
  Widget build(BuildContext context) {
    final due = task.dueDate;
    final overdue = task.isOverdue(DateTime.now());
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AstraTheme.radius),
        onTap: () => context.push(Routes.task(task.id)),
        onLongPress: onLongPress == null ? null : () => onLongPress!(task),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.flag, size: 16, color: priorityColor(task.priority)),
                  const SizedBox(width: 6),
                  Expanded(child: Text(task.title, maxLines: 3, overflow: TextOverflow.ellipsis)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                [
                  task.assignee?.fullName ?? 'Non attribuée',
                  if (due != null) formatDate(due),
                ].join(' · '),
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: overdue ? AstraTheme.error : null),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

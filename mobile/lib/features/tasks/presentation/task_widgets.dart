import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:astra_hub/core/router/routes.dart';
import 'package:astra_hub/core/theme/astra_theme.dart';
import 'package:astra_hub/core/utils/formatting.dart';
import 'package:astra_hub/features/projects/data/project.dart';
import 'package:astra_hub/features/tasks/data/task.dart';

Color priorityColor(Priority priority) => switch (priority) {
  Priority.low => AstraTheme.textSecondary,
  Priority.medium => AstraTheme.secondary,
  Priority.high => AstraTheme.warning,
  Priority.critical => AstraTheme.error,
};

Color taskStatusColor(TaskStatus status) => switch (status) {
  TaskStatus.todo => AstraTheme.textSecondary,
  TaskStatus.inProgress => AstraTheme.secondary,
  TaskStatus.review => AstraTheme.warning,
  TaskStatus.done => AstraTheme.accent,
};

class TaskStatusChip extends StatelessWidget {
  const TaskStatusChip({required this.status, super.key});

  final TaskStatus status;

  @override
  Widget build(BuildContext context) {
    final color = taskStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status.label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class TaskTile extends StatelessWidget {
  const TaskTile({required this.task, this.showAssignee = false, super.key});

  final Task task;
  final bool showAssignee;

  @override
  Widget build(BuildContext context) {
    final overdue = task.isOverdue(DateTime.now());
    final due = task.dueDate;
    final details = [
      if (due != null) 'Échéance ${relativeDay(due)}',
      if (showAssignee) task.assignee?.fullName ?? 'Non attribuée',
    ].join(' · ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        Icons.flag,
        color: priorityColor(task.priority),
        semanticLabel: task.priority.label,
      ),
      title: Text(task.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: details.isEmpty
          ? null
          : Text(details, style: overdue ? const TextStyle(color: AstraTheme.error) : null),
      trailing: TaskStatusChip(status: task.status),
      onTap: () => context.push(Routes.task(task.id)),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {this.count, this.trailing, super.key});

  final String title;
  final int? count;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              count == null ? title : '$title ($count)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:astra_hub/core/network/api_exception.dart';
import 'package:astra_hub/core/router/routes.dart';
import 'package:astra_hub/core/utils/formatting.dart';
import 'package:astra_hub/core/utils/json.dart';
import 'package:astra_hub/core/widgets/async_value_view.dart';
import 'package:astra_hub/features/home/data/work.dart';
import 'package:astra_hub/features/projects/data/project.dart';
import 'package:astra_hub/features/projects/data/project_repository.dart';
import 'package:astra_hub/features/tasks/data/task.dart';
import 'package:astra_hub/features/tasks/data/task_repository.dart';
import 'package:astra_hub/features/tasks/presentation/assignee_picker.dart';
import 'package:astra_hub/features/tasks/presentation/task_discussion.dart';
import 'package:astra_hub/features/tasks/presentation/task_widgets.dart';

class TaskDetailScreen extends ConsumerWidget {
  const TaskDetailScreen({required this.taskId, super.key});

  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(taskDetailProvider(taskId));
    return Scaffold(
      appBar: AppBar(title: const Text('Tâche')),
      body: AsyncValueView(
        value: detail,
        onRetry: () => ref.invalidate(taskDetailProvider(taskId)),
        data: (data) {
          final project = ref.watch(projectDetailProvider(data.task.projectId)).value;
          return RefreshIndicator(
            onRefresh: () => ref.refresh(taskDetailProvider(taskId).future),
            child: _TaskBody(detail: data, project: project),
          );
        },
      ),
    );
  }
}

class _TaskBody extends ConsumerWidget {
  const _TaskBody({required this.detail, required this.project});

  final TaskDetail detail;
  final ProjectDetail? project;

  Task get task => detail.task;
  bool get canEdit => project?.canContribute ?? false;

  Future<void> _update(BuildContext context, WidgetRef ref, Json fields) async {
    try {
      await ref.read(taskRepositoryProvider).update(task.id, fields);
      ref
        ..invalidate(taskDetailProvider(task.id))
        ..invalidate(taskHistoryProvider(task.id))
        ..invalidate(projectTasksProvider(task.projectId))
        ..invalidate(myWorkProvider)
        ..invalidate(dashboardProvider);
    } on ApiException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _pickDueDate(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: task.dueDate ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 3)),
    );
    if (picked != null && context.mounted) {
      await _update(context, ref, {'due_date': isoDate(picked)});
    }
  }

  Future<void> _pickAssignee(BuildContext context, WidgetRef ref) async {
    final choice = await showAssigneePicker(context, task: task, project: project!);
    if (choice != null && context.mounted) {
      await _update(context, ref, {'assignee_id': choice.memberId});
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(task.title, style: textTheme.headlineSmall),
        if (project != null)
          TextButton.icon(
            style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
            onPressed: () => context.go(Routes.project(task.projectId)),
            icon: const Icon(Icons.folder_outlined, size: 18),
            label: Text(project!.project.name),
          ),
        const SizedBox(height: 12),
        SegmentedButton<TaskStatus>(
          segments: [
            for (final status in TaskStatus.values)
              ButtonSegment(value: status, label: Text(status.label)),
          ],
          selected: {task.status},
          showSelectedIcon: false,
          onSelectionChanged: canEdit
              ? (selection) => _update(context, ref, {'status': selection.first.apiName})
              : null,
        ),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.flag, color: priorityColor(task.priority)),
          title: Text('Priorité ${task.priority.label.toLowerCase()}'),
          trailing: canEdit
              ? PopupMenuButton<Priority>(
                  tooltip: 'Changer la priorité',
                  onSelected: (p) => _update(context, ref, {'priority': p.name}),
                  itemBuilder: (_) => [
                    for (final p in Priority.values) PopupMenuItem(value: p, child: Text(p.label)),
                  ],
                )
              : null,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.person_outline),
          title: Text(task.assignee?.fullName ?? 'Non attribuée'),
          subtitle: const Text('Responsable'),
          trailing: canEdit ? const Icon(Icons.edit_outlined) : null,
          onTap: canEdit ? () => _pickAssignee(context, ref) : null,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_outlined),
          title: Text(task.dueDate == null ? 'Pas d\'échéance' : formatDate(task.dueDate!)),
          subtitle: const Text('Échéance'),
          trailing: canEdit ? const Icon(Icons.edit_outlined) : null,
          onTap: canEdit ? () => _pickDueDate(context, ref) : null,
        ),
        if (detail.description != null) ...[
          const SectionTitle('Description'),
          Text(detail.description!),
        ],
        _Checklist(detail: detail, canEdit: canEdit),
        if (detail.dependencies.isNotEmpty) ...[
          SectionTitle('Prérequis', count: detail.dependencies.length),
          for (final dep in detail.dependencies) _TaskRefTile(ref: dep),
        ],
        if (detail.dependents.isNotEmpty) ...[
          SectionTitle('Tâches qui attendent celle-ci', count: detail.dependents.length),
          for (final dep in detail.dependents) _TaskRefTile(ref: dep),
        ],
        TaskDiscussion(taskId: task.id, canComment: canEdit),
      ],
    );
  }
}

class _TaskRefTile extends StatelessWidget {
  const _TaskRefTile({required this.ref});

  final TaskRef ref;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        ref.status == TaskStatus.done ? Icons.check_circle : Icons.radio_button_unchecked,
        color: taskStatusColor(ref.status),
      ),
      title: Text(ref.title),
      trailing: TaskStatusChip(status: ref.status),
      onTap: () => context.pushReplacement(Routes.task(ref.id)),
    );
  }
}

class _Checklist extends ConsumerStatefulWidget {
  const _Checklist({required this.detail, required this.canEdit});

  final TaskDetail detail;
  final bool canEdit;

  @override
  ConsumerState<_Checklist> createState() => _ChecklistState();
}

class _ChecklistState extends ConsumerState<_Checklist> {
  final _newItem = TextEditingController();

  @override
  void dispose() {
    _newItem.dispose();
    super.dispose();
  }

  String get _taskId => widget.detail.task.id;

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      ref.invalidate(taskDetailProvider(_taskId));
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _add() async {
    final label = _newItem.text.trim();
    if (label.isEmpty) return;
    _newItem.clear();
    await _run(() => ref.read(taskRepositoryProvider).addChecklistItem(_taskId, label));
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.detail.checklist;
    if (items.isEmpty && !widget.canEdit) return const SizedBox.shrink();
    final done = items.where((i) => i.isDone).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(items.isEmpty ? 'Checklist' : 'Checklist ($done/${items.length})'),
        for (final item in items)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: item.isDone,
            title: Text(
              item.label,
              style: item.isDone ? const TextStyle(decoration: TextDecoration.lineThrough) : null,
            ),
            onChanged: widget.canEdit
                ? (value) => _run(
                    () => ref
                        .read(taskRepositoryProvider)
                        .setChecklistItem(_taskId, item.id, isDone: value ?? false),
                  )
                : null,
          ),
        if (widget.canEdit)
          TextField(
            controller: _newItem,
            decoration: InputDecoration(
              hintText: 'Ajouter un élément',
              suffixIcon: IconButton(
                tooltip: 'Ajouter',
                icon: const Icon(Icons.add),
                onPressed: _add,
              ),
            ),
            onSubmitted: (_) => _add(),
          ),
      ],
    );
  }
}

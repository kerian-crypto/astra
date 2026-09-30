import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:astra_hub/core/network/api_exception.dart';
import 'package:astra_hub/core/router/routes.dart';
import 'package:astra_hub/core/utils/formatting.dart';
import 'package:astra_hub/core/utils/json.dart';
import 'package:astra_hub/features/home/data/work.dart';
import 'package:astra_hub/features/projects/data/project.dart';
import 'package:astra_hub/features/tasks/data/task_repository.dart';

Future<void> showTaskFormSheet(BuildContext context, ProjectDetail project) async {
  final taskId = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _TaskFormSheet(project: project),
  );
  if (taskId != null && context.mounted) await context.push(Routes.task(taskId));
}

class _TaskFormSheet extends ConsumerStatefulWidget {
  const _TaskFormSheet({required this.project});

  final ProjectDetail project;

  @override
  ConsumerState<_TaskFormSheet> createState() => _TaskFormSheetState();
}

class _TaskFormSheetState extends ConsumerState<_TaskFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  Priority _priority = Priority.medium;
  String? _assigneeId;
  String? _phaseId;
  DateTime? _dueDate;
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 3)),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    final projectId = widget.project.project.id;
    try {
      final created = await ref.read(taskRepositoryProvider).create(projectId, {
        'title': _title.text.trim(),
        if (_description.text.trim().isNotEmpty) 'description': _description.text.trim(),
        'priority': _priority.name,
        'assignee_id': ?_assigneeId,
        'phase_id': ?_phaseId,
        if (_dueDate != null) 'due_date': isoDate(_dueDate!),
      });
      ref
        ..invalidate(projectTasksProvider(projectId))
        ..invalidate(myWorkProvider);
      if (mounted) Navigator.of(context).pop(created.task.id);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final phases = ref.watch(projectPhasesProvider(widget.project.project.id)).value ?? [];
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Nouvelle tâche', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextFormField(
                controller: _title,
                autofocus: true,
                maxLength: 200,
                decoration: const InputDecoration(labelText: 'Titre'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Le titre est requis.' : null,
              ),
              TextFormField(
                controller: _description,
                decoration: const InputDecoration(labelText: 'Description (optionnelle)'),
                minLines: 2,
                maxLines: 5,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<Priority>(
                initialValue: _priority,
                decoration: const InputDecoration(labelText: 'Priorité'),
                items: [
                  for (final p in Priority.values) DropdownMenuItem(value: p, child: Text(p.label)),
                ],
                onChanged: (value) => setState(() => _priority = value ?? _priority),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: _assigneeId,
                decoration: const InputDecoration(labelText: 'Responsable'),
                items: [
                  const DropdownMenuItem(child: Text('Non attribuée')),
                  for (final m in widget.project.assignableMembers)
                    DropdownMenuItem(value: m.id, child: Text(m.fullName)),
                ],
                onChanged: (value) => setState(() => _assigneeId = value),
              ),
              if (phases.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: _phaseId,
                  decoration: const InputDecoration(labelText: 'Phase'),
                  items: [
                    const DropdownMenuItem(child: Text('Aucune')),
                    for (final phase in phases)
                      DropdownMenuItem(value: phase.id, child: Text(phase.name)),
                  ],
                  onChanged: (value) => setState(() => _phaseId = value),
                ),
              ],
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.event),
                label: Text(_dueDate == null ? 'Échéance' : formatDate(_dueDate!)),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                child: const Text('Créer la tâche'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

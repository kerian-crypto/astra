import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:astra_hub/core/network/api_exception.dart';
import 'package:astra_hub/core/router/routes.dart';
import 'package:astra_hub/core/widgets/astra_app_bar.dart';
import 'package:astra_hub/core/widgets/async_value_view.dart';
import 'package:astra_hub/features/auth/presentation/auth_controller.dart';
import 'package:astra_hub/features/projects/data/project.dart';
import 'package:astra_hub/features/projects/data/project_repository.dart';
import 'package:astra_hub/features/projects/presentation/project_widgets.dart';

class ProjectsScreen extends ConsumerWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectListProvider);
    final canCreate = ref.watch(authControllerProvider).value?.canCreateProjects ?? false;

    return Scaffold(
      appBar: const AstraAppBar(title: 'Projets'),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: () => _createProject(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('Nouveau'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(projectListProvider.future),
        child: AsyncValueView(
          value: projects,
          onRetry: () => ref.invalidate(projectListProvider),
          data: (items) => items.isEmpty
              ? const EmptyState(
                  icon: Icons.folder_off_outlined,
                  message: 'Vous ne participez encore à aucun projet.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, index) => _ProjectCard(project: items[index]),
                ),
        ),
      ),
    );
  }

  Future<void> _createProject(BuildContext context, WidgetRef ref) async {
    final created = await showModalBottomSheet<ProjectDetail>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CreateProjectSheet(),
    );
    if (created == null || !context.mounted) return;
    ref.invalidate(projectListProvider);
    context.go(Routes.project(created.project.id));
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.go(Routes.project(project.id)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      project.name,
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  StatusChip(status: project.status),
                ],
              ),
              if (project.objective != null) ...[
                const SizedBox(height: 8),
                Text(project.objective!, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: 8),
              Text(
                'Priorité ${project.priority.label.toLowerCase()}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreateProjectSheet extends ConsumerStatefulWidget {
  const _CreateProjectSheet();

  @override
  ConsumerState<_CreateProjectSheet> createState() => _CreateProjectSheetState();
}

class _CreateProjectSheetState extends ConsumerState<_CreateProjectSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _objective = TextEditingController();
  Priority _priority = Priority.medium;
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _objective.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      final created = await ref
          .read(projectRepositoryProvider)
          .create(name: _name.text, objective: _objective.text, priority: _priority);
      if (mounted) Navigator.of(context).pop(created);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Nouveau projet', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              autofocus: true,
              maxLength: 150,
              decoration: const InputDecoration(labelText: 'Nom'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Le nom est requis.' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _objective,
              decoration: const InputDecoration(labelText: 'Objectif (optionnel)'),
              minLines: 2,
              maxLines: 4,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<Priority>(
              initialValue: _priority,
              decoration: const InputDecoration(labelText: 'Priorité'),
              items: [
                for (final p in Priority.values) DropdownMenuItem(value: p, child: Text(p.label)),
              ],
              onChanged: (value) => setState(() => _priority = value ?? _priority),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 24),
            ElevatedButton(onPressed: _isSubmitting ? null : _submit, child: const Text('Créer')),
          ],
        ),
      ),
    );
  }
}

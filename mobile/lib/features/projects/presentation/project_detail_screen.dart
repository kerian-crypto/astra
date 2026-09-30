import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:astra_hub/core/network/api_exception.dart';
import 'package:astra_hub/core/router/routes.dart';
import 'package:astra_hub/core/utils/formatting.dart';
import 'package:astra_hub/core/widgets/async_value_view.dart';
import 'package:astra_hub/features/chat/data/chat_repository.dart';
import 'package:astra_hub/features/knowledge/presentation/documents_screen.dart';
import 'package:astra_hub/features/members/presentation/member_avatar.dart';
import 'package:astra_hub/features/projects/data/project.dart';
import 'package:astra_hub/features/projects/data/project_repository.dart';
import 'package:astra_hub/features/projects/presentation/project_widgets.dart';
import 'package:astra_hub/features/tasks/data/task_repository.dart';
import 'package:astra_hub/features/tasks/presentation/kanban_board.dart';
import 'package:astra_hub/features/tasks/presentation/task_form_sheet.dart';

class ProjectDetailScreen extends ConsumerWidget {
  const ProjectDetailScreen({required this.projectId, super.key});

  final String projectId;

  Future<void> _openDiscussion(BuildContext context, WidgetRef ref) async {
    try {
      final channel = await ref.read(chatRepositoryProvider).projectChannel(projectId);
      if (context.mounted) await context.push(Routes.chat(channel.id));
    } on ApiException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(projectDetailProvider(projectId));
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(detail.value?.project.name ?? 'Projet'),
          actions: [
            IconButton(
              tooltip: 'Discussion du projet',
              icon: const Icon(Icons.forum_outlined),
              onPressed: () => _openDiscussion(context, ref),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Aperçu'),
              Tab(text: 'Tâches'),
              Tab(text: 'Documents'),
              Tab(text: 'Activité'),
            ],
          ),
        ),
        floatingActionButton: (detail.value?.canContribute ?? false)
            ? FloatingActionButton(
                tooltip: 'Nouvelle tâche',
                onPressed: () => showTaskFormSheet(context, detail.requireValue),
                child: const Icon(Icons.add_task),
              )
            : null,
        body: AsyncValueView(
          value: detail,
          onRetry: () => ref.invalidate(projectDetailProvider(projectId)),
          data: (data) => TabBarView(
            children: [
              RefreshIndicator(
                onRefresh: () => ref.refresh(projectDetailProvider(projectId).future),
                child: _Overview(detail: data),
              ),
              KanbanBoard(project: data),
              DocumentsList(projectId: projectId, canUpload: data.canContribute),
              _ActivityFeed(projectId: projectId),
            ],
          ),
        ),
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.detail});

  final ProjectDetail detail;

  @override
  Widget build(BuildContext context) {
    final project = detail.project;
    final textTheme = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            StatusChip(status: project.status),
            Text('Priorité ${project.priority.label.toLowerCase()}', style: textTheme.bodySmall),
            Text('· Mon rôle : ${detail.myRole.label}', style: textTheme.bodySmall),
          ],
        ),
        if (project.objective != null) _Section(title: 'Objectif', body: project.objective!),
        if (project.description != null) _Section(title: 'Description', body: project.description!),
        if (project.dueDate != null)
          _Section(title: 'Échéance', body: formatDate(project.dueDate!)),
        if (project.budget != null) _Section(title: 'Budget', body: project.budget!),
        const SizedBox(height: 24),
        Text('Membres (${detail.members.length})', style: textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final m in detail.members)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: MemberAvatar(member: m.member),
            title: Text(m.member.fullName),
            subtitle: Text(m.member.jobTitle ?? m.member.email),
            trailing: Text(m.role.label, style: textTheme.bodySmall),
          ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(body),
        ],
      ),
    );
  }
}

class _ActivityFeed extends ConsumerWidget {
  const _ActivityFeed({required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = ref.watch(projectActivityProvider(projectId));
    return RefreshIndicator(
      onRefresh: () => ref.refresh(projectActivityProvider(projectId).future),
      child: AsyncValueView(
        value: activity,
        onRetry: () => ref.invalidate(projectActivityProvider(projectId)),
        data: (items) => items.isEmpty
            ? const EmptyState(icon: Icons.history, message: 'Aucune activité pour le moment.')
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                itemBuilder: (_, index) {
                  final item = items[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.history, size: 20),
                    title: Text(item.describe()),
                    subtitle: Text(formatDateTime(item.createdAt)),
                  );
                },
              ),
      ),
    );
  }
}

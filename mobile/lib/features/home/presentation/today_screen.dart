import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:astra_hub/core/router/routes.dart';
import 'package:astra_hub/core/theme/astra_theme.dart';
import 'package:astra_hub/core/utils/formatting.dart';
import 'package:astra_hub/core/widgets/astra_app_bar.dart';
import 'package:astra_hub/core/widgets/async_value_view.dart';
import 'package:astra_hub/features/auth/presentation/auth_controller.dart';
import 'package:astra_hub/features/home/data/work.dart';
import 'package:astra_hub/features/tasks/data/task.dart';
import 'package:astra_hub/features/tasks/presentation/task_widgets.dart';

/// Écran principal (spec §19) : aujourd'hui, Astra, IA, puis « Mon travail » (§8).
class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  Future<void> _refresh(WidgetRef ref) =>
      Future.wait([ref.refresh(dashboardProvider.future), ref.refresh(myWorkProvider.future)]);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firstName = ref.watch(authControllerProvider).value?.fullName.split(' ').first ?? '';
    final dashboard = ref.watch(dashboardProvider);
    final work = ref.watch(myWorkProvider);

    return Scaffold(
      appBar: AstraAppBar(title: 'Bonjour $firstName'),
      body: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: AsyncValueView(
          value: dashboard,
          onRetry: () => ref.invalidate(dashboardProvider),
          data: (stats) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              const SectionTitle('Aujourd\'hui'),
              _StatGrid(
                stats: [
                  ('Mes tâches', stats.myTodayTasks, false),
                  ('En retard', stats.myOverdueTasks, stats.myOverdueTasks > 0),
                  ('Réunions', stats.myMeetingsToday, false),
                  ('Notifications', stats.unreadNotifications, false),
                ],
              ),
              const SectionTitle('Astra'),
              _StatGrid(
                stats: [
                  ('Projets actifs', stats.activeProjects, false),
                  ('Tâches ouvertes', stats.openTasks, false),
                  ('Tâches en retard', stats.overdueTasks, stats.overdueTasks > 0),
                  (
                    'Projets à surveiller',
                    stats.projectsNeedingAttention.length,
                    stats.projectsNeedingAttention.isNotEmpty,
                  ),
                ],
              ),
              for (final project in stats.projectsNeedingAttention)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.warning_amber, color: AstraTheme.warning),
                  title: Text(project.name),
                  subtitle: Text(project.reason),
                  onTap: () => context.go(Routes.project(project.id)),
                ),
              const SectionTitle('ASTRA AI'),
              const _AiShortcuts(),
              ...work.when(
                data: (data) => _workSections(context, data),
                loading: () => const [
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ],
                error: (error, _) => [
                  ErrorRetry(message: '$error', onRetry: () => ref.invalidate(myWorkProvider)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _workSections(BuildContext context, MyWork work) {
    Widget tasks(String title, List<Task> items) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(title, count: items.length),
        for (final task in items) TaskTile(task: task),
      ],
    );

    final isEmpty =
        work.today.isEmpty &&
        work.overdue.isEmpty &&
        work.priority.isEmpty &&
        work.upcoming.isEmpty &&
        work.meetings.isEmpty;
    if (isEmpty) {
      return const [
        SectionTitle('Mon travail'),
        Text('Rien de prévu : aucune tâche ni réunion à venir.'),
      ];
    }
    return [
      if (work.overdue.isNotEmpty) tasks('En retard', work.overdue),
      if (work.today.isNotEmpty) tasks('Tâches du jour', work.today),
      if (work.priority.isNotEmpty) tasks('Prioritaires', work.priority),
      if (work.upcoming.isNotEmpty) tasks('Prochaines échéances', work.upcoming),
      if (work.meetings.isNotEmpty) ...[
        SectionTitle('Réunions', count: work.meetings.length),
        for (final meeting in work.meetings)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.groups_outlined),
            title: Text(meeting.title),
            subtitle: Text(formatDateTime(meeting.scheduledAt)),
            onTap: () => context.go(Routes.meeting(meeting.id)),
          ),
      ],
    ];
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.stats});

  final List<(String, int, bool)> stats;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 2.2,
      children: [
        for (final (label, value, highlight) in stats)
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$value',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: highlight ? AstraTheme.error : null,
                    ),
                  ),
                  Text(label, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _AiShortcuts extends StatelessWidget {
  const _AiShortcuts();

  @override
  Widget build(BuildContext context) {
    final shortcuts = [
      (Icons.account_tree_outlined, 'Planifier un projet', '${Routes.ai}?tab=plan'),
      (Icons.insights_outlined, 'Analyser mon travail', '${Routes.ai}?ask=analyse'),
      (Icons.monitor_heart_outlined, 'État de santé d\'Astra', Routes.health),
      (Icons.search, 'Rechercher dans Astra', Routes.search),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (icon, label, route) in shortcuts)
          ActionChip(
            avatar: Icon(icon, size: 18),
            label: Text(label),
            onPressed: () => context.push(route),
          ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:astra_hub/core/router/routes.dart';
import 'package:astra_hub/core/utils/formatting.dart';
import 'package:astra_hub/core/widgets/astra_app_bar.dart';
import 'package:astra_hub/core/widgets/async_value_view.dart';
import 'package:astra_hub/features/meetings/data/meeting.dart';
import 'package:astra_hub/features/meetings/data/meeting_repository.dart';
import 'package:astra_hub/features/meetings/presentation/meeting_form_sheet.dart';
import 'package:astra_hub/features/tasks/presentation/task_widgets.dart';

class MeetingsScreen extends ConsumerWidget {
  const MeetingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meetings = ref.watch(meetingsProvider);
    return Scaffold(
      appBar: const AstraAppBar(title: 'Réunions'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showMeetingFormSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Planifier'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(meetingsProvider.future),
        child: AsyncValueView(
          value: meetings,
          onRetry: () => ref.invalidate(meetingsProvider),
          data: (items) {
            if (items.isEmpty) {
              return const EmptyState(
                icon: Icons.groups_outlined,
                message: 'Aucune réunion récente ou à venir.',
              );
            }
            final now = DateTime.now();
            final upcoming = items.where((m) => !m.scheduledAt.isBefore(now)).toList();
            final past = items.where((m) => m.scheduledAt.isBefore(now)).toList().reversed;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
              children: [
                if (upcoming.isNotEmpty) SectionTitle('À venir', count: upcoming.length),
                for (final m in upcoming) _MeetingTile(meeting: m),
                if (past.isNotEmpty) SectionTitle('Passées', count: past.length),
                for (final m in past) _MeetingTile(meeting: m),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MeetingTile extends StatelessWidget {
  const _MeetingTile({required this.meeting});

  final Meeting meeting;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(meeting.status == MeetingStatus.done ? Icons.task_alt : Icons.groups_outlined),
      title: Text(meeting.title),
      subtitle: Text([formatDateTime(meeting.scheduledAt), ?meeting.location].join(' · ')),
      trailing: meeting.status == MeetingStatus.planned ? null : Text(meeting.status.label),
      onTap: () => context.go(Routes.meeting(meeting.id)),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:astra_hub/core/network/api_exception.dart';
import 'package:astra_hub/core/router/routes.dart';
import 'package:astra_hub/core/theme/astra_theme.dart';
import 'package:astra_hub/core/utils/formatting.dart';
import 'package:astra_hub/core/widgets/async_value_view.dart';
import 'package:astra_hub/features/auth/presentation/auth_controller.dart';
import 'package:astra_hub/features/meetings/data/meeting.dart';
import 'package:astra_hub/features/meetings/data/meeting_repository.dart';
import 'package:astra_hub/features/meetings/presentation/decision_to_project_dialog.dart';
import 'package:astra_hub/features/meetings/presentation/meeting_summary_sheet.dart';
import 'package:astra_hub/features/members/presentation/member_avatar.dart';
import 'package:astra_hub/features/tasks/presentation/task_widgets.dart';

class MeetingDetailScreen extends ConsumerWidget {
  const MeetingDetailScreen({required this.meetingId, super.key});

  final String meetingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(meetingDetailProvider(meetingId));
    return Scaffold(
      appBar: AppBar(title: Text(detail.value?.meeting.title ?? 'Réunion')),
      body: AsyncValueView(
        value: detail,
        onRetry: () => ref.invalidate(meetingDetailProvider(meetingId)),
        data: (data) => RefreshIndicator(
          onRefresh: () => ref.refresh(meetingDetailProvider(meetingId).future),
          child: _MeetingBody(detail: data),
        ),
      ),
    );
  }
}

class _MeetingBody extends ConsumerWidget {
  const _MeetingBody({required this.detail});

  final MeetingDetail detail;

  Meeting get meeting => detail.meeting;

  Future<void> _run(BuildContext context, WidgetRef ref, Future<void> Function() action) async {
    try {
      await action();
      ref
        ..invalidate(meetingDetailProvider(meeting.id))
        ..invalidate(meetingsProvider);
    } on ApiException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _editMinutes(BuildContext context, WidgetRef ref) async {
    final minutes = await showDialog<String>(
      context: context,
      builder: (_) =>
          _TextDialog(title: 'Compte rendu', initial: detail.minutes ?? '', maxLines: 14),
    );
    if (minutes == null || !context.mounted) return;
    await _run(
      context,
      ref,
      () => ref.read(meetingRepositoryProvider).update(meeting.id, {
        'minutes': minutes,
        'status': MeetingStatus.done.name,
      }),
    );
  }

  Future<void> _addDecision(BuildContext context, WidgetRef ref) async {
    final title = await showDialog<String>(
      context: context,
      builder: (_) => const _TextDialog(title: 'Nouvelle décision', initial: ''),
    );
    if (title == null || title.trim().isEmpty || !context.mounted) return;
    await _run(
      context,
      ref,
      () => ref.read(meetingRepositoryProvider).addDecision(meeting.id, title),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final canCreateProjects = ref.watch(authControllerProvider).value?.canCreateProjects ?? false;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
      children: [
        Text(formatDateTime(meeting.scheduledAt), style: textTheme.titleMedium),
        Text(
          ['${meeting.durationMinutes} min', ?meeting.location, meeting.status.label].join(' · '),
          style: textTheme.bodySmall,
        ),
        if (meeting.projectId != null)
          TextButton.icon(
            style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
            onPressed: () => context.go(Routes.project(meeting.projectId!)),
            icon: const Icon(Icons.folder_outlined, size: 18),
            label: const Text('Voir le projet'),
          ),
        if (detail.agenda != null) ...[const SectionTitle('Ordre du jour'), Text(detail.agenda!)],
        SectionTitle(
          'Compte rendu',
          trailing: detail.canEdit
              ? IconButton(
                  tooltip: 'Modifier le compte rendu',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _editMinutes(context, ref),
                )
              : null,
        ),
        Text(detail.minutes ?? 'Pas encore de compte rendu.'),
        if (detail.canEdit && (detail.minutes ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => showMeetingSummarySheet(context, detail),
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Analyser avec ASTRA AI'),
          ),
        ],
        SectionTitle(
          'Décisions',
          count: detail.decisions.length,
          trailing: detail.canEdit
              ? IconButton(
                  tooltip: 'Ajouter une décision',
                  icon: const Icon(Icons.add),
                  onPressed: () => _addDecision(context, ref),
                )
              : null,
        ),
        if (detail.decisions.isEmpty) const Text('Aucune décision enregistrée.'),
        for (final decision in detail.decisions)
          _DecisionTile(
            decision: decision,
            canReview: detail.canEdit,
            canCreateProject: canCreateProjects,
            onReview: (status) => _run(
              context,
              ref,
              () => ref.read(meetingRepositoryProvider).review(decision.id, status),
            ),
          ),
        SectionTitle('Participants', count: detail.participants.length),
        for (final member in detail.participants)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: MemberAvatar(member: member, radius: 16),
            title: Text(member.fullName),
            subtitle: member.jobTitle == null ? null : Text(member.jobTitle!),
          ),
      ],
    );
  }
}

class _DecisionTile extends StatelessWidget {
  const _DecisionTile({
    required this.decision,
    required this.canReview,
    required this.canCreateProject,
    required this.onReview,
  });

  final Decision decision;
  final bool canReview;
  final bool canCreateProject;
  final void Function(DecisionStatus status) onReview;

  Color get _color => switch (decision.status) {
    DecisionStatus.proposed => AstraTheme.warning,
    DecisionStatus.validated => AstraTheme.accent,
    DecisionStatus.rejected => AstraTheme.textSecondary,
  };

  @override
  Widget build(BuildContext context) {
    final canTurnIntoProject =
        canCreateProject &&
        decision.status == DecisionStatus.validated &&
        decision.resultingProjectId == null;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.gavel, size: 18, color: _color),
                const SizedBox(width: 8),
                Expanded(child: Text(decision.title)),
                Text(decision.status.label, style: TextStyle(color: _color, fontSize: 12)),
              ],
            ),
            if (decision.description != null) ...[
              const SizedBox(height: 4),
              Text(decision.description!, style: Theme.of(context).textTheme.bodySmall),
            ],
            Wrap(
              spacing: 8,
              children: [
                if (canReview && decision.status == DecisionStatus.proposed) ...[
                  TextButton(
                    onPressed: () => onReview(DecisionStatus.validated),
                    child: const Text('Valider'),
                  ),
                  TextButton(
                    onPressed: () => onReview(DecisionStatus.rejected),
                    child: const Text('Rejeter'),
                  ),
                ],
                if (canTurnIntoProject)
                  TextButton.icon(
                    onPressed: () => showDecisionToProjectDialog(context, decision),
                    icon: const Icon(Icons.rocket_launch_outlined, size: 18),
                    label: const Text('Créer le projet'),
                  ),
                if (decision.resultingProjectId != null)
                  TextButton.icon(
                    onPressed: () => context.go(Routes.project(decision.resultingProjectId!)),
                    icon: const Icon(Icons.folder_outlined, size: 18),
                    label: const Text('Projet créé'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TextDialog extends StatefulWidget {
  const _TextDialog({required this.title, required this.initial, this.maxLines = 3});

  final String title;
  final String initial;
  final int maxLines;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 1,
        maxLines: widget.maxLines,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

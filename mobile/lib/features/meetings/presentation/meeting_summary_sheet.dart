import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_hub/core/network/api_exception.dart';
import 'package:astra_hub/core/widgets/async_value_view.dart';
import 'package:astra_hub/features/ai/data/ai.dart';
import 'package:astra_hub/features/ai/data/ai_repository.dart';
import 'package:astra_hub/features/meetings/data/meeting.dart';
import 'package:astra_hub/features/meetings/data/meeting_repository.dart';
import 'package:astra_hub/features/tasks/presentation/task_widgets.dart';

/// Proposition d'ASTRA AI après une réunion (spec §15) : le responsable coche
/// ce qu'il valide ; rien n'est enregistré sans son accord.
Future<void> showMeetingSummarySheet(BuildContext context, MeetingDetail meeting) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      builder: (_, controller) => _SummarySheet(meeting: meeting, scrollController: controller),
    ),
  );
}

final _summaryProvider = FutureProvider.autoDispose.family<MeetingSummary, String>(
  (ref, meetingId) => ref.watch(aiRepositoryProvider).summarizeMeeting(meetingId),
);

class _SummarySheet extends ConsumerStatefulWidget {
  const _SummarySheet({required this.meeting, required this.scrollController});

  final MeetingDetail meeting;
  final ScrollController scrollController;

  @override
  ConsumerState<_SummarySheet> createState() => _SummarySheetState();
}

class _SummarySheetState extends ConsumerState<_SummarySheet> {
  final Set<int> _decisions = {};
  final Set<int> _tasks = {};
  bool _initialized = false;
  bool _isSaving = false;

  String get _meetingId => widget.meeting.meeting.id;
  bool get _canCreateTasks => widget.meeting.meeting.projectId != null;

  Future<void> _save(MeetingSummary summary) async {
    setState(() => _isSaving = true);
    final repository = ref.read(meetingRepositoryProvider);
    try {
      for (final index in _decisions.toList()..sort()) {
        final decision = summary.decisions[index];
        await repository.addDecision(_meetingId, decision.title, description: decision.description);
      }
      final tasks = [
        for (final index in _tasks.toList()..sort()) summary.tasks[index].toTaskCreate(),
      ];
      if (tasks.isNotEmpty) await repository.createTasks(_meetingId, tasks);
      ref.invalidate(meetingDetailProvider(_meetingId));
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_decisions.length} décision(s) et ${tasks.length} tâche(s) enregistrées.',
            ),
          ),
        );
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(_summaryProvider(_meetingId));
    return AsyncValueView(
      value: summary,
      onRetry: () => ref.invalidate(_summaryProvider(_meetingId)),
      data: (data) {
        if (!_initialized) {
          _initialized = true;
          _decisions.addAll(List.generate(data.decisions.length, (i) => i));
          if (_canCreateTasks) _tasks.addAll(List.generate(data.tasks.length, (i) => i));
        }
        return ListView(
          controller: widget.scrollController,
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Proposition d\'ASTRA AI',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Vérifiez et décochez ce qui ne convient pas avant d\'enregistrer.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SectionTitle('Résumé'),
            Text(data.summary),
            SectionTitle('Décisions', count: data.decisions.length),
            for (final (index, d) in data.decisions.indexed)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _decisions.contains(index),
                title: Text(d.title),
                subtitle: d.description.isEmpty ? null : Text(d.description),
                onChanged: (v) =>
                    setState(() => v == true ? _decisions.add(index) : _decisions.remove(index)),
              ),
            SectionTitle('Tâches', count: data.tasks.length),
            if (!_canCreateTasks)
              const Text('Rattachez la réunion à un projet pour créer ces tâches.'),
            for (final (index, t) in data.tasks.indexed)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _tasks.contains(index),
                title: Text(t.title),
                subtitle: Text([t.assigneeName ?? 'Sans responsable', ?t.dueDate].join(' · ')),
                onChanged: _canCreateTasks
                    ? (v) => setState(() => v == true ? _tasks.add(index) : _tasks.remove(index))
                    : null,
              ),
            if (data.openQuestions.isNotEmpty) ...[
              const SectionTitle('Questions ouvertes'),
              for (final q in data.openQuestions) Text('• $q'),
            ],
            if (data.risks.isNotEmpty) ...[
              const SectionTitle('Risques'),
              for (final r in data.risks) Text('• $r'),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isSaving || (_decisions.isEmpty && _tasks.isEmpty)
                  ? null
                  : () => _save(data),
              child: const Text('Valider et enregistrer'),
            ),
          ],
        );
      },
    );
  }
}

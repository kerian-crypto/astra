import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:astra_hub/core/network/api_exception.dart';
import 'package:astra_hub/core/router/routes.dart';
import 'package:astra_hub/core/utils/formatting.dart';
import 'package:astra_hub/features/home/data/work.dart';
import 'package:astra_hub/features/meetings/data/meeting_repository.dart';
import 'package:astra_hub/features/members/data/member_repository.dart';
import 'package:astra_hub/features/projects/data/project_repository.dart';

Future<void> showMeetingFormSheet(BuildContext context) async {
  final meetingId = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _MeetingFormSheet(),
  );
  if (meetingId != null && context.mounted) context.go(Routes.meeting(meetingId));
}

class _MeetingFormSheet extends ConsumerStatefulWidget {
  const _MeetingFormSheet();

  @override
  ConsumerState<_MeetingFormSheet> createState() => _MeetingFormSheetState();
}

class _MeetingFormSheetState extends ConsumerState<_MeetingFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _agenda = TextEditingController();
  DateTime? _when;
  String? _projectId;
  final Set<String> _participants = {};
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _agenda.dispose();
    super.dispose();
  }

  Future<void> _pickMoment() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _when ?? now,
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_when ?? now.add(const Duration(hours: 1))),
    );
    if (time == null) return;
    setState(() => _when = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) return;
    if (_when == null) {
      setState(() => _error = 'Choisissez la date et l\'heure.');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      final created = await ref
          .read(meetingRepositoryProvider)
          .create(
            title: _title.text,
            scheduledAt: _when!,
            participantIds: _participants.toList(),
            projectId: _projectId,
            agenda: _agenda.text,
          );
      ref
        ..invalidate(meetingsProvider)
        ..invalidate(myWorkProvider);
      if (mounted) Navigator.of(context).pop(created.meeting.id);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final projects = ref.watch(projectListProvider).value ?? const [];
    final members = ref.watch(membersProvider).value ?? const [];
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Planifier une réunion', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextFormField(
                controller: _title,
                maxLength: 200,
                decoration: const InputDecoration(labelText: 'Titre'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Le titre est requis.' : null,
              ),
              OutlinedButton.icon(
                onPressed: _pickMoment,
                icon: const Icon(Icons.schedule),
                label: Text(_when == null ? 'Date et heure' : formatDateTime(_when!)),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: _projectId,
                decoration: const InputDecoration(labelText: 'Projet'),
                items: [
                  const DropdownMenuItem(child: Text('Réunion générale')),
                  for (final p in projects) DropdownMenuItem(value: p.id, child: Text(p.name)),
                ],
                onChanged: (value) => setState(() => _projectId = value),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _agenda,
                decoration: const InputDecoration(labelText: 'Ordre du jour'),
                minLines: 2,
                maxLines: 6,
              ),
              const SizedBox(height: 16),
              Text('Participants', style: Theme.of(context).textTheme.titleSmall),
              Wrap(
                spacing: 8,
                children: [
                  for (final m in members)
                    FilterChip(
                      label: Text(m.fullName),
                      selected: _participants.contains(m.id),
                      onSelected: (selected) => setState(
                        () => selected ? _participants.add(m.id) : _participants.remove(m.id),
                      ),
                    ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                child: const Text('Planifier'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

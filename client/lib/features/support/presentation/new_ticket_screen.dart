import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:astra_client/core/layout/breakpoints.dart';
import 'package:astra_client/core/layout/page_frame.dart';
import 'package:astra_client/core/router/routes.dart';
import 'package:astra_client/core/theme/client_theme.dart';
import 'package:astra_client/core/widgets/state_views.dart';
import 'package:astra_client/features/dashboard/data/dashboard.dart';
import 'package:astra_client/features/projects/data/project_repository.dart';
import 'package:astra_client/features/support/data/ticket.dart';
import 'package:astra_client/features/support/data/ticket_repository.dart';

class NewTicketScreen extends ConsumerStatefulWidget {
  const NewTicketScreen({this.projectId, super.key});

  final String? projectId;

  @override
  ConsumerState<NewTicketScreen> createState() => _NewTicketScreenState();
}

class _NewTicketScreenState extends ConsumerState<NewTicketScreen> {
  final _formKey = GlobalKey<FormState>();
  final _subject = TextEditingController();
  final _description = TextEditingController();
  TicketType _type = TicketType.question;
  TicketPriority _priority = TicketPriority.normal;
  late String? _projectId = widget.projectId;
  bool _sending = false;

  @override
  void dispose() {
    _subject.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _sending = true);
    try {
      final ticket = await ref
          .read(ticketRepositoryProvider)
          .create(
            type: _type,
            subject: _subject.text,
            description: _description.text,
            priority: _priority,
            projectId: _projectId,
          );
      ref
        ..invalidate(ticketsProvider)
        ..invalidate(dashboardProvider);
      if (!mounted) return;
      showSuccess(context, 'Demande ${ticket.number} créée. Astra vous répondra rapidement.');
      context.pushReplacement(Routes.ticket(ticket.id));
    } on Exception catch (error) {
      if (mounted) {
        setState(() => _sending = false);
        showError(context, error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final projects = ref.watch(projectsProvider).value ?? const [];
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Nouvelle demande')),
      body: Form(
        key: _formKey,
        child: FramedListView(
          maxWidth: Breakpoints.formMaxWidth,
          children: [
            Text('Type de demande', style: text.labelLarge),
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                for (final type in TicketType.values)
                  ChoiceChip(
                    avatar: Icon(type.icon, size: 18),
                    label: Text(type.label),
                    selected: _type == type,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _type = type),
                  ),
              ],
            ),
            const SizedBox(height: Space.xl),
            if (projects.isNotEmpty) ...[
              DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: _projectId,
                decoration: const InputDecoration(labelText: 'Projet concerné'),
                items: [
                  const DropdownMenuItem(child: Text('Aucun projet en particulier')),
                  for (final p in projects) DropdownMenuItem(value: p.id, child: Text(p.name)),
                ],
                onChanged: (value) => setState(() => _projectId = value),
              ),
              const SizedBox(height: Space.lg),
            ],
            TextFormField(
              controller: _subject,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Sujet',
                hintText: 'Ex. Problème sur le site',
              ),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Indiquez un sujet.' : null,
            ),
            const SizedBox(height: Space.sm),
            TextFormField(
              controller: _description,
              minLines: 5,
              maxLines: 10,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'Décrivez votre demande le plus précisément possible.',
                alignLabelWithHint: true,
              ),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Décrivez votre demande.' : null,
            ),
            const SizedBox(height: Space.lg),
            Text('Priorité', style: text.labelLarge),
            const SizedBox(height: Space.sm),
            SegmentedButton<TicketPriority>(
              segments: [
                for (final p in TicketPriority.values)
                  ButtonSegment(value: p, label: Text(p.label)),
              ],
              selected: {_priority},
              showSelectedIcon: false,
              onSelectionChanged: (value) => setState(() => _priority = value.first),
            ),
            const SizedBox(height: Space.xxl),
            FilledButton.icon(
              onPressed: _sending ? null : _submit,
              icon: const Icon(Icons.send_rounded),
              label: const Text('Envoyer la demande'),
            ),
          ],
        ),
      ),
    );
  }
}

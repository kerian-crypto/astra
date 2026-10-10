import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_client/core/theme/client_theme.dart';
import 'package:astra_client/core/widgets/state_views.dart';
import 'package:astra_client/features/messages/data/conversation.dart';
import 'package:astra_client/features/messages/data/conversation_repository.dart';
import 'package:astra_client/features/projects/data/project_repository.dart';

Future<Conversation?> showNewConversationSheet(BuildContext context, {String? projectId}) {
  return showModalBottomSheet<Conversation>(
    context: context,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (_) => _NewConversationSheet(projectId: projectId),
  );
}

class _NewConversationSheet extends ConsumerStatefulWidget {
  const _NewConversationSheet({this.projectId});

  final String? projectId;

  @override
  ConsumerState<_NewConversationSheet> createState() => _NewConversationSheetState();
}

class _NewConversationSheetState extends ConsumerState<_NewConversationSheet> {
  final _formKey = GlobalKey<FormState>();
  final _subject = TextEditingController();
  final _body = TextEditingController();
  late String? _projectId = widget.projectId;
  bool _sending = false;

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _sending = true);
    try {
      final conversation = await ref
          .read(conversationRepositoryProvider)
          .start(subject: _subject.text, body: _body.text, projectId: _projectId);
      if (mounted) Navigator.of(context).pop(conversation);
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
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Space.xl,
        0,
        Space.xl,
        MediaQuery.viewInsetsOf(context).bottom + Space.xl,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Nouveau message', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: Space.xl),
            if (projects.isNotEmpty) ...[
              DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: _projectId,
                decoration: const InputDecoration(labelText: 'Projet concerné'),
                items: [
                  const DropdownMenuItem(child: Text('Question générale')),
                  for (final project in projects)
                    DropdownMenuItem(value: project.id, child: Text(project.name)),
                ],
                onChanged: (value) => setState(() => _projectId = value),
              ),
              const SizedBox(height: Space.lg),
            ],
            TextFormField(
              controller: _subject,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Sujet'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Indiquez un sujet.' : null,
            ),
            const SizedBox(height: Space.sm),
            TextFormField(
              controller: _body,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(labelText: 'Message', alignLabelWithHint: true),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Écrivez votre message.' : null,
            ),
            const SizedBox(height: Space.xl),
            FilledButton.icon(
              onPressed: _sending ? null : _send,
              icon: const Icon(Icons.send_rounded),
              label: const Text('Envoyer'),
            ),
          ],
        ),
      ),
    );
  }
}

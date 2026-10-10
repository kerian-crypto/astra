import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_hub/core/layout/responsive.dart';
import 'package:astra_hub/core/theme/astra_theme.dart';
import 'package:astra_hub/core/utils/formatting.dart';
import 'package:astra_hub/core/widgets/async_value_view.dart';
import 'package:astra_hub/features/clients/data/clients.dart';
import 'package:astra_hub/features/clients/data/clients_repository.dart';
import 'package:astra_hub/features/clients/presentation/client_widgets.dart';

class ClientConversationScreen extends ConsumerWidget {
  const ClientConversationScreen({required this.conversationId, super.key});

  final String conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversation = ref.watch(clientConversationProvider(conversationId)).value;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(conversation?.subject ?? 'Échange client', overflow: TextOverflow.ellipsis),
            if (conversation != null)
              Text(
                '${conversation.companyName}${conversation.projectName != null ? ' · ${conversation.projectName}' : ''}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
      body: ClientThread(conversationId: conversationId),
    );
  }
}

/// Fil d'échanges avec le client et zone de réponse (réutilisé par les tickets).
class ClientThread extends ConsumerStatefulWidget {
  const ClientThread({required this.conversationId, super.key});

  final String conversationId;

  @override
  ConsumerState<ClientThread> createState() => _ClientThreadState();
}

class _ClientThreadState extends ConsumerState<ClientThread> {
  final _input = TextEditingController();
  LocalFile? _file;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    unawaited(
      ref
          .read(clientsRepositoryProvider)
          .markConversationRead(widget.conversationId)
          .then((_) => ref.invalidate(clientConversationsProvider), onError: (Object _) {}),
    );
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_input.text.trim().isEmpty && _file == null) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(clientsRepositoryProvider)
          .sendMessage(widget.conversationId, _input.text, file: _file);
      _input.clear();
      setState(() => _file = null);
      ref
        ..invalidate(clientMessagesProvider(widget.conversationId))
        ..invalidate(clientConversationsProvider);
    } on Exception catch (error) {
      if (mounted) showMessage(context, error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(clientMessagesProvider(widget.conversationId));
    return ResponsiveCenter(
      maxWidth: Breakpoints.readingMaxWidth,
      child: Column(
        children: [
          Expanded(
            child: AsyncValueView(
              value: messages,
              onRetry: () => ref.invalidate(clientMessagesProvider(widget.conversationId)),
              data: (list) => RefreshIndicator(
                onRefresh: () => ref.refresh(clientMessagesProvider(widget.conversationId).future),
                child: ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: list.length,
                  itemBuilder: (_, i) => _Bubble(message: list[list.length - 1 - i]),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_file != null)
                    InputChip(
                      label: Text(_file!.name),
                      onDeleted: () => setState(() => _file = null),
                    ),
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Joindre un fichier',
                        icon: const Icon(Icons.attach_file),
                        onPressed: () async {
                          final files = await FilePicker.pickFiles();
                          final picked = files.firstOrNull;
                          if (picked?.path != null) {
                            setState(() => _file = (path: picked!.path!, name: picked.name));
                          }
                        },
                      ),
                      Expanded(
                        child: TextField(
                          controller: _input,
                          minLines: 1,
                          maxLines: 5,
                          decoration: const InputDecoration(hintText: 'Répondre au client…'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        tooltip: 'Envoyer',
                        onPressed: _sending ? null : _send,
                        icon: const Icon(Icons.send),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends ConsumerWidget {
  const _Bubble({required this.message});

  final ClientMessage message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final astra = message.fromAstra;
    final file = message.file;
    return Align(
      alignment: astra ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: astra ? AstraTheme.primary.withValues(alpha: 0.25) : AstraTheme.surface,
            border: astra ? null : Border.all(color: AstraTheme.outline),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                astra ? message.authorName : '${message.authorName} · client',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: astra ? AstraTheme.primary : AstraTheme.accent,
                ),
              ),
              if (message.body.isNotEmpty) Text(message.body),
              if (file != null)
                TextButton.icon(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  onPressed: () => openClientFile(
                    context,
                    ref,
                    '/clients/conversations/${message.conversationId}/messages/${message.id}/file',
                    file.name,
                  ),
                  icon: const Icon(Icons.attach_file, size: 16),
                  label: Text(file.name),
                ),
              Text(
                formatDateTime(message.createdAt),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

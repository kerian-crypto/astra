import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_client/core/theme/client_theme.dart';
import 'package:astra_client/core/utils/formatting.dart';
import 'package:astra_client/core/utils/picked_file.dart';
import 'package:astra_client/core/widgets/state_views.dart';
import 'package:astra_client/core/widgets/ui.dart';
import 'package:astra_client/features/documents/presentation/document_tile.dart';
import 'package:astra_client/features/messages/data/conversation.dart';
import 'package:astra_client/features/messages/data/conversation_repository.dart';

/// Fil d'une conversation et zone de saisie (réutilisé en plein écran sur
/// téléphone et dans le panneau de droite sur grand écran).
class ConversationPane extends ConsumerStatefulWidget {
  const ConversationPane({required this.conversationId, this.showHeader = false, super.key});

  final String conversationId;
  final bool showHeader;

  @override
  ConsumerState<ConversationPane> createState() => _ConversationPaneState();
}

class _ConversationPaneState extends ConsumerState<ConversationPane> {
  final _input = TextEditingController();
  PickedFile? _attachment;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    unawaited(_markRead());
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _markRead() async {
    try {
      await ref.read(conversationRepositoryProvider).markRead(widget.conversationId);
      ref.invalidate(conversationsProvider);
    } on Exception {
      // Hors ligne : sera marqué lu à la prochaine ouverture.
    }
  }

  Future<void> _send() async {
    final body = _input.text.trim();
    if (body.isEmpty && _attachment == null) return;
    setState(() => _sending = true);
    try {
      final message = await ref
          .read(conversationRepositoryProvider)
          .send(widget.conversationId, body: body, attachment: _attachment);
      ref.read(conversationMessagesProvider(widget.conversationId).notifier).upsert(message);
      ref.invalidate(conversationsProvider);
      _input.clear();
      setState(() => _attachment = null);
    } on Exception catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _attach() async {
    final file = await pickDocument();
    if (file != null) setState(() => _attachment = file);
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(conversationMessagesProvider(widget.conversationId));
    final conversation = ref.watch(conversationProvider(widget.conversationId)).value;
    // Un message reçu pendant que le fil est ouvert est lu.
    ref.listen(conversationMessagesProvider(widget.conversationId), (previous, next) {
      if ((previous?.value?.length ?? 0) < (next.value?.length ?? 0)) unawaited(_markRead());
    });
    return Column(
      children: [
        if (widget.showHeader && conversation != null)
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: ListTile(
              title: Text(conversation.subject, style: Theme.of(context).textTheme.titleMedium),
              subtitle: conversation.projectName == null ? null : Text(conversation.projectName!),
            ),
          ),
        Expanded(
          child: AsyncView(
            value: messages,
            onRetry: () => ref.invalidate(conversationMessagesProvider(widget.conversationId)),
            builder: (list) {
              if (list.isEmpty) {
                return const StateMessage(
                  icon: Icons.chat_outlined,
                  title: 'Aucun message pour le moment',
                  message: 'Écrivez votre premier message ci-dessous.',
                  compact: true,
                );
              }
              final notifier = ref.read(
                conversationMessagesProvider(widget.conversationId).notifier,
              );
              final reversed = list.reversed.toList();
              return ListView.builder(
                reverse: true,
                padding: const EdgeInsets.all(Space.lg),
                itemCount: reversed.length + (notifier.hasMore ? 1 : 0),
                itemBuilder: (context, i) {
                  if (i == reversed.length) {
                    return Center(
                      child: TextButton(
                        onPressed: () => unawaited(notifier.loadOlder()),
                        child: const Text('Messages précédents'),
                      ),
                    );
                  }
                  final message = reversed[i];
                  final previous = i + 1 < reversed.length ? reversed[i + 1] : null;
                  final showDay =
                      previous == null ||
                      previous.createdAt.toLocal().day != message.createdAt.toLocal().day;
                  return Column(
                    children: [
                      if (showDay) _DayDivider(date: message.createdAt),
                      _Bubble(message: message),
                    ],
                  );
                },
              );
            },
          ),
        ),
        _Composer(
          controller: _input,
          attachment: _attachment,
          sending: _sending,
          onAttach: _attach,
          onRemoveAttachment: () => setState(() => _attachment = null),
          onSend: _send,
        ),
      ],
    );
  }
}

class _DayDivider extends StatelessWidget {
  const _DayDivider({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.md),
    child: Center(child: StatusPill(label: formatDate(date))),
  );
}

class _Bubble extends ConsumerWidget {
  const _Bubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final mine = message.isMine;
    final background = mine ? scheme.primary : scheme.surface;
    final foreground = mine ? scheme.onPrimary : scheme.onSurface;
    final file = message.file;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, Space.sm),
          decoration: BoxDecoration(
            color: background,
            border: mine ? null : Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(mine ? 16 : 4),
              bottomRight: Radius.circular(mine ? 4 : 16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!mine)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        message.authorName,
                        style: text.labelMedium?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (message.fromAstra) ...[
                        const SizedBox(width: 6),
                        const StatusPill(label: 'Astra', tone: Tone.brand),
                      ],
                    ],
                  ),
                ),
              if (message.body.isNotEmpty)
                Text(message.body, style: text.bodyMedium?.copyWith(color: foreground)),
              if (file != null)
                InkWell(
                  onTap: () => unawaited(
                    openApiFile(
                      context,
                      ref,
                      'client/conversations/${message.conversationId}/messages/${message.id}/file',
                      file.name,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(top: Space.xs),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(iconForContentType(file.contentType), size: 20, color: foreground),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            file.name,
                            style: text.bodyMedium?.copyWith(
                              color: foreground,
                              decoration: TextDecoration.underline,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 2),
              Align(
                alignment: Alignment.bottomRight,
                child: Text(
                  formatRelative(message.createdAt),
                  style: text.labelSmall?.copyWith(color: foreground.withValues(alpha: 0.7)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.attachment,
    required this.sending,
    required this.onAttach,
    required this.onRemoveAttachment,
    required this.onSend,
  });

  final TextEditingController controller;
  final PickedFile? attachment;
  final bool sending;
  final VoidCallback onAttach;
  final VoidCallback onRemoveAttachment;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.sm, Space.sm, Space.sm, Space.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (attachment != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.sm),
                  child: InputChip(
                    avatar: const Icon(Icons.attach_file_rounded, size: 18),
                    label: Text(attachment!.name, overflow: TextOverflow.ellipsis),
                    onDeleted: onRemoveAttachment,
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'Joindre un fichier',
                    onPressed: sending ? null : onAttach,
                    icon: const Icon(Icons.attach_file_rounded),
                  ),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Votre message',
                        isDense: true,
                        filled: true,
                        fillColor: scheme.surfaceContainerLow,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(color: scheme.outlineVariant),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: Space.xs),
                  IconButton.filled(
                    tooltip: 'Envoyer',
                    onPressed: sending ? null : onSend,
                    icon: sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

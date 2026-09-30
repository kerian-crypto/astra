import 'package:flutter/material.dart';

import 'package:astra_hub/core/theme/astra_theme.dart';
import 'package:astra_hub/core/utils/formatting.dart';
import 'package:astra_hub/features/chat/data/chat.dart';
import 'package:astra_hub/features/chat/presentation/attachment_view.dart';

sealed class MessageAction {
  const MessageAction();
}

final class ReplyAction extends MessageAction {
  const ReplyAction();
}

final class ReactAction extends MessageAction {
  const ReactAction(this.emoji);

  final String emoji;
}

final class DeleteAction extends MessageAction {
  const DeleteAction();
}

const quickReactions = ['👍', '✅', '❤️', '😂', '👀', '🎉'];

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    required this.message,
    required this.isMine,
    required this.onAction,
    this.repliedTo,
    super.key,
  });

  final ChatMessage message;
  final bool isMine;
  final ChatMessage? repliedTo;
  final void Function(MessageAction action) onAction;

  Future<void> _openActions(BuildContext context) async {
    final action = await showModalBottomSheet<MessageAction>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final emoji in quickReactions)
                    IconButton(
                      tooltip: 'Réagir $emoji',
                      onPressed: () => Navigator.pop(sheetContext, ReactAction(emoji)),
                      icon: Text(emoji, style: const TextStyle(fontSize: 24)),
                    ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Répondre'),
              onTap: () => Navigator.pop(sheetContext, const ReplyAction()),
            ),
            if (isMine)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Supprimer'),
                onTap: () => Navigator.pop(sheetContext, const DeleteAction()),
              ),
          ],
        ),
      ),
    );
    if (action != null) onAction(action);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final background = isMine ? AstraTheme.primary.withValues(alpha: 0.25) : AstraTheme.surface;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        child: GestureDetector(
          onLongPress: message.isDeleted ? null : () => _openActions(context),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(AstraTheme.radius),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isMine)
                  Text(
                    message.author?.fullName ?? 'Membre supprimé',
                    style: textTheme.labelMedium?.copyWith(color: AstraTheme.secondary),
                  ),
                if (repliedTo != null)
                  Container(
                    margin: const EdgeInsets.only(top: 4, bottom: 4),
                    padding: const EdgeInsets.only(left: 8),
                    decoration: const BoxDecoration(
                      border: Border(left: BorderSide(color: AstraTheme.secondary, width: 2)),
                    ),
                    child: Text(
                      repliedTo!.preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall,
                    ),
                  ),
                if (message.attachment case final attachment? when !message.isDeleted)
                  AttachmentView(messageId: message.id, attachment: attachment),
                if (message.isDeleted || message.body.isNotEmpty)
                  Text(
                    message.isDeleted ? 'Message supprimé' : message.body,
                    style: message.isDeleted
                        ? textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)
                        : textTheme.bodyLarge,
                  ),
                const SizedBox(height: 4),
                Text(
                  [
                    formatShortMoment(message.createdAt),
                    if (message.editedAt != null && !message.isDeleted) 'modifié',
                  ].join(' · '),
                  style: textTheme.labelSmall,
                ),
                if (message.reactions.isNotEmpty)
                  Wrap(
                    spacing: 4,
                    children: [
                      for (final reaction in message.reactions)
                        ActionChip(
                          visualDensity: VisualDensity.compact,
                          backgroundColor: reaction.reactedByMe
                              ? AstraTheme.primary.withValues(alpha: 0.3)
                              : null,
                          label: Text('${reaction.emoji} ${reaction.count}'),
                          onPressed: () => onAction(ReactAction(reaction.emoji)),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

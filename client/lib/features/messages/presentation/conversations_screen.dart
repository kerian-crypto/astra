import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:astra_client/core/layout/breakpoints.dart';
import 'package:astra_client/core/router/routes.dart';
import 'package:astra_client/core/theme/client_theme.dart';
import 'package:astra_client/core/utils/formatting.dart';
import 'package:astra_client/core/widgets/state_views.dart';
import 'package:astra_client/core/widgets/ui.dart';
import 'package:astra_client/features/auth/data/session.dart';
import 'package:astra_client/features/auth/presentation/auth_controller.dart';
import 'package:astra_client/features/messages/data/conversation.dart';
import 'package:astra_client/features/messages/data/conversation_repository.dart';
import 'package:astra_client/features/messages/presentation/conversation_pane.dart';
import 'package:astra_client/features/messages/presentation/new_conversation_sheet.dart';

/// Conversations avec Astra. Sur grand écran : liste et fil côte à côte.
class ConversationsScreen extends ConsumerStatefulWidget {
  const ConversationsScreen({super.key});

  @override
  ConsumerState<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends ConsumerState<ConversationsScreen> {
  String? _selectedId;

  Future<void> _create() async {
    final conversation = await showNewConversationSheet(context);
    if (conversation == null || !mounted) return;
    ref.invalidate(conversationsProvider);
    _open(conversation.id);
  }

  void _open(String id) {
    if (context.windowSize == WindowSize.expanded) {
      setState(() => _selectedId = id);
    } else {
      context.go(Routes.conversation(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final conversations = ref.watch(conversationsProvider);
    final canWrite = ref.watch(sessionProvider)?.can(ClientPermission.sendMessage) ?? false;
    final expanded = context.windowSize == WindowSize.expanded;
    final list = AsyncView(
      value: conversations,
      onRetry: () => ref.invalidate(conversationsProvider),
      isEmpty: (items) => items.isEmpty,
      empty: StateMessage(
        icon: Icons.forum_outlined,
        title: 'Aucune conversation',
        message: 'Posez une question à votre équipe Astra, elle vous répondra ici.',
        tone: Tone.brand,
        action: canWrite
            ? FilledButton.icon(
                onPressed: _create,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Nouveau message'),
              )
            : null,
      ),
      builder: (items) => RefreshIndicator(
        onRefresh: () => ref.refresh(conversationsProvider.future),
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: Space.sm),
          itemCount: items.length,
          separatorBuilder: (_, _) => const Divider(indent: 76),
          itemBuilder: (_, i) => _ConversationTile(
            conversation: items[i],
            selected: expanded && items[i].id == _selectedId,
            onTap: () => _open(items[i].id),
          ),
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      floatingActionButton: canWrite && !expanded
          ? FloatingActionButton.extended(
              onPressed: _create,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Nouveau'),
            )
          : null,
      body: !expanded
          ? Center(
              child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: list),
            )
          : Row(
              children: [
                SizedBox(
                  width: 380,
                  child: Column(
                    children: [
                      if (canWrite)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
                          child: SizedBox(
                            width: double.infinity,
                            child: FilledButton.tonalIcon(
                              onPressed: _create,
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('Nouveau message'),
                            ),
                          ),
                        ),
                      Expanded(child: list),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: _selectedId == null
                      ? const StateMessage(
                          icon: Icons.chat_bubble_outline_rounded,
                          title: 'Sélectionnez une conversation',
                        )
                      : ConversationPane(
                          key: ValueKey(_selectedId),
                          conversationId: _selectedId!,
                          showHeader: true,
                        ),
                ),
              ],
            ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.conversation, required this.onTap, this.selected = false});

  final Conversation conversation;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final unread = conversation.unreadCount > 0;
    final last = conversation.lastMessage;
    final (icon, tone) = switch (conversation.kind) {
      ConversationKind.project => (Icons.work_outline_rounded, Tone.brand),
      ConversationKind.ticket => (Icons.support_agent_outlined, Tone.info),
      ConversationKind.deliverable => (Icons.inventory_2_outlined, Tone.warning),
      ConversationKind.general => (Icons.forum_outlined, Tone.neutral),
    };
    final preview = last == null
        ? (conversation.projectName ?? 'Nouvelle conversation')
        : '${last.isMine ? 'Vous' : last.authorName} : ${last.body.isEmpty ? '📎 Pièce jointe' : last.body}';
    return ListTile(
      selected: selected,
      selectedTileColor: scheme.primaryContainer.withValues(alpha: 0.5),
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.xs),
      leading: ToneIcon(icon, tone: tone, size: 44),
      title: Text(
        conversation.subject,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: text.titleSmall?.copyWith(fontWeight: unread ? FontWeight.w800 : FontWeight.w600),
      ),
      subtitle: Text(
        preview,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: unread ? scheme.onSurface : scheme.onSurfaceVariant),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(formatDateShort(conversation.activityAt), style: text.labelSmall),
          const SizedBox(height: 4),
          if (unread)
            Badge(label: Text('${conversation.unreadCount}'))
          else
            const SizedBox(height: 16),
        ],
      ),
      onTap: onTap,
    );
  }
}

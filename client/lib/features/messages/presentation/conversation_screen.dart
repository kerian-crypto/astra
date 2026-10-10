import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_client/features/messages/data/conversation_repository.dart';
import 'package:astra_client/features/messages/presentation/conversation_pane.dart';

class ConversationScreen extends ConsumerWidget {
  const ConversationScreen({required this.conversationId, super.key});

  final String conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversation = ref.watch(conversationProvider(conversationId)).value;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(conversation?.subject ?? 'Conversation', overflow: TextOverflow.ellipsis),
            if (conversation?.projectName != null)
              Text(conversation!.projectName!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      body: ConversationPane(conversationId: conversationId),
    );
  }
}

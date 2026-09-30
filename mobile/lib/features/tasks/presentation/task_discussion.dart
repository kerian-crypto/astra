import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_hub/core/network/api_exception.dart';
import 'package:astra_hub/core/utils/formatting.dart';
import 'package:astra_hub/features/members/presentation/member_avatar.dart';
import 'package:astra_hub/features/tasks/data/task_repository.dart';
import 'package:astra_hub/features/tasks/presentation/task_widgets.dart';

/// Commentaires et historique d'une tâche.
class TaskDiscussion extends ConsumerStatefulWidget {
  const TaskDiscussion({required this.taskId, required this.canComment, super.key});

  final String taskId;
  final bool canComment;

  @override
  ConsumerState<TaskDiscussion> createState() => _TaskDiscussionState();
}

class _TaskDiscussionState extends ConsumerState<TaskDiscussion> {
  final _comment = TextEditingController();
  bool _isSending = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _comment.text.trim();
    if (body.isEmpty || _isSending) return;
    setState(() => _isSending = true);
    try {
      await ref.read(taskRepositoryProvider).addComment(widget.taskId, body);
      _comment.clear();
      ref
        ..invalidate(taskCommentsProvider(widget.taskId))
        ..invalidate(taskHistoryProvider(widget.taskId));
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final comments = ref.watch(taskCommentsProvider(widget.taskId)).value ?? const [];
    final history = ref.watch(taskHistoryProvider(widget.taskId)).value ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle('Commentaires', count: comments.length),
        for (final comment in comments)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: MemberAvatar(member: comment.author, radius: 16),
            title: Text(comment.body),
            subtitle: Text('${comment.author.fullName} · ${formatShortMoment(comment.createdAt)}'),
          ),
        if (widget.canComment)
          TextField(
            controller: _comment,
            minLines: 1,
            maxLines: 4,
            textInputAction: TextInputAction.send,
            decoration: InputDecoration(
              hintText: 'Écrire un commentaire',
              suffixIcon: IconButton(
                tooltip: 'Envoyer',
                icon: const Icon(Icons.send),
                onPressed: _isSending ? null : _send,
              ),
            ),
            onSubmitted: (_) => _send(),
          ),
        if (history.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('Historique (${history.length})'),
            children: [
              for (final entry in history)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(entry.describe()),
                  subtitle: Text(formatDateTime(entry.createdAt)),
                ),
            ],
          ),
      ],
    );
  }
}

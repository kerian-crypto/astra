import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:astra_hub/core/network/api_exception.dart';
import 'package:astra_hub/core/router/routes.dart';
import 'package:astra_hub/core/theme/astra_theme.dart';
import 'package:astra_hub/features/ai/data/ai.dart';
import 'package:astra_hub/features/ai/data/ai_repository.dart';
import 'package:astra_hub/features/ai/presentation/ai_action_card.dart';
import 'package:astra_hub/features/ai/presentation/ai_history_sheet.dart';

/// Assistant ASTRA AI. Les conversations sont enregistrées côté serveur et la
/// réponse de Ronda y est générée en arrière-plan : on peut quitter l'écran ou
/// ouvrir une autre conversation, elle continue et se retrouve dans l'historique.
class AiChatView extends ConsumerStatefulWidget {
  const AiChatView({this.initialQuestion, this.focus, super.key});

  final String? initialQuestion;

  /// Écran d'où l'on vient (bouton Ronda) : Ronda le lit à chaque question
  /// tant que le membre ne retire pas ce contexte.
  final AiFocus? focus;

  @override
  ConsumerState<AiChatView> createState() => _AiChatViewState();
}

class _AiChatViewState extends ConsumerState<AiChatView> {
  /// Fréquence de relecture tant que Ronda répond.
  static const pollInterval = Duration(seconds: 3);
  static const _examples = [
    'Quels sont mes travaux prioritaires aujourd\'hui ?',
    'Quels projets sont actuellement en retard ?',
    'Quelles décisions ont été prises récemment ?',
  ];

  final _input = TextEditingController();
  AiConversation? _conversation;
  String? _sendingQuestion; // question en cours d'envoi, avant la réponse du serveur
  bool _isLoading = false;
  Timer? _poll;
  late AiFocus? _focus = widget.focus;

  AiRepository get _repository => ref.read(aiRepositoryProvider);

  bool get _isBusy => _sendingQuestion != null || (_conversation?.isPending ?? false);

  @override
  void initState() {
    super.initState();
    final question = widget.initialQuestion;
    final currentId = ref.read(currentAiConversationProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (question != null) {
        _startNew();
        await _ask(question);
      } else if (currentId != null) {
        await _open(currentId);
      }
    });
  }

  @override
  void dispose() {
    // La génération continue côté serveur : seule la relecture s'arrête.
    _poll?.cancel();
    _input.dispose();
    super.dispose();
  }

  void _showError(ApiException error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
  }

  void _show(AiConversation conversation) {
    if (!mounted) return;
    setState(() => _conversation = conversation);
    ref.read(currentAiConversationProvider.notifier).open(conversation.id);
    _poll?.cancel();
    if (conversation.isPending) {
      _poll = Timer(pollInterval, () => unawaited(_refresh(conversation.id)));
    } else {
      ref.invalidate(aiConversationsProvider);
    }
  }

  void _startNew() {
    _poll?.cancel();
    setState(() => _conversation = null);
    ref.read(currentAiConversationProvider.notifier).open(null);
  }

  Future<void> _open(String id) async {
    _poll?.cancel();
    setState(() => _isLoading = true);
    try {
      _show(await _repository.conversation(id));
    } on ApiException catch (error) {
      if (!mounted) return;
      _startNew();
      if (error.statusCode != 404) _showError(error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refresh(String id) async {
    try {
      final conversation = await _repository.conversation(id);
      if (_conversation?.id == id) _show(conversation);
    } on ApiException catch (error) {
      if (!mounted || _conversation?.id != id) return;
      if (error.statusCode == 404) return _startNew();
      // Coupure réseau passagère : on réessaie, la réponse est sur le serveur.
      _poll = Timer(pollInterval, () => unawaited(_refresh(id)));
    }
  }

  Future<void> _ask(String question) async {
    final text = question.trim();
    if (text.isEmpty || _isBusy) return;
    setState(() => _sendingQuestion = text);
    _input.clear();
    try {
      final conversation = await _repository.sendQuestion(
        text,
        conversationId: _conversation?.id,
        focus: _focus,
      );
      ref.invalidate(aiConversationsProvider);
      _show(conversation);
    } on ApiException catch (error) {
      if (mounted && _input.text.isEmpty) _input.text = text;
      _showError(error);
    } finally {
      if (mounted) setState(() => _sendingQuestion = null);
    }
  }

  Future<void> _openHistory() async {
    final id = await showAiHistory(context);
    if (id != null && mounted) await _open(id);
    // La conversation affichée a pu être supprimée depuis l'historique.
    if (mounted && _conversation != null && ref.read(currentAiConversationProvider) == null) {
      _startNew();
    }
  }

  Future<void> _decide(AiMessage message, {required bool apply}) async {
    final conversation = _conversation;
    if (conversation == null) return;
    try {
      final updated = await _repository.decideAction(conversation.id, message.id, apply: apply);
      final current = _conversation;
      final action = updated.action;
      if (!mounted || current == null || current.id != conversation.id || action == null) return;
      setState(
        () => _conversation = AiConversation(
          id: current.id,
          title: current.title,
          updatedAt: current.updatedAt,
          isPending: current.isPending,
          messages: [
            for (final m in current.messages) m.id == message.id ? m.withAction(action) : m,
          ],
        ),
      );
    } on ApiException catch (error) {
      _showError(error);
    }
  }

  String? _routeFor(AiSource source) {
    final id = source.id;
    if (id == null) return null;
    return switch (source.type) {
      'work' || 'task' => Routes.task(id),
      'project' => Routes.project(id),
      'meeting' => Routes.meeting(id),
      _ => null,
    };
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _conversation?.title ?? 'Nouvelle conversation',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          IconButton(
            tooltip: 'Historique',
            icon: const Icon(Icons.history),
            onPressed: _openHistory,
          ),
          IconButton(
            tooltip: 'Nouvelle conversation',
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: _sendingQuestion == null ? _startNew : null,
          ),
        ],
      ),
    );
  }

  Widget _welcome(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Posez une question sur Astra. Les réponses s\'appuient uniquement '
          'sur les informations auxquelles vous avez accès, et vos conversations '
          'sont conservées dans l\'historique.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        for (final example in _examples)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ActionChip(label: Text(example), onPressed: () => _ask(example)),
          ),
      ],
    );
  }

  Widget _messages() {
    final messages = _conversation?.messages ?? const <AiMessage>[];
    final sending = _sendingQuestion;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final message in messages)
          message.status == AiMessageStatus.pending
              ? const _Thinking()
              : _Bubble(message: message, routeFor: _routeFor, onDecide: _decide),
        if (sending != null) ...[
          _Bubble(
            message: AiMessage(
              id: '',
              role: 'user',
              content: sending,
              sources: const [],
              status: AiMessageStatus.done,
            ),
            routeFor: _routeFor,
          ),
          const _Thinking(),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEmpty = _conversation == null && _sendingQuestion == null;
    return Column(
      children: [
        _header(context),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : isEmpty
              ? _welcome(context)
              : _messages(),
        ),
        if (_focus case final focus?)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: InputChip(
                avatar: const Icon(Icons.visibility_outlined, size: 18),
                label: Text('Ronda lit : ${focus.label}'),
                deleteButtonTooltipMessage: 'Retirer ce contexte',
                onDeleted: () => setState(() => _focus = null),
              ),
            ),
          ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 2000,
                    buildCounter: (_, {required currentLength, required isFocused, maxLength}) =>
                        null,
                    textInputAction: TextInputAction.send,
                    decoration: const InputDecoration(hintText: 'Que voulez-vous faire ?'),
                    onSubmitted: _ask,
                  ),
                ),
                IconButton(
                  tooltip: 'Envoyer',
                  icon: const Icon(Icons.send),
                  onPressed: _isBusy ? null : () => _ask(_input.text),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Thinking extends StatelessWidget {
  const _Thinking();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(8),
      child: Row(
        children: [
          SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 12),
          // Modèle local sur CPU : prévenir que la réponse peut prendre du temps.
          Expanded(
            child: Text(
              'Ronda réfléchit… cela peut prendre une minute. Vous pouvez quitter : '
              'la réponse sera enregistrée dans l\'historique.',
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.routeFor, this.onDecide});

  final AiMessage message;
  final String? Function(AiSource source) routeFor;
  final Future<void> Function(AiMessage message, {required bool apply})? onDecide;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final isFailed = message.status == AiMessageStatus.failed;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.85),
        decoration: BoxDecoration(
          color: isUser ? AstraTheme.primary.withValues(alpha: 0.25) : AstraTheme.surface,
          borderRadius: BorderRadius.circular(AstraTheme.radius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.focusTitle case final title?)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('À propos de : $title', style: Theme.of(context).textTheme.labelSmall),
              ),
            SelectableText(isFailed ? '⚠️ ${message.content}' : message.content),
            if (message.sources.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Sources', style: Theme.of(context).textTheme.labelMedium),
              for (final source in message.sources)
                InkWell(
                  onTap: switch (routeFor(source)) {
                    // Projets et réunions vivent dans les onglets : `go` évite de
                    // dupliquer leurs pages (la conversation reste dans l'historique).
                    final route? when source.type == 'project' || source.type == 'meeting' =>
                      () => context.go(route),
                    final route? => () => unawaited(context.push(route)),
                    null => null,
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      '[${source.number}] ${source.title}',
                      style: const TextStyle(color: AstraTheme.secondary),
                    ),
                  ),
                ),
            ],
            if ((message.action, onDecide) case (final action?, final decide?))
              AiActionCard(
                action: action,
                onDecide: ({required apply}) => decide(message, apply: apply),
              ),
          ],
        ),
      ),
    );
  }
}

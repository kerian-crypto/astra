import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_client/core/network/api_client.dart';
import 'package:astra_client/core/utils/json.dart';
import 'package:astra_client/core/utils/picked_file.dart';
import 'package:astra_client/features/messages/data/conversation.dart';

final conversationRepositoryProvider = Provider<ConversationRepository>(
  (ref) => ConversationRepository(ref.watch(apiProvider)),
);

class ConversationRepository {
  ConversationRepository(this._api);

  final Api _api;

  Future<List<Conversation>> list() =>
      _api.get('/client/conversations', parse: (data) => listOf(data, Conversation.fromJson));

  Future<Conversation> get(String id) =>
      _api.get('/client/conversations/$id', parse: (data) => Conversation.fromJson(data! as Json));

  Future<List<ChatMessage>> messages(String id, {DateTime? before}) => _api.get(
    '/client/conversations/$id/messages',
    query: {'before': ?before?.toUtc().toIso8601String()},
    parse: (data) => listOf(data, ChatMessage.fromJson),
    cache: before == null,
  );

  Future<Conversation> start({required String subject, required String body, String? projectId}) =>
      _api.post(
        '/client/conversations',
        data: {'subject': subject.trim(), 'body': body.trim(), 'project_id': ?projectId},
        parse: (data) => Conversation.fromJson(data! as Json),
      );

  Future<ChatMessage> send(String id, {String body = '', PickedFile? attachment}) async {
    final form = FormData.fromMap({
      'body': body.trim(),
      if (attachment != null) 'file': await attachment.toMultipart(),
    });
    return _api.post(
      '/client/conversations/$id/messages',
      data: form,
      parse: (data) => ChatMessage.fromJson(data! as Json),
    );
  }

  Future<void> markRead(String id) => _api.post<void>('/client/conversations/$id/read');
}

final conversationsProvider = FutureProvider.autoDispose<List<Conversation>>(
  (ref) => ref.watch(conversationRepositoryProvider).list(),
);

final conversationProvider = FutureProvider.autoDispose.family<Conversation, String>(
  (ref, id) => ref.watch(conversationRepositoryProvider).get(id),
);

final unreadMessagesProvider = Provider.autoDispose<int>(
  (ref) =>
      ref.watch(conversationsProvider).value?.fold<int>(0, (sum, c) => sum + c.unreadCount) ?? 0,
);

/// Messages d'une conversation, enrichis en direct par le temps réel.
final conversationMessagesProvider = AsyncNotifierProvider.autoDispose
    .family<ConversationMessages, List<ChatMessage>, String>(ConversationMessages.new);

class ConversationMessages extends AsyncNotifier<List<ChatMessage>> {
  ConversationMessages(this.conversationId);

  final String conversationId;
  bool _hasMore = true;

  bool get hasMore => _hasMore;

  @override
  Future<List<ChatMessage>> build() async {
    final messages = await ref.read(conversationRepositoryProvider).messages(conversationId);
    _hasMore = messages.length >= 50;
    return messages;
  }

  Future<void> loadOlder() async {
    final current = state.value;
    if (current == null || current.isEmpty || !_hasMore) return;
    final older = await ref
        .read(conversationRepositoryProvider)
        .messages(conversationId, before: current.first.createdAt);
    _hasMore = older.length >= 50;
    state = AsyncData([...older, ...current]);
  }

  /// Ajoute (ou remplace) un message reçu en direct ou envoyé.
  void upsert(ChatMessage message) {
    final current = state.value ?? const <ChatMessage>[];
    final others = current.where((m) => m.id != message.id);
    state = AsyncData([...others, message]..sort((a, b) => a.createdAt.compareTo(b.createdAt)));
  }
}

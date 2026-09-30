import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:astra_hub/core/network/api_client.dart';
import 'package:astra_hub/core/network/api_exception.dart';
import 'package:astra_hub/core/utils/json.dart';
import 'package:astra_hub/features/chat/data/chat.dart';
import 'package:astra_hub/features/chat/data/media_sources.dart';

final chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => ChatRepository(ref.watch(dioProvider), ref.watch(attachmentCacheDirProvider)),
);

/// Dossier privé où sont gardées les pièces jointes déjà téléchargées.
final attachmentCacheDirProvider = Provider<Future<Directory> Function()>(
  (_) =>
      () async => Directory('${(await getTemporaryDirectory()).path}/chat_attachments'),
);

class ChatRepository {
  ChatRepository(this._dio, this._cacheDir);

  static const pageSize = 40;

  final Dio _dio;
  final Future<Directory> Function() _cacheDir;

  Future<Json> _send(String method, String path, [Object? data]) => guardApi(() async {
    final response = await _dio.request<Json>(
      path,
      data: data,
      options: Options(method: method),
    );
    return response.data ?? const {};
  });

  Future<List<Channel>> channels() => guardApi(() async {
    final response = await _dio.get<List<dynamic>>('/channels');
    return listOf(response.data, Channel.fromJson);
  });

  Future<Channel> channel(String id) async => Channel.fromJson(await _send('GET', '/channels/$id'));

  Future<Channel> openDirect(String userId) async =>
      Channel.fromJson(await _send('POST', '/channels/direct', {'user_id': userId}));

  Future<Channel> projectChannel(String projectId) async =>
      Channel.fromJson(await _send('GET', '/projects/$projectId/channel'));

  Future<Channel> createGroup(String name, List<String> memberIds) async => Channel.fromJson(
    await _send('POST', '/channels', {
      'kind': 'private',
      'name': name.trim(),
      'member_ids': memberIds,
    }),
  );

  /// Messages du plus récent au plus ancien ; `before` pagine vers le passé.
  Future<List<ChatMessage>> messages(String channelId, {DateTime? before}) => guardApi(() async {
    final response = await _dio.get<List<dynamic>>(
      '/channels/$channelId/messages',
      queryParameters: {
        'limit': pageSize,
        if (before != null) 'before': before.toUtc().toIso8601String(),
      },
    );
    return listOf(response.data, ChatMessage.fromJson);
  });

  Future<ChatMessage> send(
    String channelId,
    String body, {
    String? replyToId,
    List<String> mentionedUserIds = const [],
  }) async => ChatMessage.fromJson(
    await _send('POST', '/channels/$channelId/messages', {
      'body': body.trim(),
      'reply_to_id': ?replyToId,
      'mentioned_user_ids': mentionedUserIds,
    }),
  );

  /// Photo, vidéo, message vocal ou document, avec légende facultative.
  Future<ChatMessage> sendAttachment(
    String channelId,
    PickedMedia media, {
    String caption = '',
    String? replyToId,
  }) => guardApi(() async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(media.path, filename: media.name),
      if (caption.trim().isNotEmpty) 'body': caption.trim(),
      'duration_ms': ?media.durationMs?.toString(),
      'reply_to_id': ?replyToId,
    });
    final response = await _dio.post<Json>('/channels/$channelId/attachments', data: form);
    return ChatMessage.fromJson(response.data!);
  });

  /// Télécharge la pièce jointe une seule fois (cache privé) et renvoie son fichier.
  Future<File> attachmentFile(String messageId, String name) => guardApi(() async {
    final directory = await _cacheDir();
    await directory.create(recursive: true);
    // Nom local sûr : identifiant du message + extension d'origine seulement.
    final extension = name.contains('.') ? name.substring(name.lastIndexOf('.')) : '';
    final target = File('${directory.path}/$messageId$extension');
    if (!await target.exists()) {
      await _dio.download('/messages/$messageId/attachment', target.path);
    }
    return target;
  });

  Future<ChatMessage> toggleReaction(ChatMessage message, String emoji) async {
    final mine = message.reactions.any((r) => r.emoji == emoji && r.reactedByMe);
    final path = '/messages/${message.id}/reactions/${Uri.encodeComponent(emoji)}';
    return ChatMessage.fromJson(await _send(mine ? 'DELETE' : 'PUT', path));
  }

  Future<ChatMessage> deleteMessage(String id) async =>
      ChatMessage.fromJson(await _send('DELETE', '/messages/$id'));

  /// Photo PNG ou JPEG du canal (réservé à ceux qui le gèrent).
  Future<Channel> setChannelPhoto(String channelId, PickedMedia photo) => guardApi(() async {
    final form = FormData.fromMap({
      'photo': await MultipartFile.fromFile(photo.path, filename: photo.name),
    });
    final response = await _dio.put<Json>('/channels/$channelId/photo', data: form);
    return Channel.fromJson(response.data!);
  });

  Future<Channel> removeChannelPhoto(String channelId) async =>
      Channel.fromJson(await _send('DELETE', '/channels/$channelId/photo'));

  Future<void> markRead(String channelId) => _send('POST', '/channels/$channelId/read');

  Future<List<AppNotification>> notifications() => guardApi(() async {
    final response = await _dio.get<List<dynamic>>('/notifications');
    return listOf(response.data, AppNotification.fromJson);
  });

  Future<void> markNotificationRead(String id) => _send('POST', '/notifications/$id/read');

  Future<void> markAllNotificationsRead() => _send('POST', '/notifications/read-all');
}

final channelsProvider = FutureProvider.autoDispose<List<Channel>>(
  (ref) => ref.watch(chatRepositoryProvider).channels(),
);

final channelProvider = FutureProvider.autoDispose.family<Channel, String>(
  (ref, id) => ref.watch(chatRepositoryProvider).channel(id),
);

final notificationsProvider = FutureProvider.autoDispose<List<AppNotification>>(
  (ref) => ref.watch(chatRepositoryProvider).notifications(),
);

final unreadNotificationsProvider = Provider.autoDispose<int>(
  (ref) => ref.watch(notificationsProvider).value?.where((n) => n.isUnread).length ?? 0,
);

/// Fil d'une conversation, du plus récent au plus ancien, alimenté par l'API
/// et par le temps réel.
final channelMessagesProvider = AsyncNotifierProvider.autoDispose
    .family<ChannelMessages, List<ChatMessage>, String>(ChannelMessages.new);

class ChannelMessages extends AsyncNotifier<List<ChatMessage>> {
  ChannelMessages(this.channelId);

  final String channelId;
  bool _hasMore = true;
  bool _loadingMore = false;

  ChatRepository get _repository => ref.read(chatRepositoryProvider);

  bool get hasMore => _hasMore;

  @override
  Future<List<ChatMessage>> build() async {
    final page = await _repository.messages(channelId);
    _hasMore = page.length == ChatRepository.pageSize;
    return page;
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.isEmpty || !_hasMore || _loadingMore) return;
    _loadingMore = true;
    try {
      final older = await _repository.messages(channelId, before: current.last.createdAt);
      _hasMore = older.length == ChatRepository.pageSize;
      state = AsyncData([...current, ...older]);
    } finally {
      _loadingMore = false;
    }
  }

  /// Insère ou remplace un message (envoi, temps réel, réaction, suppression).
  void upsert(ChatMessage message) {
    final current = state.value ?? const <ChatMessage>[];
    final index = current.indexWhere((m) => m.id == message.id);
    state = AsyncData(
      index == -1
          ? [message, ...current]
          : [...current.sublist(0, index), message, ...current.sublist(index + 1)],
    );
  }

  Future<void> send(String body, {String? replyToId, List<String> mentions = const []}) async {
    upsert(
      await _repository.send(channelId, body, replyToId: replyToId, mentionedUserIds: mentions),
    );
  }

  Future<void> sendAttachment(PickedMedia media, {String caption = '', String? replyToId}) async {
    upsert(
      await _repository.sendAttachment(channelId, media, caption: caption, replyToId: replyToId),
    );
  }
}

/// Fichier local d'une pièce jointe, téléchargé à la demande.
final attachmentFileProvider = FutureProvider.autoDispose.family<File, (String, String)>(
  (ref, key) => ref.read(chatRepositoryProvider).attachmentFile(key.$1, key.$2),
);

import 'package:astra_client/core/utils/json.dart';
import 'package:astra_client/features/deliverables/data/deliverable.dart';

enum ConversationKind { general, project, deliverable, ticket }

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.authorName,
    required this.fromAstra,
    required this.isMine,
    required this.body,
    required this.createdAt,
    this.file,
  });

  factory ChatMessage.fromJson(Json json) => ChatMessage(
    id: json['id'] as String,
    conversationId: json['conversation_id'] as String,
    authorName: json['author_name'] as String,
    fromAstra: json['from_astra'] as bool? ?? false,
    isMine: json['is_mine'] as bool? ?? false,
    body: json['body'] as String? ?? '',
    file: AttachedFile.fromJson(json['file']),
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  final String id;
  final String conversationId;
  final String authorName;
  final bool fromAstra;
  final bool isMine;
  final String body;
  final AttachedFile? file;
  final DateTime createdAt;
}

class Conversation {
  const Conversation({
    required this.id,
    required this.kind,
    required this.subject,
    required this.unreadCount,
    required this.createdAt,
    this.projectId,
    this.projectName,
    this.ticketId,
    this.lastMessage,
    this.lastMessageAt,
  });

  factory Conversation.fromJson(Json json) => Conversation(
    id: json['id'] as String,
    kind: enumFromJson(ConversationKind.values, json['kind'], ConversationKind.general),
    subject: json['subject'] as String,
    projectId: json['project_id'] as String?,
    projectName: json['project_name'] as String?,
    ticketId: json['ticket_id'] as String?,
    lastMessage: json['last_message'] == null
        ? null
        : ChatMessage.fromJson(json['last_message'] as Json),
    lastMessageAt: dateOrNull(json['last_message_at']),
    unreadCount: json['unread_count'] as int? ?? 0,
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  final String id;
  final ConversationKind kind;
  final String subject;
  final String? projectId;
  final String? projectName;
  final String? ticketId;
  final ChatMessage? lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final DateTime createdAt;

  DateTime get activityAt => lastMessageAt ?? createdAt;
}

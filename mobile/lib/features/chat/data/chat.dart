import 'package:astra_hub/core/utils/json.dart';
import 'package:astra_hub/features/members/data/member.dart';

enum ChannelKind { public, private, project, direct }

class Channel {
  const Channel({
    required this.id,
    required this.kind,
    required this.displayName,
    required this.unreadCount,
    required this.canPost,
    required this.announcementsOnly,
    this.description,
    this.projectId,
    this.lastMessageAt,
    this.members = const [],
    this.photoUrl,
    this.canManage = false,
  });

  factory Channel.fromJson(Json json) => Channel(
    id: json['id'] as String,
    kind: enumFromJson(ChannelKind.values, json['kind'], ChannelKind.public),
    displayName: json['display_name'] as String,
    description: json['description'] as String?,
    projectId: json['project_id'] as String?,
    unreadCount: json['unread_count'] as int,
    canPost: json['can_post'] as bool,
    announcementsOnly: json['announcements_only'] as bool,
    lastMessageAt: dateOrNull(json['last_message_at'])?.toLocal(),
    members: listOf(json['members'], Member.fromJson),
    photoUrl: json['photo_url'] as String?,
    canManage: json['can_manage'] as bool? ?? false,
  );

  final String id;
  final ChannelKind kind;
  final String displayName;
  final String? description;
  final String? projectId;
  final int unreadCount;
  final bool canPost;
  final bool announcementsOnly;
  final DateTime? lastMessageAt;
  final List<Member> members;

  /// Photo du canal (relative à l'API) ; celle de l'autre membre en direct.
  final String? photoUrl;

  /// Peut modifier le canal (nom, photo…).
  final bool canManage;

  String get title => switch (kind) {
    ChannelKind.public || ChannelKind.private => '# $displayName',
    ChannelKind.project => 'Projet · $displayName',
    ChannelKind.direct => displayName,
  };
}

class Reaction {
  const Reaction({required this.emoji, required this.count, required this.reactedByMe});

  factory Reaction.fromJson(Json json) => Reaction(
    emoji: json['emoji'] as String,
    count: json['count'] as int,
    reactedByMe: json['reacted_by_me'] as bool,
  );

  final String emoji;
  final int count;
  final bool reactedByMe;
}

enum AttachmentKind { image, video, audio, file }

/// Pièce jointe d'un message : photo, vidéo, message vocal ou document.
class ChatAttachment {
  const ChatAttachment({
    required this.kind,
    required this.name,
    required this.contentType,
    required this.sizeBytes,
    this.durationMs,
  });

  factory ChatAttachment.fromJson(Json json) => ChatAttachment(
    kind: enumFromJson(AttachmentKind.values, json['kind'], AttachmentKind.file),
    name: json['name'] as String,
    contentType: json['content_type'] as String,
    sizeBytes: json['size_bytes'] as int,
    durationMs: json['duration_ms'] as int?,
  );

  final AttachmentKind kind;
  final String name;
  final String contentType;
  final int sizeBytes;
  final int? durationMs;

  /// Libellé court (aperçu d'une réponse, notifications).
  String get label => switch (kind) {
    AttachmentKind.image => '📷 Photo',
    AttachmentKind.video => '🎬 Vidéo',
    AttachmentKind.audio => '🎤 Message vocal',
    AttachmentKind.file => '📄 $name',
  };
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.channelId,
    required this.body,
    required this.createdAt,
    required this.isDeleted,
    required this.reactions,
    this.author,
    this.replyToId,
    this.editedAt,
    this.attachment,
  });

  factory ChatMessage.fromJson(Json json) => ChatMessage(
    id: json['id'] as String,
    channelId: json['channel_id'] as String,
    author: json['author'] == null ? null : Member.fromJson(json['author'] as Json),
    body: json['body'] as String,
    replyToId: json['reply_to_id'] as String?,
    createdAt: DateTime.parse(json['created_at'] as String),
    editedAt: dateOrNull(json['edited_at']),
    isDeleted: json['is_deleted'] as bool,
    reactions: listOf(json['reactions'], Reaction.fromJson),
    attachment: switch (json['attachment']) {
      final Json attachment => ChatAttachment.fromJson(attachment),
      _ => null,
    },
  );

  final String id;
  final String channelId;
  final Member? author;
  final String body;
  final String? replyToId;
  final DateTime createdAt;
  final DateTime? editedAt;
  final bool isDeleted;
  final List<Reaction> reactions;
  final ChatAttachment? attachment;

  /// Texte d'aperçu : le corps, ou le type de pièce jointe s'il est vide.
  String get preview => body.isNotEmpty ? body : attachment?.label ?? '';
}

enum NotificationKind {
  mention('mention'),
  taskAssigned('task_assigned'),
  taskStatus('task_status'),
  taskComment('task_comment'),
  projectAdded('project_added'),
  projectStatus('project_status'),
  meetingInvite('meeting_invite'),
  meetingUpdated('meeting_updated'),
  meetingCancelled('meeting_cancelled'),
  decisionProposed('decision_proposed'),
  decisionReviewed('decision_reviewed'),
  documentAdded('document_added'),
  channelAdded('channel_added'),
  registrationRequest('registration_request'),
  other('');

  const NotificationKind(this.wire);

  /// Valeur envoyée par l'API.
  final String wire;

  static NotificationKind parse(Object? value) =>
      values.firstWhere((kind) => kind.wire == value && kind != other, orElse: () => other);
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.entityType,
    required this.entityId,
    required this.createdAt,
    this.body,
    this.readAt,
  });

  factory AppNotification.fromJson(Json json) => AppNotification(
    id: json['id'] as String,
    kind: NotificationKind.parse(json['kind']),
    title: json['title'] as String,
    body: json['body'] as String?,
    entityType: json['entity_type'] as String,
    entityId: json['entity_id'] as String,
    readAt: dateOrNull(json['read_at']),
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  final String id;
  final NotificationKind kind;
  final String title;
  final String? body;
  final String entityType;
  final String entityId;
  final DateTime? readAt;
  final DateTime createdAt;

  bool get isUnread => readAt == null;
}

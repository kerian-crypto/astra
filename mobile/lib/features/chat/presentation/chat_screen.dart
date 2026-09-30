import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_hub/core/network/api_exception.dart';
import 'package:astra_hub/core/widgets/async_value_view.dart';
import 'package:astra_hub/features/auth/presentation/auth_controller.dart';
import 'package:astra_hub/features/chat/data/chat.dart';
import 'package:astra_hub/features/chat/data/chat_repository.dart';
import 'package:astra_hub/features/chat/data/media_sources.dart';
import 'package:astra_hub/features/chat/presentation/attachment_view.dart';
import 'package:astra_hub/features/chat/presentation/channel_avatar.dart';
import 'package:astra_hub/features/chat/presentation/message_bubble.dart';
import 'package:astra_hub/features/members/data/member.dart';
import 'package:astra_hub/features/members/data/member_repository.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({required this.channelId, super.key});

  final String channelId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final Map<String, Member> _mentions = {};
  ChatMessage? _replyTo;
  bool _isSending = false;
  bool _hasText = false;

  /// Début de l'enregistrement vocal en cours (null : pas d'enregistrement).
  DateTime? _recordingSince;
  Timer? _recordingTicker;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _input.addListener(() {
      final hasText = _input.text.trim().isNotEmpty;
      if (hasText != _hasText) setState(() => _hasText = hasText);
    });
    unawaited(_markRead());
  }

  @override
  void dispose() {
    _recordingTicker?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _markRead() async {
    try {
      await ref.read(chatRepositoryProvider).markRead(widget.channelId);
      ref.invalidate(channelsProvider);
    } on ApiException {
      // Non bloquant : le compteur se corrigera au prochain passage.
    }
  }

  void _onScroll() {
    // La liste est inversée : le « haut » visuel correspond à la fin.
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 200) {
      unawaited(ref.read(channelMessagesProvider(widget.channelId).notifier).loadMore());
    }
  }

  Future<void> _pickMention() async {
    final List<Member> members;
    try {
      members = await ref.read(membersProvider.future);
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
      return;
    }
    if (!mounted) return;
    final member = await showModalBottomSheet<Member>(
      context: context,
      builder: (_) => ListView(
        children: [
          for (final m in members)
            ListTile(title: Text(m.fullName), onTap: () => Navigator.pop(context, m)),
        ],
      ),
    );
    if (member == null) return;
    _mentions[member.id] = member;
    final text = _input.text;
    _input.text = '${text.isEmpty || text.endsWith(' ') ? text : '$text '}@${member.fullName} ';
  }

  Future<void> _send() async {
    final body = _input.text.trim();
    if (body.isEmpty || _isSending) return;
    setState(() => _isSending = true);
    // Seules les mentions encore présentes dans le texte sont envoyées.
    final mentions = [
      for (final m in _mentions.values)
        if (body.contains('@${m.fullName}')) m.id,
    ];
    try {
      await ref
          .read(channelMessagesProvider(widget.channelId).notifier)
          .send(body, replyToId: _replyTo?.id, mentions: mentions);
      _input.clear();
      _mentions.clear();
      setState(() => _replyTo = null);
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Envoie une pièce jointe ; le texte saisi sert de légende.
  Future<void> _sendMedia(PickedMedia media) async {
    setState(() => _isSending = true);
    try {
      await ref
          .read(channelMessagesProvider(widget.channelId).notifier)
          .sendAttachment(media, caption: _input.text, replyToId: _replyTo?.id);
      _input.clear();
      _mentions.clear();
      if (mounted) setState(() => _replyTo = null);
    } on ApiException catch (error) {
      _showError(error.message);
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _attach() async {
    final source = await showModalBottomSheet<MediaSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (source, icon, label) in const [
              (MediaSource.galleryPhoto, Icons.photo_library_outlined, 'Photo de la galerie'),
              (MediaSource.cameraPhoto, Icons.photo_camera_outlined, 'Prendre une photo'),
              (MediaSource.galleryVideo, Icons.video_library_outlined, 'Vidéo de la galerie'),
              (MediaSource.cameraVideo, Icons.videocam_outlined, 'Filmer une vidéo'),
              (MediaSource.document, Icons.description_outlined, 'Document'),
            ])
              ListTile(
                leading: Icon(icon),
                title: Text(label),
                onTap: () => Navigator.pop(sheetContext, source),
              ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    final media = await ref.read(mediaPickerProvider).pick(source);
    if (media != null && mounted) await _sendMedia(media);
  }

  Future<void> _startRecording() async {
    if (!await ref.read(voiceRecorderProvider).start()) {
      return _showError('Autorisez le micro pour enregistrer un message vocal.');
    }
    if (!mounted) return;
    setState(() => _recordingSince = DateTime.now());
    _recordingTicker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  Future<void> _stopRecording({required bool send}) async {
    _recordingTicker?.cancel();
    final recorder = ref.read(voiceRecorderProvider);
    setState(() => _recordingSince = null);
    if (!send) return recorder.cancel();
    final media = await recorder.stop();
    if (media != null && mounted) await _sendMedia(media);
  }

  /// Photo du canal : galerie, appareil photo ou suppression.
  Future<void> _editPhoto(Channel channel) async {
    final choice = await showModalBottomSheet<_PhotoChoice>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choisir dans la galerie'),
              onTap: () => Navigator.pop(sheetContext, _PhotoChoice.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Prendre une photo'),
              onTap: () => Navigator.pop(sheetContext, _PhotoChoice.camera),
            ),
            if (channel.photoUrl != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Retirer la photo'),
                onTap: () => Navigator.pop(sheetContext, _PhotoChoice.remove),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    final repository = ref.read(chatRepositoryProvider);
    try {
      if (choice == _PhotoChoice.remove) {
        setState(() => _isSending = true);
        await repository.removeChannelPhoto(channel.id);
      } else {
        final source = choice == _PhotoChoice.camera
            ? MediaSource.cameraPhoto
            : MediaSource.galleryPhoto;
        final photo = await ref.read(mediaPickerProvider).pick(source);
        if (photo == null || !mounted) return;
        setState(() => _isSending = true);
        await repository.setChannelPhoto(channel.id, photo);
      }
      _refreshChannel();
    } on ApiException catch (error) {
      _showError(error.message);
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _refreshChannel() {
    ref
      ..invalidate(channelProvider(widget.channelId))
      ..invalidate(channelsProvider);
  }

  Future<void> _onAction(ChatMessage message, MessageAction action) async {
    final repository = ref.read(chatRepositoryProvider);
    final notifier = ref.read(channelMessagesProvider(widget.channelId).notifier);
    try {
      switch (action) {
        case ReplyAction():
          setState(() => _replyTo = message);
        case ReactAction(:final emoji):
          notifier.upsert(await repository.toggleReaction(message, emoji));
        case DeleteAction():
          notifier.upsert(await repository.deleteMessage(message.id));
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final channel = ref.watch(channelProvider(widget.channelId));
    final messages = ref.watch(channelMessagesProvider(widget.channelId));
    final meId = ref.watch(authControllerProvider).value?.id;
    // Gardé en vie tant que l'écran est ouvert (enregistrement en cours).
    ref.watch(voiceRecorderProvider);
    final canPost = channel.value?.canPost ?? false;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            if (channel.value case final current?)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: current.canManage ? () => _editPhoto(current) : null,
                  child: Tooltip(
                    message: current.canManage ? 'Changer la photo du canal' : current.title,
                    child: ChannelAvatar(channel: current, radius: 18),
                  ),
                ),
              ),
            Expanded(
              child: Text(channel.value?.title ?? 'Conversation', overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: AsyncValueView(
              value: messages,
              onRetry: () => ref.invalidate(channelMessagesProvider(widget.channelId)),
              data: (items) => items.isEmpty
                  ? const EmptyState(icon: Icons.chat_outlined, message: 'Aucun message.')
                  : ListView.builder(
                      controller: _scroll,
                      reverse: true,
                      padding: const EdgeInsets.all(12),
                      itemCount: items.length,
                      itemBuilder: (_, index) {
                        final message = items[index];
                        final replied = message.replyToId == null
                            ? null
                            : items.where((m) => m.id == message.replyToId).firstOrNull;
                        return MessageBubble(
                          message: message,
                          isMine: message.author?.id == meId,
                          repliedTo: replied,
                          onAction: (action) => _onAction(message, action),
                        );
                      },
                    ),
            ),
          ),
          if (canPost) _composer(context) else _readOnlyNotice(context),
        ],
      ),
    );
  }

  Widget _readOnlyNotice(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        'Lecture seule : vous ne pouvez pas publier dans ce canal.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ),
  );

  Widget _composer(BuildContext context) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_replyTo != null)
          ListTile(
            dense: true,
            leading: const Icon(Icons.reply, size: 18),
            title: Text(
              'Réponse à ${_replyTo!.author?.fullName ?? 'un message'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            subtitle: Text(_replyTo!.preview, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              tooltip: 'Annuler la réponse',
              icon: const Icon(Icons.close),
              onPressed: () => setState(() => _replyTo = null),
            ),
          ),
        if (_isSending) const LinearProgressIndicator(minHeight: 2),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          child: _recordingSince == null ? _inputRow() : _recordingRow(context),
        ),
      ],
    ),
  );

  Widget _inputRow() => Row(
    children: [
      IconButton(
        tooltip: 'Mentionner un membre',
        icon: const Icon(Icons.alternate_email),
        onPressed: _pickMention,
      ),
      IconButton(
        tooltip: 'Joindre un fichier',
        icon: const Icon(Icons.attach_file),
        onPressed: _isSending ? null : _attach,
      ),
      Expanded(
        child: TextField(
          controller: _input,
          minLines: 1,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Message'),
        ),
      ),
      if (_hasText)
        IconButton(
          tooltip: 'Envoyer',
          icon: const Icon(Icons.send),
          onPressed: _isSending ? null : _send,
        )
      else
        IconButton(
          tooltip: 'Message vocal',
          icon: const Icon(Icons.mic_none),
          onPressed: _isSending ? null : _startRecording,
        ),
    ],
  );

  Widget _recordingRow(BuildContext context) {
    final since = _recordingSince ?? DateTime.now();
    return Row(
      children: [
        IconButton(
          tooltip: 'Annuler l\'enregistrement',
          icon: const Icon(Icons.delete_outline),
          onPressed: () => _stopRecording(send: false),
        ),
        const Icon(Icons.fiber_manual_record, color: Colors.red, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text('Enregistrement… ${formatClock(DateTime.now().difference(since))}')),
        IconButton(
          tooltip: 'Envoyer le message vocal',
          icon: const Icon(Icons.send),
          onPressed: () => _stopRecording(send: true),
        ),
      ],
    );
  }
}

enum _PhotoChoice { gallery, camera, remove }

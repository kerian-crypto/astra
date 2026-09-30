import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:video_player/video_player.dart';

import 'package:astra_hub/core/network/api_exception.dart';
import 'package:astra_hub/features/chat/data/chat.dart';
import 'package:astra_hub/features/chat/data/chat_repository.dart';

/// « 0:42 », « 12:05 ».
String formatClock(Duration duration) {
  final seconds = duration.inSeconds;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// « 820 o », « 12 Ko », « 3,4 Mo ».
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes o';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} Ko';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} Mo';
}

/// Pièce jointe d'un message, selon son type.
class AttachmentView extends StatelessWidget {
  const AttachmentView({required this.messageId, required this.attachment, super.key});

  final String messageId;
  final ChatAttachment attachment;

  @override
  Widget build(BuildContext context) {
    final key = (messageId, attachment.name);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: switch (attachment.kind) {
        AttachmentKind.image => _ImageAttachment(fileKey: key),
        AttachmentKind.video => _VideoAttachment(fileKey: key, attachment: attachment),
        AttachmentKind.audio => _VoiceAttachment(fileKey: key, attachment: attachment),
        AttachmentKind.file => _FileAttachment(fileKey: key, attachment: attachment),
      },
    );
  }
}

Future<File?> _download(BuildContext context, WidgetRef ref, (String, String) key) async {
  try {
    return await ref.read(attachmentFileProvider(key).future);
  } on ApiException catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
    return null;
  }
}

class _ImageAttachment extends ConsumerWidget {
  const _ImageAttachment({required this.fileKey});

  final (String, String) fileKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final file = ref.watch(attachmentFileProvider(fileKey));
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: switch (file) {
        AsyncData(:final value) => GestureDetector(
          onTap: () => unawaited(
            Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => _PhotoViewer(file: value))),
          ),
          child: Image.file(
            value,
            height: 220,
            fit: BoxFit.cover,
            semanticLabel: 'Photo',
            errorBuilder: (_, _, _) => const _Placeholder(icon: Icons.broken_image_outlined),
          ),
        ),
        AsyncError() => const _Placeholder(icon: Icons.broken_image_outlined),
        _ => const _Placeholder(icon: Icons.image_outlined, isLoading: true),
      },
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.icon, this.isLoading = false});

  final IconData icon;
  final bool isLoading;

  @override
  Widget build(BuildContext context) => Container(
    width: 200,
    height: 150,
    color: Colors.black26,
    alignment: Alignment.center,
    child: isLoading ? const CircularProgressIndicator(strokeWidth: 2) : Icon(icon, size: 40),
  );
}

class _PhotoViewer extends StatelessWidget {
  const _PhotoViewer({required this.file});

  final File file;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(backgroundColor: Colors.black),
    body: Center(child: InteractiveViewer(maxScale: 5, child: Image.file(file))),
  );
}

class _VideoAttachment extends ConsumerWidget {
  const _VideoAttachment({required this.fileKey, required this.attachment});

  final (String, String) fileKey;
  final ChatAttachment attachment;

  Future<void> _play(BuildContext context, WidgetRef ref) async {
    final file = await _download(context, ref, fileKey);
    if (file == null || !context.mounted) return;
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => _VideoPlayerPage(file: file)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final duration = attachment.durationMs;
    return InkWell(
      onTap: () => _play(context, ref),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 220,
        height: 130,
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(Icons.play_circle_fill, size: 52, semanticLabel: 'Lire la vidéo'),
            Positioned(
              left: 8,
              right: 8,
              bottom: 6,
              child: Text(
                [
                  attachment.name,
                  if (duration != null) formatClock(Duration(milliseconds: duration)),
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoPlayerPage extends StatefulWidget {
  const _VideoPlayerPage({required this.file});

  final File file;

  @override
  State<_VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<_VideoPlayerPage> {
  late final VideoPlayerController _controller = VideoPlayerController.file(widget.file);
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      await _controller.initialize();
      await _controller.play();
    } on Exception {
      _error = 'Lecture impossible sur cet appareil.';
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = _controller.value;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black),
      body: Center(
        child: switch ((_error, value.isInitialized)) {
          (final error?, _) => Text(error),
          (_, false) => const CircularProgressIndicator(),
          _ => AspectRatio(
            aspectRatio: value.aspectRatio,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                VideoPlayer(_controller),
                VideoProgressIndicator(_controller, allowScrubbing: true),
              ],
            ),
          ),
        },
      ),
      floatingActionButton: value.isInitialized
          ? FloatingActionButton(
              tooltip: value.isPlaying ? 'Pause' : 'Lecture',
              onPressed: () async {
                await (value.isPlaying ? _controller.pause() : _controller.play());
                if (mounted) setState(() {});
              },
              child: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
            )
          : null,
    );
  }
}

class _VoiceAttachment extends ConsumerStatefulWidget {
  const _VoiceAttachment({required this.fileKey, required this.attachment});

  final (String, String) fileKey;
  final ChatAttachment attachment;

  @override
  ConsumerState<_VoiceAttachment> createState() => _VoiceAttachmentState();
}

class _VoiceAttachmentState extends ConsumerState<_VoiceAttachment> {
  AudioPlayer? _player; // créé au premier appui : aucun lecteur pour un fil non écouté
  bool _isLoading = false;

  @override
  void dispose() {
    unawaited(_player?.dispose());
    super.dispose();
  }

  Future<void> _toggle() async {
    final player = _player;
    if (player != null) {
      if (player.playing) return player.pause();
      if (player.processingState == ProcessingState.completed) await player.seek(Duration.zero);
      return player.play();
    }
    setState(() => _isLoading = true);
    final file = await _download(context, ref, widget.fileKey);
    if (!mounted) return;
    if (file == null) return setState(() => _isLoading = false);
    final created = AudioPlayer();
    try {
      await created.setFilePath(file.path);
    } on Exception {
      await created.dispose();
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Lecture impossible sur cet appareil.')));
      }
      return;
    }
    if (!mounted) return unawaited(created.dispose());
    setState(() {
      _player = created;
      _isLoading = false;
    });
    unawaited(created.play());
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    final known = Duration(milliseconds: widget.attachment.durationMs ?? 0);
    return SizedBox(
      width: 230,
      child: Row(
        children: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            StreamBuilder<PlayerState>(
              stream: player?.playerStateStream,
              builder: (_, snapshot) {
                final isPlaying =
                    snapshot.data?.playing == true &&
                    snapshot.data?.processingState != ProcessingState.completed;
                return IconButton(
                  tooltip: isPlaying ? 'Pause' : 'Écouter le message vocal',
                  icon: Icon(isPlaying ? Icons.pause_circle : Icons.play_circle, size: 36),
                  onPressed: _toggle,
                );
              },
            ),
          Expanded(
            child: StreamBuilder<Duration>(
              stream: player?.positionStream,
              builder: (_, snapshot) {
                final total = player?.duration ?? known;
                final position = snapshot.data ?? Duration.zero;
                final progress = total.inMilliseconds == 0
                    ? 0.0
                    : (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LinearProgressIndicator(value: progress),
                    const SizedBox(height: 4),
                    Text(
                      player == null ? formatClock(known) : formatClock(position),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FileAttachment extends ConsumerStatefulWidget {
  const _FileAttachment({required this.fileKey, required this.attachment});

  final (String, String) fileKey;
  final ChatAttachment attachment;

  @override
  ConsumerState<_FileAttachment> createState() => _FileAttachmentState();
}

class _FileAttachmentState extends ConsumerState<_FileAttachment> {
  bool _isOpening = false;

  Future<void> _open() async {
    setState(() => _isOpening = true);
    try {
      final file = await _download(context, ref, widget.fileKey);
      if (file == null || !mounted) return;
      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Aucune application pour ouvrir ce fichier.')));
      }
    } finally {
      if (mounted) setState(() => _isOpening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _isOpening ? null : _open,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 230,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
        child: Row(
          children: [
            _isOpening
                ? const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.description_outlined),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.attachment.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    formatBytes(widget.attachment.sizeBytes),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

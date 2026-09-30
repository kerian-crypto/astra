import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Fichier choisi ou enregistré sur l'appareil, prêt à être envoyé.
class PickedMedia {
  const PickedMedia({required this.path, required this.name, this.durationMs});

  final String path;
  final String name;
  final int? durationMs;
}

enum MediaSource { galleryPhoto, cameraPhoto, galleryVideo, cameraVideo, document }

/// Choix d'une photo, d'une vidéo ou d'un document (remplaçable en test).
abstract interface class MediaPicker {
  Future<PickedMedia?> pick(MediaSource source);
}

/// Enregistrement d'un message vocal (remplaçable en test).
abstract interface class VoiceRecorder {
  /// Faux si le micro n'est pas autorisé.
  Future<bool> start();

  Future<PickedMedia?> stop();

  Future<void> cancel();
}

/// Documents acceptés par le serveur dans le chat (en plus des médias).
const chatDocumentExtensions = ['pdf', 'txt', 'md', 'csv', 'docx', 'xlsx', 'pptx', 'odt'];

class DeviceMediaPicker implements MediaPicker {
  final _images = ImagePicker();

  @override
  Future<PickedMedia?> pick(MediaSource source) async {
    final XFile? file = switch (source) {
      MediaSource.galleryPhoto => await _images.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 2048,
      ),
      MediaSource.cameraPhoto => await _images.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 2048,
      ),
      MediaSource.galleryVideo => await _images.pickVideo(source: ImageSource.gallery),
      MediaSource.cameraVideo => await _images.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(minutes: 3),
      ),
      MediaSource.document => null,
    };
    if (file != null) return PickedMedia(path: file.path, name: file.name);
    if (source != MediaSource.document) return null;

    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: chatDocumentExtensions,
    );
    final picked = files.firstOrNull;
    final path = picked?.path;
    return picked == null || path == null ? null : PickedMedia(path: path, name: picked.name);
  }
}

class DeviceVoiceRecorder implements VoiceRecorder {
  // Créé au premier enregistrement : ouvrir une conversation n'active pas le micro.
  AudioRecorder? _created;
  final _clock = Stopwatch();

  AudioRecorder get _recorder => _created ??= AudioRecorder();

  @override
  Future<bool> start() async {
    if (!await _recorder.hasPermission()) return false;
    final directory = await getTemporaryDirectory();
    final path = '${directory.path}/vocal-${DateTime.now().millisecondsSinceEpoch}.m4a';
    // AAC mono dans un conteneur .m4a : léger et lisible partout.
    await _recorder.start(const RecordConfig(numChannels: 1, bitRate: 64000), path: path);
    _clock
      ..reset()
      ..start();
    return true;
  }

  @override
  Future<PickedMedia?> stop() async {
    _clock.stop();
    final path = await _recorder.stop();
    if (path == null || !await File(path).exists()) return null;
    return PickedMedia(
      path: path,
      name: path.split('/').last,
      durationMs: _clock.elapsedMilliseconds,
    );
  }

  @override
  Future<void> cancel() async {
    _clock.stop();
    await _created?.cancel();
  }

  Future<void> dispose() async => _created?.dispose();
}

final mediaPickerProvider = Provider<MediaPicker>((_) => DeviceMediaPicker());

final voiceRecorderProvider = Provider.autoDispose<VoiceRecorder>((ref) {
  final recorder = DeviceVoiceRecorder();
  ref.onDispose(recorder.dispose);
  return recorder;
});

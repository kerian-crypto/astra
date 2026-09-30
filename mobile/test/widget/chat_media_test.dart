import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:astra_hub/core/network/api_exception.dart';
import 'package:astra_hub/core/utils/json.dart';
import 'package:astra_hub/features/chat/data/chat_repository.dart';
import 'package:astra_hub/features/chat/data/media_sources.dart';
import 'package:astra_hub/features/chat/presentation/attachment_view.dart';
import 'package:astra_hub/features/chat/presentation/channel_avatar.dart';

import '../helpers/fake_backend.dart';

class FakePicker implements MediaPicker {
  FakePicker(this.media);

  final PickedMedia? media;
  final List<MediaSource> requested = [];

  @override
  Future<PickedMedia?> pick(MediaSource source) async {
    requested.add(source);
    return media;
  }
}

class FakeRecorder implements VoiceRecorder {
  FakeRecorder(this.media, {this.allowed = true});

  final PickedMedia media;
  final bool allowed;
  bool isCancelled = false;

  @override
  Future<bool> start() async => allowed;

  @override
  Future<PickedMedia?> stop() async => media;

  @override
  Future<void> cancel() async => isCancelled = true;
}

Json attachmentMessage(String id, String kind, String name, {int? durationMs, String body = ''}) =>
    {
      ...messageJson(id: id, body: body),
      'attachment': {
        'kind': kind,
        'name': name,
        'content_type': 'application/octet-stream',
        'size_bytes': 12 * 1024,
        'duration_ms': durationMs,
      },
    };

void main() {
  setUpAll(() => initializeDateFormatting('fr'));

  late File document;
  late File voice;

  setUp(() {
    final directory = Directory.systemTemp.createTempSync('astra-media-');
    document = File('${directory.path}/devis.pdf')..writeAsBytesSync([37, 80, 68, 70]);
    voice = File('${directory.path}/vocal.m4a')..writeAsBytesSync(List.filled(32, 0));
    addTearDown(() => directory.deleteSync(recursive: true));
  });

  Future<FakeBackend> openChannel(
    WidgetTester tester, {
    FakeBackend? backend,
    MediaPicker? picker,
    VoiceRecorder? recorder,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    final fake = backend ?? FakeBackend();
    await tester.pumpWidget(
      fake.app(
        overrides: [
          // Pas de téléchargement réel dans les tests : les aperçus s'affichent en erreur.
          attachmentCacheDirProvider.overrideWithValue(
            () async => throw const ApiException('Hors ligne'),
          ),
          if (picker != null) mediaPickerProvider.overrideWithValue(picker),
          if (recorder != null) voiceRecorderProvider.overrideWithValue(recorder),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'ada@astra.example.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Mot de passe'), 'secret-password');
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(NavigationBar), matching: find.text('Messages')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('# général'));
    await tester.pumpAndSettle();
    return fake;
  }

  /// L'envoi multipart lit le vrai fichier : il faut laisser passer de vraies E/S.
  Future<void> tapWithRealIo(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pump(const Duration(milliseconds: 500)); // fermeture de la feuille
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
  }

  testWidgets('every attachment kind is shown in the thread', (tester) async {
    final backend = FakeBackend();
    backend.messages
      ..clear()
      ..addAll([
        attachmentMessage('m4', 'file', 'devis.pdf', body: 'Le devis signé'),
        attachmentMessage('m3', 'audio', 'vocal.m4a', durationMs: 4200),
        attachmentMessage('m2', 'video', 'clip.mp4', durationMs: 7000),
        attachmentMessage('m1', 'image', 'plage.jpg'),
      ]);

    await openChannel(tester, backend: backend);

    expect(find.byType(AttachmentView), findsNWidgets(4));
    expect(find.text('devis.pdf'), findsOneWidget);
    expect(find.text('12 Ko'), findsOneWidget);
    expect(find.text('Le devis signé'), findsOneWidget);
    expect(find.byTooltip('Écouter le message vocal'), findsOneWidget);
    expect(find.text('0:04'), findsOneWidget);
    expect(find.text('clip.mp4 · 0:07'), findsOneWidget);
  });

  testWidgets('a document is sent with the typed text as caption', (tester) async {
    final picker = FakePicker(PickedMedia(path: document.path, name: 'devis.pdf'));
    final backend = await openChannel(tester, picker: picker);

    await tester.enterText(find.widgetWithText(TextField, 'Message'), 'Voici le devis');
    await tester.tap(find.byTooltip('Joindre un fichier'));
    await tester.pumpAndSettle();
    await tapWithRealIo(tester, find.text('Document'));

    expect(picker.requested, [MediaSource.document]);
    final form = backend.writes['POST /channels/c1/attachments']! as FormData;
    expect(form.files.single.value.filename, 'devis.pdf');
    expect(Map.fromEntries(form.fields), {'body': 'Voici le devis'});
    expect(find.text('devis.pdf'), findsOneWidget);
    expect(find.text('Voici le devis'), findsOneWidget);
  });

  testWidgets('nothing is sent when the picker is dismissed', (tester) async {
    final backend = await openChannel(tester, picker: FakePicker(null));

    await tester.tap(find.byTooltip('Joindre un fichier'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Photo de la galerie'));
    await tester.pumpAndSettle();

    expect(backend.writes.containsKey('POST /channels/c1/attachments'), isFalse);
  });

  testWidgets('a voice message is recorded then sent with its duration', (tester) async {
    final recorder = FakeRecorder(
      PickedMedia(path: voice.path, name: 'vocal.m4a', durationMs: 4200),
    );
    final backend = await openChannel(tester, recorder: recorder);

    await tester.tap(find.byTooltip('Message vocal'));
    await tester.pump();
    expect(find.textContaining('Enregistrement…'), findsOneWidget);

    await tapWithRealIo(tester, find.byTooltip('Envoyer le message vocal'));

    final form = backend.writes['POST /channels/c1/attachments']! as FormData;
    expect(form.files.single.value.filename, 'vocal.m4a');
    expect(Map.fromEntries(form.fields), {'duration_ms': '4200'});
    expect(find.byTooltip('Écouter le message vocal'), findsOneWidget);
    expect(find.textContaining('Enregistrement…'), findsNothing);
  });

  testWidgets('a recording can be cancelled', (tester) async {
    final recorder = FakeRecorder(PickedMedia(path: voice.path, name: 'vocal.m4a'));
    final backend = await openChannel(tester, recorder: recorder);

    await tester.tap(find.byTooltip('Message vocal'));
    await tester.pump();
    await tester.tap(find.byTooltip('Annuler l\'enregistrement'));
    await tester.pumpAndSettle();

    expect(recorder.isCancelled, isTrue);
    expect(backend.writes.containsKey('POST /channels/c1/attachments'), isFalse);
    expect(find.byTooltip('Message vocal'), findsOneWidget);
  });

  testWidgets('a refused microphone is explained', (tester) async {
    final recorder = FakeRecorder(PickedMedia(path: voice.path, name: 'x.m4a'), allowed: false);
    await openChannel(tester, recorder: recorder);

    await tester.tap(find.byTooltip('Message vocal'));
    await tester.pumpAndSettle();

    expect(find.text('Autorisez le micro pour enregistrer un message vocal.'), findsOneWidget);
    expect(find.textContaining('Enregistrement…'), findsNothing);
  });

  testWidgets('a channel manager changes the channel photo', (tester) async {
    final picker = FakePicker(PickedMedia(path: document.path, name: 'logo.jpg'));
    final backend = FakeBackend()..canManageChannel = true;
    await openChannel(tester, backend: backend, picker: picker);

    await tester.tap(find.byTooltip('Changer la photo du canal'));
    await tester.pumpAndSettle();
    expect(find.text('Retirer la photo'), findsNothing); // aucune photo pour l'instant
    await tapWithRealIo(tester, find.text('Choisir dans la galerie'));

    expect(picker.requested, [MediaSource.galleryPhoto]);
    final form = backend.writes['PUT /channels/c1/photo']! as FormData;
    expect(form.files.single.key, 'photo');
    expect(form.files.single.value.filename, 'logo.jpg');
    expect(backend.channelPhoto, 'channels/c1/photo?v=1');
  });

  testWidgets('a channel manager removes the channel photo', (tester) async {
    final backend = FakeBackend()
      ..canManageChannel = true
      ..channelPhoto = 'channels/c1/photo?v=1';
    await openChannel(tester, backend: backend);

    await tester.tap(find.byTooltip('Changer la photo du canal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retirer la photo'));
    await tester.pumpAndSettle();

    expect(backend.calls, contains('DELETE /channels/c1/photo'));
    expect(backend.channelPhoto, isNull);
  });

  testWidgets('members who do not manage the channel cannot change its photo', (tester) async {
    final backend = await openChannel(tester);

    expect(find.byTooltip('Changer la photo du canal'), findsNothing);
    await tester.tap(find.byType(ChannelAvatar));
    await tester.pumpAndSettle();

    expect(find.text('Choisir dans la galerie'), findsNothing);
    expect(backend.writes.containsKey('PUT /channels/c1/photo'), isFalse);
  });

  test('sizes and durations are formatted for people', () {
    expect(formatBytes(820), '820 o');
    expect(formatBytes(12 * 1024), '12 Ko');
    expect(formatBytes(3565158), '3,4 Mo');
    expect(formatClock(const Duration(seconds: 65)), '1:05');
  });
}

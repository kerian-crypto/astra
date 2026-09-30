import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_hub/core/theme/astra_theme.dart';
import 'package:astra_hub/features/chat/data/chat.dart';
import 'package:astra_hub/features/members/presentation/member_avatar.dart';

/// Photo du canal, ou icône de son type si aucune photo n'est définie.
class ChannelAvatar extends ConsumerWidget {
  const ChannelAvatar({required this.channel, this.radius = 20, super.key});

  final Channel channel;
  final double radius;

  IconData get _icon => switch (channel.kind) {
    ChannelKind.public => channel.announcementsOnly ? Icons.campaign_outlined : Icons.tag,
    ChannelKind.private => Icons.lock_outline,
    ChannelKind.project => Icons.folder_outlined,
    ChannelKind.direct => Icons.person_outline,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photo = switch (channel.photoUrl) {
      final String url => resolvePhotoUrl(url),
      null => null,
    };
    final headers = photo == null ? null : ref.watch(photoHeadersProvider).value;
    return CircleAvatar(
      radius: radius,
      backgroundColor: AstraTheme.primary.withValues(alpha: 0.25),
      foregroundImage: photo == null || headers == null
          ? null
          : NetworkImage(photo, headers: headers),
      // En cas d'échec (hors ligne, session expirée), l'icône reste.
      onForegroundImageError: photo == null || headers == null ? null : (_, _) {},
      child: Icon(_icon, size: radius, color: AstraTheme.textPrimary),
    );
  }
}

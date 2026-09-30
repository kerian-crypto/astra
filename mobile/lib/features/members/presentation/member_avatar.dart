import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_hub/core/config/app_config.dart';
import 'package:astra_hub/core/network/api_client.dart';
import 'package:astra_hub/core/theme/astra_theme.dart';
import 'package:astra_hub/features/members/data/member.dart';

/// En-tête d'authentification pour les photos servies par l'API (elles ne sont
/// accessibles qu'aux membres connectés).
final photoHeadersProvider = FutureProvider.autoDispose<Map<String, String>>((ref) async {
  final tokens = await ref.watch(tokenStorageProvider).read();
  return tokens == null ? const {} : {'Authorization': 'Bearer ${tokens.accessToken}'};
});

/// URL absolue d'une photo servie par l'API, ou `null` pour toute autre
/// adresse : le jeton de connexion ne doit jamais partir vers un site tiers.
String? resolvePhotoUrl(String photo) {
  final isRelative = !photo.contains('://') && !photo.startsWith('//');
  return isRelative ? '${AppConfig.apiBaseUrl}/$photo' : null;
}

class MemberAvatar extends ConsumerWidget {
  const MemberAvatar({required this.member, this.radius = 20, super.key});

  final Member member;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photo = switch (member.photoUrl) {
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
      // En cas d'échec (hors ligne, session expirée), les initiales restent.
      onForegroundImageError: photo == null || headers == null ? null : (_, _) {},
      child: Text(
        member.initials,
        style: TextStyle(fontSize: radius * 0.8, color: AstraTheme.textPrimary),
      ),
    );
  }
}

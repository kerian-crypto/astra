import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:astra_hub/core/router/routes.dart';
import 'package:astra_hub/core/widgets/astra_app_bar.dart';

import 'package:astra_hub/core/network/api_exception.dart';
import 'package:astra_hub/features/auth/data/registration_repository.dart';
import 'package:astra_hub/features/auth/presentation/auth_controller.dart';
import 'package:astra_hub/features/members/data/member.dart';
import 'package:astra_hub/features/members/presentation/member_avatar.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _changePhoto(BuildContext context, WidgetRef ref) async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg'],
    );
    final file = files.firstOrNull;
    if (file?.path == null) return;
    try {
      final member = await ref
          .read(registrationRepositoryProvider)
          .updateMyPhoto(file!.path!, file.name);
      ref.read(authControllerProvider.notifier).updateMember(member);
    } on ApiException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final member = ref.watch(authControllerProvider).value;
    if (member == null) return const SizedBox.shrink();
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: const AstraAppBar(title: 'Profil'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Stack(
              children: [
                MemberAvatar(member: member, radius: 40),
                Positioned(
                  right: -8,
                  bottom: -8,
                  child: IconButton.filledTonal(
                    tooltip: 'Changer de photo',
                    icon: const Icon(Icons.photo_camera_outlined, size: 18),
                    onPressed: () => _changePhoto(context, ref),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(member.fullName, textAlign: TextAlign.center, style: textTheme.titleLarge),
          if (member.jobTitle != null)
            Text(member.jobTitle!, textAlign: TextAlign.center, style: textTheme.bodyMedium),
          const SizedBox(height: 24),
          ListTile(leading: const Icon(Icons.email_outlined), title: Text(member.email)),
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: Text(member.accessLevel.label),
            subtitle: const Text('Niveau d\'accès'),
          ),
          ListTile(
            leading: const Icon(Icons.speed_outlined),
            title: Text('${member.availability} %'),
            subtitle: const Text('Disponibilité'),
          ),
          if (member.skills.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Compétences', style: textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final skill in member.skills) Chip(label: Text(skill))],
            ),
          ],
          const SizedBox(height: 24),
          if (member.accessLevel == AccessLevel.admin)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.how_to_reg_outlined),
              title: const Text('Demandes d\'inscription'),
              subtitle: const Text('Valider les nouveaux comptes'),
              onTap: () => context.push(Routes.registrations),
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.library_books_outlined),
            title: const Text('Documents d\'Astra'),
            subtitle: const Text('Guides, retours d\'expérience, connaissances'),
            onTap: () => context.push(Routes.documents),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.monitor_heart_outlined),
            title: const Text('État de santé d\'Astra'),
            onTap: () => context.push(Routes.health),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
            icon: const Icon(Icons.logout),
            label: const Text('Se déconnecter'),
          ),
        ],
      ),
    );
  }
}

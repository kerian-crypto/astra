import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_hub/core/network/api_exception.dart';
import 'package:astra_hub/features/members/data/member.dart';
import 'package:astra_hub/features/members/data/member_repository.dart';
import 'package:astra_hub/features/members/presentation/member_avatar.dart';
import 'package:astra_hub/features/projects/data/project.dart';
import 'package:astra_hub/features/projects/data/project_repository.dart';

/// Membres du projet ; le responsable peut en ajouter, changer leur rôle ou les retirer.
class ProjectMembersSection extends ConsumerWidget {
  const ProjectMembersSection({required this.detail, super.key});

  final ProjectDetail detail;

  String get _projectId => detail.project.id;

  Future<void> _run(BuildContext context, WidgetRef ref, Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      ref.invalidate(projectDetailProvider(_projectId));
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final choice = await showModalBottomSheet<(Member, ProjectRole)>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddMemberSheet(existing: {for (final m in detail.members) m.member.id}),
    );
    if (choice == null || !context.mounted) return;
    await _run(
      context,
      ref,
      () => ref.read(projectRepositoryProvider).setMember(_projectId, choice.$1.id, choice.$2),
    );
  }

  Future<void> _onMenu(
    BuildContext context,
    WidgetRef ref,
    ProjectMember member,
    ProjectRole? role,
  ) async {
    final repository = ref.read(projectRepositoryProvider);
    final userId = member.member.id;
    if (role != null) {
      return _run(context, ref, () => repository.setMember(_projectId, userId, role));
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Retirer du projet ?'),
        content: Text('${member.member.fullName} n\'aura plus accès à ce projet.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Retirer'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await _run(context, ref, () => repository.removeMember(_projectId, userId));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Membres (${detail.members.length})', style: textTheme.titleMedium),
            ),
            if (detail.isLead)
              TextButton.icon(
                onPressed: () => _add(context, ref),
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: const Text('Ajouter'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (final m in detail.members)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: MemberAvatar(member: m.member),
            title: Text(m.member.fullName),
            subtitle: Text(m.member.jobTitle ?? m.member.email),
            trailing: detail.isLead
                ? _MemberMenu(current: m.role, onSelected: (role) => _onMenu(context, ref, m, role))
                : Text(m.role.label, style: textTheme.bodySmall),
          ),
      ],
    );
  }
}

/// Rôle actuel ; le menu propose les autres rôles, ou de retirer le membre (`null`).
/// Les entrées sont des chaînes : une valeur `null` déclencherait `onCanceled`.
class _MemberMenu extends StatelessWidget {
  const _MemberMenu({required this.current, required this.onSelected});

  static const _remove = 'remove';

  final ProjectRole current;
  final void Function(ProjectRole? role) onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Gérer ce membre',
      onSelected: (value) =>
          onSelected(ProjectRole.values.where((role) => role.name == value).firstOrNull),
      itemBuilder: (_) => [
        for (final role in ProjectRole.values)
          if (role != current) PopupMenuItem(value: role.name, child: Text('Passer ${role.label}')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: _remove, child: Text('Retirer du projet')),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(current.label, style: Theme.of(context).textTheme.bodySmall),
          const Icon(Icons.arrow_drop_down),
        ],
      ),
    );
  }
}

class _AddMemberSheet extends ConsumerStatefulWidget {
  const _AddMemberSheet({required this.existing});

  /// Membres déjà dans le projet, exclus de la liste.
  final Set<String> existing;

  @override
  ConsumerState<_AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends ConsumerState<_AddMemberSheet> {
  String _filter = '';
  ProjectRole _role = ProjectRole.contributor;

  bool _matches(Member member) {
    final query = _filter.trim().toLowerCase();
    return query.isEmpty ||
        member.fullName.toLowerCase().contains(query) ||
        member.email.toLowerCase().contains(query);
  }

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(membersProvider);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Ajouter un membre', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              SegmentedButton<ProjectRole>(
                segments: [
                  for (final role in ProjectRole.values)
                    ButtonSegment(value: role, label: Text(role.label)),
                ],
                selected: {_role},
                onSelectionChanged: (selection) => setState(() => _role = selection.first),
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Nom ou e-mail',
                ),
                onChanged: (value) => setState(() => _filter = value),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: members.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (error, _) => Center(
                    child: Text(error is ApiException ? error.message : 'Liste indisponible.'),
                  ),
                  data: (all) {
                    final candidates = [
                      for (final m in all)
                        if (m.isActive && !widget.existing.contains(m.id) && _matches(m)) m,
                    ];
                    if (candidates.isEmpty) {
                      return const Center(child: Text('Aucun membre à ajouter.'));
                    }
                    return ListView.builder(
                      itemCount: candidates.length,
                      itemBuilder: (_, index) {
                        final member = candidates[index];
                        return ListTile(
                          leading: MemberAvatar(member: member),
                          title: Text(member.fullName),
                          subtitle: Text(member.jobTitle ?? member.email),
                          onTap: () => Navigator.pop(context, (member, _role)),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

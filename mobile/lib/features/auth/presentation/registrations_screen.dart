import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_hub/core/network/api_exception.dart';
import 'package:astra_hub/core/utils/formatting.dart';
import 'package:astra_hub/core/widgets/async_value_view.dart';
import 'package:astra_hub/features/auth/data/registration_repository.dart';
import 'package:astra_hub/features/members/data/member.dart';
import 'package:astra_hub/features/members/data/member_repository.dart';
import 'package:astra_hub/features/members/presentation/member_avatar.dart';

/// Demandes d'inscription à valider (administrateurs).
class RegistrationsScreen extends ConsumerWidget {
  const RegistrationsScreen({super.key});

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() action,
    String done,
  ) async {
    try {
      await action();
      ref
        ..invalidate(pendingRegistrationsProvider)
        ..invalidate(membersProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
      }
    } on ApiException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _approve(BuildContext context, WidgetRef ref, PendingRegistration request) async {
    final level = await showDialog<AccessLevel>(
      context: context,
      builder: (_) => _ApproveDialog(request: request),
    );
    if (level == null || !context.mounted) return;
    await _run(
      context,
      ref,
      () => ref.read(registrationRepositoryProvider).approve(request.member.id, level),
      'Compte de ${request.member.fullName} activé (${level.label}).',
    );
  }

  Future<void> _reject(BuildContext context, WidgetRef ref, PendingRegistration request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Refuser la demande ?'),
        content: Text('La demande de ${request.member.fullName} sera supprimée.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Refuser'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await _run(
      context,
      ref,
      () => ref.read(registrationRepositoryProvider).reject(request.member.id),
      'Demande refusée.',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingRegistrationsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Demandes d\'inscription')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(pendingRegistrationsProvider.future),
        child: AsyncValueView(
          value: pending,
          onRetry: () => ref.invalidate(pendingRegistrationsProvider),
          data: (items) => items.isEmpty
              ? const EmptyState(
                  icon: Icons.how_to_reg_outlined,
                  message: 'Aucune demande en attente.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  itemBuilder: (_, index) {
                    final request = items[index];
                    final member = request.member;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                MemberAvatar(member: member, radius: 28),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        member.fullName,
                                        style: Theme.of(context).textTheme.titleMedium,
                                      ),
                                      Text(member.jobTitle ?? ''),
                                      Text(
                                        member.email,
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text('Rôle souhaité : ${request.requestedAccessLevel.label}'),
                            if (member.skills.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [for (final s in member.skills) Chip(label: Text(s))],
                              ),
                            ],
                            if (member.createdAt != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Demande du ${formatDate(member.createdAt!)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: () => _reject(context, ref, request),
                                  child: const Text('Refuser'),
                                ),
                                const SizedBox(width: 8),
                                FilledButton(
                                  onPressed: () => _approve(context, ref, request),
                                  child: const Text('Valider'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _ApproveDialog extends StatefulWidget {
  const _ApproveDialog({required this.request});

  final PendingRegistration request;

  @override
  State<_ApproveDialog> createState() => _ApproveDialogState();
}

class _ApproveDialogState extends State<_ApproveDialog> {
  late AccessLevel _level = widget.request.requestedAccessLevel;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Valider ${widget.request.member.fullName}'),
      content: RadioGroup<AccessLevel>(
        groupValue: _level,
        onChanged: (value) => setState(() => _level = value ?? _level),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final level in AccessLevel.values)
              RadioListTile<AccessLevel>(
                value: level,
                title: Text(level.label),
                subtitle: level == widget.request.requestedAccessLevel
                    ? const Text('Demandé')
                    : null,
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _level),
          child: const Text('Activer le compte'),
        ),
      ],
    );
  }
}

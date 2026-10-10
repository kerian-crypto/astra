import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:astra_hub/core/router/routes.dart';
import 'package:astra_hub/core/theme/astra_theme.dart';
import 'package:astra_hub/features/auth/presentation/auth_controller.dart';
import 'package:astra_hub/features/clients/data/clients.dart';
import 'package:astra_hub/features/clients/data/clients_repository.dart';
import 'package:astra_hub/features/clients/presentation/client_widgets.dart';
import 'package:astra_hub/features/projects/data/project.dart';
import 'package:astra_hub/features/projects/data/project_repository.dart';

/// Section « Espace client » d'un projet : rattachement à une entreprise,
/// ce que voit le client (statut, avancement, résumé) et livrables.
class ProjectClientSection extends ConsumerWidget {
  const ProjectClientSection({required this.detail, super.key});

  final ProjectDetail detail;

  Future<void> _edit(BuildContext context, WidgetRef ref, {required bool canLink}) async {
    final updated = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => _ClientSettingsDialog(project: detail.project, canLink: canLink),
    );
    if (updated == null || updated.isEmpty) return;
    try {
      await ref.read(clientsRepositoryProvider).updateProjectClient(detail.project.id, updated);
      ref.invalidate(projectDetailProvider(detail.project.id));
    } on Exception catch (error) {
      if (context.mounted) showMessage(context, error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = detail.project;
    final member = ref.watch(authControllerProvider).value;
    final canLink = member?.canCreateProjects ?? false;
    final text = Theme.of(context).textTheme;
    if (project.clientCompanyId == null) {
      if (!canLink) return const SizedBox.shrink();
      return Card(
        margin: const EdgeInsets.only(top: 24),
        child: ListTile(
          leading: const Icon(Icons.storefront_outlined),
          title: const Text('Projet interne'),
          subtitle: const Text(
            'Rattachez-le à une entreprise cliente pour l\'ouvrir dans Astra Client.',
          ),
          trailing: OutlinedButton(
            onPressed: () => _edit(context, ref, canLink: true),
            child: const Text('Rattacher'),
          ),
        ),
      );
    }
    final status = ClientProjectStatus.parse(project.clientStatus);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListSectionTitle(
          'Espace client',
          trailing: detail.isLead || canLink
              ? TextButton.icon(
                  onPressed: () => _edit(context, ref, canLink: canLink),
                  icon: const Icon(Icons.tune, size: 18),
                  label: const Text('Réglages'),
                )
              : null,
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Pill(status?.label ?? 'Statut déduit du projet', color: AstraTheme.secondary),
                    Pill(
                      project.progress == null
                          ? 'Avancement calculé'
                          : 'Avancement : ${project.progress} %',
                      color: AstraTheme.accent,
                    ),
                  ],
                ),
                if (project.clientSummary != null) ...[
                  const SizedBox(height: 12),
                  Text('Résumé visible du client', style: text.labelLarge),
                  Text(project.clientSummary!),
                ],
                const SizedBox(height: 8),
                if (canLink)
                  TextButton.icon(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    onPressed: () => context.push(Routes.clientCompany(project.clientCompanyId!)),
                    icon: const Icon(Icons.apartment_outlined, size: 18),
                    label: const Text('Voir l\'entreprise cliente'),
                  ),
              ],
            ),
          ),
        ),
        _DeliverablesList(detail: detail),
      ],
    );
  }
}

class _DeliverablesList extends ConsumerWidget {
  const _DeliverablesList({required this.detail});

  final ProjectDetail detail;

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final title = TextEditingController();
    final description = TextEditingController();
    var requiresValidation = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Nouveau livrable'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                decoration: const InputDecoration(labelText: 'Titre'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: description,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Description (visible du client)'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: requiresValidation,
                title: const Text('Validation du client requise'),
                onChanged: (value) => setState(() => requiresValidation = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Créer')),
          ],
        ),
      ),
    );
    if (ok != true || title.text.trim().isEmpty) return;
    try {
      final deliverable = await ref
          .read(clientsRepositoryProvider)
          .createDeliverable(
            detail.project.id,
            title: title.text,
            description: description.text,
            requiresValidation: requiresValidation,
          );
      ref.invalidate(projectDeliverablesProvider(detail.project.id));
      if (context.mounted) await context.push(Routes.deliverable(deliverable.id));
    } on Exception catch (error) {
      if (context.mounted) showMessage(context, error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deliverables = ref.watch(projectDeliverablesProvider(detail.project.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListSectionTitle(
          'Livrables',
          trailing: detail.isLead
              ? TextButton.icon(
                  onPressed: () => _create(context, ref),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Livrable'),
                )
              : null,
        ),
        deliverables.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => Text('$error'),
          data: (list) => list.isEmpty
              ? const Text('Aucun livrable. Créez-en un pour le transmettre au client.')
              : Column(
                  children: [
                    for (final d in list)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Icon(d.status.icon, color: deliverableColor(d.status)),
                          title: Text(d.title),
                          subtitle: Text(
                            d.current == null
                                ? 'Pas encore publié'
                                : 'Version ${d.current!.number}',
                          ),
                          trailing: Pill(d.status.label, color: deliverableColor(d.status)),
                          onTap: () => context.push(Routes.deliverable(d.id)),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _ClientSettingsDialog extends ConsumerStatefulWidget {
  const _ClientSettingsDialog({required this.project, required this.canLink});

  final Project project;
  final bool canLink;

  @override
  ConsumerState<_ClientSettingsDialog> createState() => _ClientSettingsDialogState();
}

class _ClientSettingsDialogState extends ConsumerState<_ClientSettingsDialog> {
  late String? _companyId = widget.project.clientCompanyId;
  late ClientProjectStatus? _status = ClientProjectStatus.parse(widget.project.clientStatus);
  late double? _progress = widget.project.progress?.toDouble();
  late final _summary = TextEditingController(text: widget.project.clientSummary ?? '');

  @override
  void dispose() {
    _summary.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final companies = widget.canLink
        ? ref.watch(clientCompaniesProvider).value ?? const []
        : const <ClientCompany>[];
    return AlertDialog(
      title: const Text('Espace client du projet'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.canLink)
                DropdownButtonFormField<String?>(
                  isExpanded: true,
                  initialValue: _companyId,
                  decoration: const InputDecoration(labelText: 'Entreprise cliente'),
                  items: [
                    const DropdownMenuItem(child: Text('Aucune (projet interne)')),
                    for (final c in companies) DropdownMenuItem(value: c.id, child: Text(c.name)),
                  ],
                  onChanged: (value) => setState(() => _companyId = value),
                ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ClientProjectStatus?>(
                isExpanded: true,
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Statut affiché au client'),
                items: [
                  const DropdownMenuItem(child: Text('Déduit du statut interne')),
                  for (final s in ClientProjectStatus.values)
                    DropdownMenuItem(value: s, child: Text(s.label)),
                ],
                onChanged: (value) => setState(() => _status = value),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _progress == null,
                title: const Text('Avancement calculé depuis les tâches'),
                onChanged: (auto) => setState(() => _progress = auto ? null : 50),
              ),
              if (_progress != null)
                Slider(
                  value: _progress!,
                  max: 100,
                  divisions: 20,
                  label: '${_progress!.round()} %',
                  onChanged: (value) => setState(() => _progress = value),
                ),
              TextField(
                controller: _summary,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(labelText: 'Résumé visible du client'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          onPressed: () {
            final p = widget.project;
            final summary = _summary.text.trim().isEmpty ? null : _summary.text.trim();
            Navigator.pop(context, <String, Object?>{
              if (widget.canLink && _companyId != p.clientCompanyId)
                'client_company_id': _companyId,
              if (_status?.value != p.clientStatus) 'client_status': _status?.value,
              if (_progress?.round() != p.progress) 'progress': _progress?.round(),
              if (summary != p.clientSummary) 'client_summary': summary,
            });
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

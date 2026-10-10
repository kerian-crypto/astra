import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_hub/core/layout/responsive.dart';
import 'package:astra_hub/core/theme/astra_theme.dart';
import 'package:astra_hub/core/utils/formatting.dart';
import 'package:astra_hub/core/widgets/async_value_view.dart';
import 'package:astra_hub/features/clients/data/clients.dart';
import 'package:astra_hub/features/clients/data/clients_repository.dart';
import 'package:astra_hub/features/clients/presentation/client_widgets.dart';

/// Livrable côté Astra : versions publiées au client et ses validations.
class DeliverableScreen extends ConsumerWidget {
  const DeliverableScreen({required this.deliverableId, super.key});

  final String deliverableId;

  Future<void> _publish(BuildContext context, WidgetRef ref, Deliverable d) async {
    final notes = TextEditingController();
    final link = TextEditingController();
    LocalFile? file;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Publier la version ${(d.current?.number ?? 0) + 1}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final files = await FilePicker.pickFiles();
                  final picked = files.firstOrNull;
                  if (picked?.path != null) {
                    setState(() => file = (path: picked!.path!, name: picked.name));
                  }
                },
                icon: const Icon(Icons.upload_file),
                label: Text(file?.name ?? 'Choisir le fichier'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: link,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'Ou lien https (facultatif)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notes,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Notes pour le client'),
              ),
              const SizedBox(height: 8),
              Text(
                d.requiresValidation
                    ? 'Le client sera notifié et invité à valider.'
                    : 'Le client sera notifié de la nouvelle version.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Publier'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await ref
          .read(clientsRepositoryProvider)
          .publishVersion(d.id, notes: notes.text, linkUrl: link.text, file: file);
      ref
        ..invalidate(hubDeliverableProvider(deliverableId))
        ..invalidate(projectDeliverablesProvider(d.projectId));
      if (context.mounted) showMessage(context, 'Version publiée au client.');
    } on Exception catch (error) {
      if (context.mounted) showMessage(context, error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deliverable = ref.watch(hubDeliverableProvider(deliverableId));
    final gutter = Breakpoints.gutter(context);
    return Scaffold(
      appBar: AppBar(title: Text(deliverable.value?.title ?? 'Livrable')),
      floatingActionButton: deliverable.hasValue
          ? FloatingActionButton.extended(
              onPressed: () => _publish(context, ref, deliverable.requireValue),
              icon: const Icon(Icons.publish),
              label: const Text('Publier une version'),
            )
          : null,
      body: AsyncValueView(
        value: deliverable,
        onRetry: () => ref.invalidate(hubDeliverableProvider(deliverableId)),
        data: (d) => ResponsiveCenter(
          maxWidth: Breakpoints.readingMaxWidth,
          child: ListView(
            padding: EdgeInsets.fromLTRB(gutter, gutter, gutter, 96),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Pill(d.status.label, color: deliverableColor(d.status), icon: d.status.icon),
                      const SizedBox(height: 8),
                      Text(d.title, style: Theme.of(context).textTheme.titleLarge),
                      Text(d.projectName),
                      if (d.description != null) ...[
                        const SizedBox(height: 8),
                        Text(d.description!),
                      ],
                    ],
                  ),
                ),
              ),
              if (d.reviews.isNotEmpty) ...[
                const ListSectionTitle('Retours du client'),
                for (final r in d.reviews)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(
                        r.approved ? Icons.verified_outlined : Icons.edit_note,
                        color: r.approved ? AstraTheme.accent : AstraTheme.warning,
                      ),
                      title: Text(
                        '${r.approved ? 'Approuvé' : 'Modification demandée'} · V${r.versionNumber}',
                      ),
                      subtitle: Text(
                        [
                          '${r.reviewerName} · ${formatDateTime(r.createdAt)}',
                          if (r.reason != null) 'Motif : ${r.reason}',
                          ?r.comment,
                        ].join('\n'),
                      ),
                      isThreeLine: r.reason != null || r.comment != null,
                      trailing: r.file == null
                          ? null
                          : IconButton(
                              tooltip: r.file!.name,
                              icon: const Icon(Icons.attach_file),
                              onPressed: () => openClientFile(
                                context,
                                ref,
                                '/deliverables/${d.id}/reviews/${r.id}/download',
                                r.file!.name,
                              ),
                            ),
                    ),
                  ),
              ],
              ListSectionTitle('Versions (${d.versions.length})'),
              if (d.versions.isEmpty)
                const Text('Aucune version publiée : le client ne voit pas encore ce livrable.'),
              for (final v in d.versions)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text('Version ${v.number}'),
                    subtitle: Text(
                      [
                        '${formatDateTime(v.publishedAt)}${v.publishedBy != null ? ' · ${v.publishedBy}' : ''}',
                        ?v.notes,
                        ?v.linkUrl,
                      ].join('\n'),
                    ),
                    trailing: v.file == null
                        ? null
                        : IconButton(
                            tooltip: v.file!.name,
                            icon: const Icon(Icons.download),
                            onPressed: () => openClientFile(
                              context,
                              ref,
                              '/deliverables/${d.id}/versions/${v.id}/download',
                              v.file!.name,
                            ),
                          ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

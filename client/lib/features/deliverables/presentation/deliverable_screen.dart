import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_client/core/layout/page_frame.dart';
import 'package:astra_client/core/theme/client_theme.dart';
import 'package:astra_client/core/utils/files.dart';
import 'package:astra_client/core/utils/formatting.dart';
import 'package:astra_client/core/widgets/state_views.dart';
import 'package:astra_client/core/widgets/ui.dart';
import 'package:astra_client/features/dashboard/data/dashboard.dart';
import 'package:astra_client/features/deliverables/data/deliverable.dart';
import 'package:astra_client/features/deliverables/data/deliverable_repository.dart';
import 'package:astra_client/features/deliverables/presentation/review_sheet.dart';
import 'package:astra_client/features/documents/presentation/document_tile.dart';
import 'package:astra_client/features/projects/data/project_repository.dart';

class DeliverableScreen extends ConsumerWidget {
  const DeliverableScreen({required this.deliverableId, super.key});

  final String deliverableId;

  Future<void> _review(
    BuildContext context,
    WidgetRef ref,
    DeliverableDetail d,
    ReviewAction action,
  ) async {
    final done = await showReviewSheet(context, deliverable: d, action: action);
    if (done != true || !context.mounted) return;
    ref
      ..invalidate(deliverableProvider(deliverableId))
      ..invalidate(dashboardProvider)
      ..invalidate(projectProvider(d.projectId))
      ..invalidate(deliverablesProvider((projectId: d.projectId, pendingOnly: false)));
    showSuccess(
      context,
      action == ReviewAction.approve
          ? 'Merci ! Votre validation a été transmise à Astra.'
          : 'Votre demande de modification a été transmise à Astra.',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deliverable = ref.watch(deliverableProvider(deliverableId));
    return Scaffold(
      appBar: AppBar(title: const Text('Livrable')),
      body: AsyncView(
        value: deliverable,
        onRetry: () => ref.invalidate(deliverableProvider(deliverableId)),
        builder: (d) => FramedListView(
          maxWidth: 960,
          onRefresh: () => ref.refresh(deliverableProvider(deliverableId).future),
          children: [
            _Summary(deliverable: d),
            if (d.canReview) ...[
              const SizedBox(height: Space.lg),
              _ReviewPanel(
                onApprove: () => _review(context, ref, d, ReviewAction.approve),
                onRequestChanges: () => _review(context, ref, d, ReviewAction.requestChanges),
              ),
            ],
            if (d.versions.length > 1) ...[
              const SectionHeader('Versions précédentes'),
              for (final version in d.versions.skip(1)) ...[
                _VersionTile(deliverableId: d.id, version: version),
                const SizedBox(height: Space.sm),
              ],
            ],
            if (d.reviews.isNotEmpty) ...[
              const SectionHeader('Historique des validations'),
              for (final review in d.reviews) ...[
                _ReviewTile(deliverableId: d.id, review: review),
                const SizedBox(height: Space.sm),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _Summary extends ConsumerWidget {
  const _Summary({required this.deliverable});

  final DeliverableDetail deliverable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final version = deliverable.currentVersion;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StatusPill(label: deliverable.status.label, tone: deliverable.status.tone),
            const SizedBox(height: Space.md),
            Text(deliverable.title, style: text.headlineSmall),
            Text(
              deliverable.projectName,
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (deliverable.description != null) ...[
              const SizedBox(height: Space.lg),
              Text(deliverable.description!),
            ],
            if (version != null) ...[
              const SizedBox(height: Space.xl),
              const Divider(),
              const SizedBox(height: Space.lg),
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  StatusPill(label: 'Version ${version.number}', tone: Tone.brand),
                  Text('publiée ${formatRelative(version.publishedAt)}', style: text.bodySmall),
                ],
              ),
              if (version.notes != null) ...[
                const SizedBox(height: Space.md),
                Text(version.notes!, style: text.bodyMedium),
              ],
              const SizedBox(height: Space.lg),
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  if (version.file != null)
                    FilledButton.tonalIcon(
                      onPressed: () => unawaited(
                        openApiFile(
                          context,
                          ref,
                          'client/deliverables/${deliverable.id}/versions/${version.id}/download',
                          version.file!.name,
                        ),
                      ),
                      icon: Icon(iconForContentType(version.file!.contentType)),
                      label: Text('Ouvrir · ${formatFileSize(version.file!.sizeBytes)}'),
                    ),
                  if (version.linkUrl != null)
                    OutlinedButton.icon(
                      onPressed: () async {
                        try {
                          await ref.read(fileServiceProvider).openLink(version.linkUrl!);
                        } on Exception catch (error) {
                          if (context.mounted) showError(context, error);
                        }
                      },
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: const Text('Voir en ligne'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReviewPanel extends StatelessWidget {
  const _ReviewPanel({required this.onApprove, required this.onRequestChanges});

  final VoidCallback onApprove;
  final VoidCallback onRequestChanges;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final buttons = [
      FilledButton.icon(
        onPressed: onApprove,
        icon: const Icon(Icons.check_rounded),
        label: const Text('Approuver'),
      ),
      OutlinedButton.icon(
        onPressed: onRequestChanges,
        icon: const Icon(Icons.edit_note_rounded),
        label: const Text('Demander une modification'),
      ),
    ];
    return Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: Tone.warning.background(scheme),
        borderRadius: BorderRadius.circular(ClientTheme.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.fact_check_outlined, color: Tone.warning.foreground(scheme)),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  'Votre validation est attendue',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(color: Tone.warning.foreground(scheme)),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth < 480
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      buttons[0],
                      const SizedBox(height: Space.sm),
                      buttons[1],
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: buttons[0]),
                      const SizedBox(width: Space.md),
                      Expanded(child: buttons[1]),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _VersionTile extends ConsumerWidget {
  const _VersionTile({required this.deliverableId, required this.version});

  final String deliverableId;
  final DeliverableVersion version;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final file = version.file;
    return Card(
      child: ListTile(
        leading: const ToneIcon(Icons.history_rounded, tone: Tone.neutral),
        title: Text('Version ${version.number}'),
        subtitle: Text(
          version.notes ?? formatDate(version.publishedAt),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: file == null ? null : const Icon(Icons.download_rounded),
        onTap: file == null
            ? null
            : () => unawaited(
                openApiFile(
                  context,
                  ref,
                  'client/deliverables/$deliverableId/versions/${version.id}/download',
                  file.name,
                ),
              ),
      ),
    );
  }
}

class _ReviewTile extends ConsumerWidget {
  const _ReviewTile({required this.deliverableId, required this.review});

  final String deliverableId;
  final DeliverableReview review;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final tone = review.approved ? Tone.success : Tone.info;
    final file = review.file;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ToneIcon(review.approved ? Icons.check_rounded : Icons.edit_note_rounded, tone: tone),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${review.approved ? 'Approuvé' : 'Modification demandée'} · V${review.versionNumber}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    '${review.reviewerName} · ${formatDateTime(review.createdAt)}',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  if (review.reason != null) ...[
                    const SizedBox(height: Space.xs),
                    Text(
                      'Motif : ${review.reason}',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ],
                  if (review.comment != null) Text(review.comment!),
                  if (file != null)
                    TextButton.icon(
                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      onPressed: () => unawaited(
                        openApiFile(
                          context,
                          ref,
                          'client/deliverables/$deliverableId/reviews/${review.id}/download',
                          file.name,
                        ),
                      ),
                      icon: const Icon(Icons.attach_file_rounded, size: 18),
                      label: Text(file.name),
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

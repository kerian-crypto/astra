import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_client/core/theme/client_theme.dart';
import 'package:astra_client/core/utils/files.dart';
import 'package:astra_client/core/utils/formatting.dart';
import 'package:astra_client/core/widgets/state_views.dart';
import 'package:astra_client/core/widgets/ui.dart';
import 'package:astra_client/features/documents/data/document.dart';

IconData iconForContentType(String contentType) {
  if (contentType.startsWith('image/')) return Icons.image_outlined;
  if (contentType.contains('pdf')) return Icons.picture_as_pdf_outlined;
  if (contentType.contains('sheet') || contentType.contains('csv')) {
    return Icons.table_chart_outlined;
  }
  if (contentType.contains('presentation')) return Icons.slideshow_outlined;
  if (contentType.startsWith('video/')) return Icons.movie_outlined;
  return Icons.description_outlined;
}

/// Télécharge puis ouvre un fichier de l'API, avec retour visuel.
Future<void> openApiFile(BuildContext context, WidgetRef ref, String path, String filename) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    SnackBar(content: Text('Ouverture de « $filename »…'), duration: const Duration(seconds: 2)),
  );
  try {
    await ref.read(fileServiceProvider).openFromApi(path, filename);
  } on Exception catch (error) {
    if (context.mounted) showError(context, error);
  }
}

class DocumentTile extends ConsumerWidget {
  const DocumentTile({required this.document, this.onShowVersions, super.key});

  final ClientDocument document;
  final VoidCallback? onShowVersions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final meta = [
      document.category.label,
      if (document.projectName != null) document.projectName!,
      formatFileSize(document.sizeBytes),
      formatDateShort(document.createdAt),
    ].join(' · ');
    return Card(
      child: InkWell(
        onTap: () => unawaited(openApiFile(context, ref, document.downloadPath, document.filename)),
        child: Padding(
          padding: const EdgeInsets.all(Space.md),
          child: Row(
            children: [
              ToneIcon(iconForContentType(document.contentType), tone: Tone.info, size: 44),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            document.title,
                            style: Theme.of(context).textTheme.titleSmall,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (document.version > 1) ...[
                          const SizedBox(width: Space.sm),
                          StatusPill(label: 'V${document.version}', tone: Tone.brand),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (document.hasHistory && onShowVersions != null)
                IconButton(
                  tooltip: 'Versions précédentes',
                  icon: const Icon(Icons.history_rounded),
                  onPressed: onShowVersions,
                ),
              Icon(Icons.download_rounded, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

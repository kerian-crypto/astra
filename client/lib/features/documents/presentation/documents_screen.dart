import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_client/core/layout/page_frame.dart';
import 'package:astra_client/core/theme/client_theme.dart';
import 'package:astra_client/core/widgets/state_views.dart';
import 'package:astra_client/core/widgets/ui.dart';
import 'package:astra_client/features/documents/data/document.dart';
import 'package:astra_client/features/documents/data/document_repository.dart';
import 'package:astra_client/features/documents/presentation/document_tile.dart';

/// Espace documentaire (§21) : documents partagés, livrables, contrats et
/// factures, filtrables par catégorie.
class DocumentsScreen extends ConsumerStatefulWidget {
  const DocumentsScreen({super.key});

  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen> {
  DocumentCategory? _category;
  String _query = '';

  ({DocumentCategory? category, String? projectId}) get _filter =>
      (category: _category, projectId: null);

  void _showVersions(ClientDocument document) {
    showModalBottomSheet<void>(
      context: context,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => _VersionsSheet(document: document),
    );
  }

  @override
  Widget build(BuildContext context) {
    final documents = ref.watch(documentsProvider(_filter));
    return Scaffold(
      appBar: AppBar(title: const Text('Documents')),
      body: Column(
        children: [
          PageFrame(
            child: Column(
              children: [
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Rechercher un document',
                    prefixIcon: Icon(Icons.search_rounded),
                    isDense: true,
                  ),
                  onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
                ),
                const SizedBox(height: Space.md),
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _chip(null, 'Tous', Icons.apps_rounded),
                      for (final category in DocumentCategory.values)
                        _chip(category, category.label, category.icon),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.sm),
          Expanded(
            child: AsyncView(
              value: documents,
              onRetry: () => ref.invalidate(documentsProvider(_filter)),
              builder: (list) {
                final shown = _query.isEmpty
                    ? list
                    : list
                          .where(
                            (d) =>
                                d.title.toLowerCase().contains(_query) ||
                                (d.projectName ?? '').toLowerCase().contains(_query),
                          )
                          .toList();
                if (shown.isEmpty) {
                  return const StateMessage(
                    icon: Icons.folder_open_outlined,
                    title: 'Aucun document',
                    message: 'Les documents partagés par Astra apparaîtront ici.',
                  );
                }
                return FramedListView(
                  onRefresh: () => ref.refresh(documentsProvider(_filter).future),
                  children: [
                    ResponsiveGrid(
                      minItemWidth: 420,
                      spacing: Space.sm,
                      children: [
                        for (final document in shown)
                          DocumentTile(
                            document: document,
                            onShowVersions: () => _showVersions(document),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(DocumentCategory? category, String label, IconData icon) => Padding(
    padding: const EdgeInsets.only(right: Space.sm),
    child: FilterChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      selected: _category == category,
      showCheckmark: false,
      onSelected: (_) => setState(() => _category = category),
    ),
  );
}

class _VersionsSheet extends ConsumerWidget {
  const _VersionsSheet({required this.document});

  final ClientDocument document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final versions = ref.watch(documentVersionsProvider(document.id));
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Versions de « ${document.title} »', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: Space.lg),
          Flexible(
            child: AsyncView(
              value: versions,
              compact: true,
              builder: (list) => ListView(
                shrinkWrap: true,
                children: [
                  for (final (i, version) in list.indexed) ...[
                    Row(
                      children: [
                        Expanded(child: DocumentTile(document: version)),
                        if (i == 0) ...[
                          const SizedBox(width: Space.sm),
                          const StatusPill(label: 'Actuelle', tone: Tone.success),
                        ],
                      ],
                    ),
                    const SizedBox(height: Space.sm),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

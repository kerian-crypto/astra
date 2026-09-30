import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';

import 'package:astra_hub/core/network/api_exception.dart';
import 'package:astra_hub/core/utils/formatting.dart';
import 'package:astra_hub/core/widgets/async_value_view.dart';
import 'package:astra_hub/features/auth/presentation/auth_controller.dart';
import 'package:astra_hub/features/knowledge/data/knowledge.dart';
import 'package:astra_hub/features/knowledge/data/knowledge_repository.dart';

/// Documents généraux d'Astra (guides, retours d'expérience…).
class DocumentsScreen extends ConsumerWidget {
  const DocumentsScreen({required this.projectId, super.key});

  final String? projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canUpload = ref.watch(authControllerProvider).value?.canCreateProjects ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Documents d\'Astra')),
      body: DocumentsList(projectId: projectId, canUpload: canUpload),
    );
  }
}

/// Liste de documents d'un projet (ou généraux si `projectId` est nul).
class DocumentsList extends ConsumerStatefulWidget {
  const DocumentsList({required this.projectId, required this.canUpload, super.key});

  final String? projectId;
  final bool canUpload;

  @override
  ConsumerState<DocumentsList> createState() => _DocumentsListState();
}

class _DocumentsListState extends ConsumerState<DocumentsList> {
  /// Formats acceptés par le serveur (vérifiés aussi côté serveur).
  static const _acceptedExtensions = [
    'pdf', 'txt', 'md', 'csv', 'png', 'jpg', 'jpeg', 'docx', 'xlsx', 'pptx', 'odt', //
  ];

  bool _isBusy = false;

  void _show(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _upload() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: _acceptedExtensions,
    );
    final file = files.firstOrNull;
    if (file == null || file.path == null || !mounted) return;
    final details = await showDialog<(String, DocumentKind)>(
      context: context,
      builder: (_) => _DocumentDetailsDialog(filename: file.name),
    );
    if (details == null) return;
    setState(() => _isBusy = true);
    try {
      await ref
          .read(knowledgeRepositoryProvider)
          .upload(
            projectId: widget.projectId,
            title: details.$1,
            kind: details.$2,
            filePath: file.path!,
            filename: file.name,
          );
      ref.invalidate(documentsProvider(widget.projectId));
      _show('Document ajouté.');
    } on ApiException catch (error) {
      _show(error.message);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _open(AstraDocument document) async {
    setState(() => _isBusy = true);
    try {
      final path = await ref.read(knowledgeRepositoryProvider).download(document);
      final result = await OpenFilex.open(path);
      if (result.type != ResultType.done) _show('Aucune application pour ouvrir ce fichier.');
    } on ApiException catch (error) {
      _show(error.message);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final documents = ref.watch(documentsProvider(widget.projectId));
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: () => ref.refresh(documentsProvider(widget.projectId).future),
          child: AsyncValueView(
            value: documents,
            onRetry: () => ref.invalidate(documentsProvider(widget.projectId)),
            data: (items) => items.isEmpty
                ? const EmptyState(icon: Icons.description_outlined, message: 'Aucun document.')
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    itemCount: items.length,
                    itemBuilder: (_, index) {
                      final doc = items[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.description_outlined),
                        title: Text(doc.title),
                        subtitle: Text(
                          '${doc.kind.label} · ${doc.filename} · ${doc.readableSize}\n'
                          '${doc.uploadedBy?.fullName ?? ''} · ${formatDate(doc.createdAt)}',
                        ),
                        isThreeLine: true,
                        onTap: _isBusy ? null : () => _open(doc),
                      );
                    },
                  ),
          ),
        ),
        if (widget.canUpload)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.small(
              heroTag: 'upload-${widget.projectId}',
              tooltip: 'Ajouter un document',
              onPressed: _isBusy ? null : _upload,
              child: const Icon(Icons.upload_file),
            ),
          ),
        if (_isBusy) const LinearProgressIndicator(),
      ],
    );
  }
}

class _DocumentDetailsDialog extends StatefulWidget {
  const _DocumentDetailsDialog({required this.filename});

  final String filename;

  @override
  State<_DocumentDetailsDialog> createState() => _DocumentDetailsDialogState();
}

class _DocumentDetailsDialogState extends State<_DocumentDetailsDialog> {
  late final _title = TextEditingController(
    text: widget.filename.replaceAll(RegExp(r'\.[^.]+$'), ''),
  );
  DocumentKind _kind = DocumentKind.other;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nouveau document'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Titre'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<DocumentKind>(
            initialValue: _kind,
            decoration: const InputDecoration(labelText: 'Type'),
            items: [
              for (final k in DocumentKind.values) DropdownMenuItem(value: k, child: Text(k.label)),
            ],
            onChanged: (value) => setState(() => _kind = value ?? _kind),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          onPressed: _title.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, (_title.text.trim(), _kind)),
          child: const Text('Envoyer'),
        ),
      ],
    );
  }
}

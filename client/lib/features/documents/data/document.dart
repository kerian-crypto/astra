import 'package:flutter/material.dart';

import 'package:astra_client/core/utils/json.dart';

enum DocumentCategory {
  contract('contract', 'Contrats', Icons.handshake_outlined),
  invoice('invoice', 'Factures', Icons.receipt_long_outlined),
  specification('specification', 'Cahier des charges', Icons.assignment_outlined),
  deliverable('deliverable', 'Livrables', Icons.inventory_2_outlined),
  report('report', 'Rapports', Icons.insert_chart_outlined),
  administrative('administrative', 'Administratif', Icons.folder_shared_outlined),
  other('other', 'Autres', Icons.description_outlined);

  const DocumentCategory(this.value, this.label, this.icon);
  final String value;
  final String label;
  final IconData icon;

  static DocumentCategory parse(Object? value) =>
      values.where((c) => c.value == value).firstOrNull ?? other;
}

class ClientDocument {
  const ClientDocument({
    required this.id,
    required this.source,
    required this.category,
    required this.title,
    required this.filename,
    required this.contentType,
    required this.sizeBytes,
    required this.version,
    required this.createdAt,
    required this.downloadPath,
    this.projectId,
    this.projectName,
  });

  factory ClientDocument.fromJson(Json json) => ClientDocument(
    id: json['id'] as String,
    source: json['source'] as String,
    category: DocumentCategory.parse(json['category']),
    title: json['title'] as String,
    filename: json['filename'] as String,
    contentType: json['content_type'] as String,
    sizeBytes: json['size_bytes'] as int? ?? 0,
    version: json['version'] as int? ?? 1,
    projectId: json['project_id'] as String?,
    projectName: json['project_name'] as String?,
    createdAt: DateTime.parse(json['created_at'] as String),
    downloadPath: json['download_path'] as String,
  );

  final String id;
  final String source;
  final DocumentCategory category;
  final String title;
  final String filename;
  final String contentType;
  final int sizeBytes;
  final int version;
  final String? projectId;
  final String? projectName;
  final DateTime createdAt;
  final String downloadPath;

  /// Seuls les documents partagés ont un historique de versions.
  bool get hasHistory => source == 'document' && version > 1;
}

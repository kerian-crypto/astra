import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:astra_client/core/network/api_client.dart';
import 'package:astra_client/core/network/api_exception.dart';

final fileServiceProvider = Provider<FileService>((ref) => FileService(ref.watch(dioProvider)));

/// Téléchargement contrôlé des fichiers (§48, §56) : toujours via l'API
/// authentifiée, jamais par une URL publique ; ouvert avec l'application du
/// téléphone. Les fichiers temporaires sont effacés à la déconnexion.
class FileService {
  FileService(this._dio);

  final Dio _dio;

  static Future<Directory> _folder() async {
    final temp = await getTemporaryDirectory();
    return Directory('${temp.path}/astra_downloads').create(recursive: true);
  }

  /// [apiPath] : chemin relatif à l'API (ex. `client/documents/<id>/download`).
  Future<void> openFromApi(String apiPath, String filename) async {
    final folder = await _folder();
    final safeName = filename.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final target = '${folder.path}/$safeName';
    await guardApi(() => _dio.download('/${apiPath.replaceFirst(RegExp('^/'), '')}', target));
    final result = await OpenFilex.open(target);
    if (result.type != ResultType.done) {
      throw ApiException('Aucune application ne peut ouvrir « $filename » sur ce téléphone.');
    }
  }

  /// Ouvre un lien https (livrable en ligne) dans le navigateur.
  Future<void> openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') {
      throw const ApiException('Lien non valide.');
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw const ApiException('Impossible d\'ouvrir ce lien.');
    }
  }

  static Future<void> clearDownloads() async {
    try {
      final folder = await _folder();
      await folder.delete(recursive: true);
    } on Exception {
      // Rien à effacer (ou stockage indisponible).
    }
  }
}

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'package:astra_hub/core/config/app_config.dart';

/// Identifiant de l'application côté serveur (`/releases/<app>/latest`).
const updateAppId = 'hub';

/// Nouvelle version publiée sur le serveur (infra/aws/publish-release.sh).
class AppUpdate {
  const AppUpdate({
    required this.version,
    required this.buildNumber,
    required this.minBuildNumber,
    required this.sizeBytes,
    required this.sha256,
    required this.downloadPath,
    required this.currentBuild,
    this.notes,
  });

  factory AppUpdate.fromJson(Map<String, dynamic> json, int currentBuild) => AppUpdate(
    version: json['version'] as String,
    buildNumber: json['build_number'] as int,
    minBuildNumber: json['min_build_number'] as int? ?? 1,
    notes: json['notes'] as String?,
    sizeBytes: json['size_bytes'] as int,
    sha256: json['sha256'] as String,
    downloadPath: json['download_path'] as String,
    currentBuild: currentBuild,
  );

  final String version;
  final int buildNumber;
  final int minBuildNumber;
  final String? notes;
  final int sizeBytes;
  final String sha256;
  final String downloadPath;
  final int currentBuild;

  bool get isAvailable => buildNumber > currentBuild;

  /// Version installée trop ancienne : la mise à jour n'est pas facultative.
  bool get isMandatory => currentBuild < minBuildNumber;
}

/// Vérifie, télécharge et lance l'installation des mises à jour Android
/// distribuées par le serveur Astra (hors Play Store).
class UpdateService {
  UpdateService({Dio? dio})
    : _dio =
          dio ??
          Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl, connectTimeout: AppConfig.connectTimeout));

  final Dio _dio;

  /// Nul si l'app est à jour, sans réseau, ou si rien n'est publié.
  Future<AppUpdate?> check() async {
    if (!Platform.isAndroid) return null;
    try {
      final info = await PackageInfo.fromPlatform();
      final current = int.tryParse(info.buildNumber) ?? 0;
      final response = await _dio.get<Map<String, dynamic>>('/releases/$updateAppId/latest');
      final update = AppUpdate.fromJson(response.data!, current);
      return update.isAvailable ? update : null;
    } on Object catch (error) {
      debugPrint('Vérification de mise à jour impossible : $error');
      return null;
    }
  }

  /// Télécharge l'APK (progression de 0 à 1), vérifie son empreinte SHA-256
  /// puis ouvre l'installeur Android : l'utilisateur confirme l'installation.
  Future<void> downloadAndInstall(AppUpdate update, {ValueChanged<double>? onProgress}) async {
    final folder = await getTemporaryDirectory();
    final file = File('${folder.path}/astra-$updateAppId-${update.buildNumber}.apk');
    await _dio.download(
      '/${update.downloadPath}',
      file.path,
      onReceiveProgress: (received, total) {
        final size = total > 0 ? total : update.sizeBytes;
        onProgress?.call((received / size).clamp(0, 1).toDouble());
      },
    );
    final digest = sha256.convert(await file.readAsBytes()).toString();
    if (digest != update.sha256) {
      await file.delete();
      throw const UpdateException('Le fichier téléchargé est incomplet ou altéré. Réessayez.');
    }
    final result = await OpenFilex.open(file.path, type: 'application/vnd.android.package-archive');
    if (result.type != ResultType.done) {
      throw UpdateException('Installation impossible : ${result.message}');
    }
  }
}

class UpdateException implements Exception {
  const UpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Vérifie une fois au démarrage (builds release Android uniquement) et
/// propose la mise à jour. Les tests et le développement ne sont pas concernés.
class UpdateGate extends StatefulWidget {
  const UpdateGate({required this.navigatorKey, required this.child, this.service, super.key});

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;
  final UpdateService? service;

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  late final UpdateService _service = widget.service ?? UpdateService();

  @override
  void initState() {
    super.initState();
    if (kReleaseMode || widget.service != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    }
  }

  Future<void> _check() async {
    final update = await _service.check();
    final context = widget.navigatorKey.currentContext;
    if (update == null || context == null || !context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: !update.isMandatory,
      builder: (_) => UpdateDialog(update: update, service: _service),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class UpdateDialog extends StatefulWidget {
  const UpdateDialog({required this.update, required this.service, super.key});

  final AppUpdate update;
  final UpdateService service;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  double? _progress;
  String? _error;

  Future<void> _install() async {
    setState(() {
      _progress = 0;
      _error = null;
    });
    try {
      await widget.service.downloadAndInstall(
        widget.update,
        onProgress: (value) => mounted ? setState(() => _progress = value) : null,
      );
      if (mounted && !widget.update.isMandatory) Navigator.of(context).pop();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _progress = null;
          _error = error is UpdateException
              ? error.message
              : 'Téléchargement impossible. Vérifiez votre connexion.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final update = widget.update;
    final downloading = _progress != null;
    final megabytes = (update.sizeBytes / (1024 * 1024)).toStringAsFixed(0);
    return PopScope(
      canPop: !update.isMandatory && !downloading,
      child: AlertDialog(
        icon: const Icon(Icons.system_update_rounded, size: 36),
        title: Text(update.isMandatory ? 'Mise à jour requise' : 'Nouvelle version disponible'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Version ${update.version} · $megabytes Mo'),
            if (update.notes != null) ...[const SizedBox(height: 12), Text(update.notes!)],
            if (update.isMandatory) ...[
              const SizedBox(height: 12),
              const Text('Cette version est nécessaire pour continuer à utiliser l\'application.'),
            ],
            if (downloading) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: _progress == 0 ? null : _progress),
              const SizedBox(height: 4),
              Text('${((_progress ?? 0) * 100).round()} %'),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
        actions: [
          if (!update.isMandatory)
            TextButton(
              onPressed: downloading ? null : () => Navigator.of(context).pop(),
              child: const Text('Plus tard'),
            ),
          FilledButton(
            onPressed: downloading ? null : _install,
            child: Text(_error == null ? 'Mettre à jour' : 'Réessayer'),
          ),
        ],
      ),
    );
  }
}

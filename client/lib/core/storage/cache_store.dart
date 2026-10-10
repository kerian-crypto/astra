import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Cache local des données déjà consultées, pour l'affichage hors ligne (§55).
///
/// Fichiers JSON dans le répertoire privé de l'application, effacés à la
/// déconnexion (§57). Les opérations sensibles ne passent jamais par ici.
abstract interface class CacheStore {
  Future<Object?> read(String key);
  Future<void> write(String key, Object? data);
  Future<void> clear();
}

class FileCacheStore implements CacheStore {
  FileCacheStore({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;

  Future<File> _file(String key) async {
    final root = await _directory();
    final safe = base64Url.encode(utf8.encode(key)).replaceAll('=', '');
    return File('${root.path}/astra_cache/$safe.json');
  }

  @override
  Future<Object?> read(String key) async {
    try {
      final file = await _file(key);
      if (!await file.exists()) return null;
      return jsonDecode(await file.readAsString());
    } on Object catch (error) {
      debugPrint('Cache illisible ($key) : $error');
      return null;
    }
  }

  @override
  Future<void> write(String key, Object? data) async {
    try {
      final file = await _file(key);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(data));
    } on Object catch (error) {
      debugPrint('Cache non enregistré ($key) : $error');
    }
  }

  @override
  Future<void> clear() async {
    try {
      final root = await _directory();
      final folder = Directory('${root.path}/astra_cache');
      if (await folder.exists()) await folder.delete(recursive: true);
    } on Object catch (error) {
      debugPrint('Cache non effacé : $error');
    }
  }
}

class MemoryCacheStore implements CacheStore {
  final _data = <String, Object?>{};

  @override
  Future<Object?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, Object? data) async => _data[key] = data;

  @override
  Future<void> clear() async => _data.clear();
}

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

/// Fichier choisi sur le téléphone, prêt à être envoyé.
class PickedFile {
  const PickedFile({required this.path, required this.name, this.size});

  final String path;
  final String name;
  final int? size;

  Future<MultipartFile> toMultipart() => MultipartFile.fromFile(path, filename: name);
}

/// Formats acceptés par le serveur pour les documents et preuves.
const documentExtensions = [
  'pdf',
  'png',
  'jpg',
  'jpeg',
  'docx',
  'xlsx',
  'pptx',
  'odt',
  'txt',
  'csv',
];

Future<PickedFile?> pickDocument({List<String> extensions = documentExtensions}) async {
  final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: extensions);
  final file = result.singleOrNull;
  if (file == null || file.path == null) return null;
  return PickedFile(path: file.path!, name: file.name);
}

/// Photo prise avec l'appareil (reçu, capture…), compressée avant envoi (§56).
Future<PickedFile?> takePhoto() async {
  final photo = await ImagePicker().pickImage(
    source: ImageSource.camera,
    imageQuality: 75,
    maxWidth: 2000,
  );
  if (photo == null) return null;
  return PickedFile(
    path: photo.path,
    name: photo.name.endsWith('.jpg') ? photo.name : '${photo.name}.jpg',
  );
}

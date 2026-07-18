import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ImageStorageService {
  ImageStorageService._();

  static Future<Directory> _imageDirectory() async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(root.path, 'inventory_images'));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  static Future<String> persistPickedImage({
    required String sourcePath,
    required String clientUid,
  }) async {
    if (sourcePath.isEmpty) return '';
    final source = File(sourcePath);
    if (!await source.exists()) return '';

    final directory = await _imageDirectory();
    final extension = p.extension(sourcePath).isEmpty ? '.jpg' : p.extension(sourcePath);
    final destination = File(p.join(directory.path, '$clientUid$extension'));

    if (p.normalize(source.path) == p.normalize(destination.path)) {
      return destination.path;
    }

    await source.copy(destination.path);
    return destination.path;
  }

  static Future<String> cacheRemoteImage({
    required String imageUrl,
    required String clientUid,
    String existingLocalPath = '',
  }) async {
    if (existingLocalPath.isNotEmpty && await File(existingLocalPath).exists()) {
      return existingLocalPath;
    }
    if (imageUrl.isEmpty) return existingLocalPath;

    try {
      final response = await http.get(Uri.parse(imageUrl)).timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300 || response.bodyBytes.isEmpty) {
        return existingLocalPath;
      }

      final directory = await _imageDirectory();
      final uriExtension = p.extension(Uri.parse(imageUrl).path);
      final extension = uriExtension.isEmpty ? '.jpg' : uriExtension;
      final destination = File(p.join(directory.path, '$clientUid$extension'));
      await destination.writeAsBytes(response.bodyBytes, flush: true);
      return destination.path;
    } catch (_) {
      return existingLocalPath;
    }
  }
}

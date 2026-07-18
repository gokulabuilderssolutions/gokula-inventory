import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.releaseNotes,
  });

  final String version;
  final String downloadUrl;
  final String releaseNotes;
}

class AppUpdateService {
  AppUpdateService._();

  static const String owner = 'gokulabuilderssolutions';
  static const String repository = 'gokula-inventory';

  static Future<AppUpdateInfo?> checkForUpdate() async {
    if (!Platform.isAndroid) return null;

    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;
    final uri = Uri.parse(
      'https://api.github.com/repos/$owner/$repository/releases/latest',
    );

    final response = await http
        .get(uri, headers: const {'Accept': 'application/vnd.github+json'})
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw Exception('GitHub update check failed (${response.statusCode}).');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final latestVersion = _cleanVersion(
      (json['tag_name'] ?? json['name'] ?? '').toString(),
    );
    if (latestVersion.isEmpty || !_isNewer(latestVersion, currentVersion)) {
      return null;
    }

    final assets = (json['assets'] as List<dynamic>? ?? const []);
    Map<String, dynamic>? apkAsset;
    for (final item in assets) {
      final asset = item as Map<String, dynamic>;
      final name = (asset['name'] ?? '').toString().toLowerCase();
      if (name.endsWith('.apk')) {
        apkAsset = asset;
        break;
      }
    }

    if (apkAsset == null) {
      throw Exception('The latest GitHub release does not contain an APK.');
    }

    return AppUpdateInfo(
      version: latestVersion,
      downloadUrl: apkAsset['browser_download_url'].toString(),
      releaseNotes: (json['body'] ?? '').toString(),
    );
  }

  static Future<File> downloadApk(
    AppUpdateInfo update, {
    required ValueChanged<double> onProgress,
  }) async {
    final request = http.Request('GET', Uri.parse(update.downloadUrl));
    final response = await request.send().timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception('APK download failed (${response.statusCode}).');
    }

    final directory = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/gokula-inventory-${update.version}.apk');
    final sink = file.openWrite();
    final total = response.contentLength ?? 0;
    var received = 0;

    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress(received / total);
      }
    } finally {
      await sink.close();
    }

    onProgress(1);
    return file;
  }

  static Future<void> installApk(File apk) async {
    final result = await OpenFilex.open(
      apk.path,
      type: 'application/vnd.android.package-archive',
    );
    if (result.type != ResultType.done) {
      throw Exception(result.message);
    }
  }

  static String _cleanVersion(String value) {
    final match = RegExp(r'(\d+\.\d+\.\d+)').firstMatch(value);
    return match?.group(1) ?? '';
  }

  static bool _isNewer(String latest, String current) {
    final latestParts = latest.split('.').map(int.parse).toList();
    final currentParts = _cleanVersion(current).split('.').map(int.parse).toList();
    if (currentParts.isEmpty) return true;
    for (var i = 0; i < 3; i++) {
      final left = i < latestParts.length ? latestParts[i] : 0;
      final right = i < currentParts.length ? currentParts[i] : 0;
      if (left != right) return left > right;
    }
    return false;
  }
}

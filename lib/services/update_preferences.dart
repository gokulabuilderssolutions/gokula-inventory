import 'package:shared_preferences/shared_preferences.dart';

class UpdatePreferences {
  UpdatePreferences._();

  static const _autoCheckKey = 'update_auto_check';
  static const _wifiDownloadKey = 'update_wifi_download';
  static const _downloadedVersionKey = 'update_downloaded_version';
  static const _downloadedPathKey = 'update_downloaded_path';

  static Future<bool> autoCheckEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoCheckKey) ?? true;
  }

  static Future<void> setAutoCheckEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoCheckKey, value);
  }

  static Future<bool> wifiDownloadEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_wifiDownloadKey) ?? true;
  }

  static Future<void> setWifiDownloadEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_wifiDownloadKey, value);
  }

  static Future<void> rememberDownloadedUpdate({
    required String version,
    required String path,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_downloadedVersionKey, version);
    await prefs.setString(_downloadedPathKey, path);
  }

  static Future<String?> downloadedVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_downloadedVersionKey);
  }

  static Future<String?> downloadedPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_downloadedPathKey);
  }

  static Future<void> clearDownloadedUpdate() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_downloadedVersionKey);
    await prefs.remove(_downloadedPathKey);
  }
}

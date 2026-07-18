import 'package:flutter/material.dart';

import '../services/update_preferences.dart';

class UpdateSettingsScreen extends StatefulWidget {
  const UpdateSettingsScreen({super.key});

  @override
  State<UpdateSettingsScreen> createState() => _UpdateSettingsScreenState();
}

class _UpdateSettingsScreenState extends State<UpdateSettingsScreen> {
  bool _loading = true;
  bool _autoCheck = true;
  bool _wifiDownload = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final autoCheck = await UpdatePreferences.autoCheckEnabled();
    final wifiDownload = await UpdatePreferences.wifiDownloadEnabled();
    if (!mounted) return;
    setState(() {
      _autoCheck = autoCheck;
      _wifiDownload = wifiDownload;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Update settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                SwitchListTile(
                  value: _autoCheck,
                  title: const Text('Check for updates automatically'),
                  subtitle: const Text('Check GitHub Releases whenever the app opens.'),
                  onChanged: (value) async {
                    await UpdatePreferences.setAutoCheckEnabled(value);
                    if (!mounted) return;
                    setState(() => _autoCheck = value);
                  },
                ),
                SwitchListTile(
                  value: _wifiDownload,
                  title: const Text('Download automatically on Wi-Fi'),
                  subtitle: const Text(
                    'When an update is found on Wi-Fi, download the APK automatically. Android will still ask before installation.',
                  ),
                  onChanged: _autoCheck
                      ? (value) async {
                          await UpdatePreferences.setWifiDownloadEnabled(value);
                          if (!mounted) return;
                          setState(() => _wifiDownload = value);
                        }
                      : null,
                ),
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'For security, Android does not allow normal apps to install APK updates silently. After download, tap Install when Android asks.',
                  ),
                ),
              ],
            ),
    );
  }
}

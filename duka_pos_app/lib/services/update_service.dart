import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateService {
  static const _githubRepo =
      'your-username/duka-pos'; // Replace with actual repo

  /// Check if update is available from GitHub releases
  static Future<Map<String, dynamic>?> checkForUpdate() async {
    try {
      final response = await Dio().get(
        'https://api.github.com/repos/$_githubRepo/releases/latest',
        options: Options(
          headers: {'Accept': 'application/vnd.github.v3+json'},
        ),
      );

      final currentVersion = await _getCurrentVersion();
      final latestVersion = response.data['tag_name'] as String?;

      if (latestVersion != null && latestVersion != 'v$currentVersion') {
        final apkUrl = _extractApkUrl(response.data['assets'] as List);
        return {
          'current_version': currentVersion,
          'latest_version': latestVersion,
          'download_url': apkUrl,
          'release_notes': response.data['body'],
        };
      }

      return null;
    } catch (e) {
      // Network error or no releases - fail silently
      return null;
    }
  }

  static Future<String> _getCurrentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  static String? _extractApkUrl(List assets) {
    final apk = assets.cast<Map<String, dynamic>>().firstWhere(
          (asset) => (asset['name'] as String).endsWith('.apk'),
          orElse: () => <String, dynamic>{},
        );
    return apk['browser_download_url'] as String?;
  }

  /// Show update dialog
  static Future<void> showUpdateDialog(
    BuildContext context,
    Map<String, dynamic> updateInfo,
  ) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Update Available'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Version ${updateInfo['latest_version']} is available.',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('You are using version ${updateInfo['current_version']}'),
            if (updateInfo['release_notes'] != null) ...[
              const SizedBox(height: 12),
              const Text(
                'What\'s new:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                updateInfo['release_notes'],
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _downloadUpdate(updateInfo['download_url']);
            },
            child: const Text('Download'),
          ),
        ],
      ),
    );
  }

  static Future<void> _downloadUpdate(String? url) async {
    if (url == null) return;

    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

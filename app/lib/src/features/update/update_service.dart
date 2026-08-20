import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../../theme/app_colors.dart';

class UpdateService {
  static const String currentVersion = '1.3.0';
  static bool _hasCheckedThisSession = false;

  /// Consulta en segundo plano la última versión disponible en GitHub Releases.
  static Future<void> checkForUpdates(BuildContext context, {bool forceShow = false}) async {
    if (_hasCheckedThisSession && !forceShow) return;
    _hasCheckedThisSession = true;

    try {
      final uri = Uri.parse('https://api.github.com/repos/thelioning/InclusiChat/releases/latest');
      final response = await http.get(
        uri,
        headers: {'Accept': 'application/vnd.github.v3+json'},
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final latestTag = (data['tag_name'] as String?)?.replaceAll('v', '').trim() ?? '';
        final releaseNotes = (data['body'] as String?)?.trim() ?? '';

        String? apkDownloadUrl;
        final assets = data['assets'] as List<dynamic>?;
        if (assets != null) {
          for (final asset in assets) {
            final name = (asset['name'] as String?) ?? '';
            if (name.endsWith('.apk')) {
              apkDownloadUrl = asset['browser_download_url'] as String?;
              break;
            }
          }
        }
        apkDownloadUrl ??= 'https://github.com/thelioning/InclusiChat/releases/latest';

        if (_isVersionNewer(latestTag, currentVersion)) {
          if (context.mounted) {
            _showUpdateDialog(
              context,
              newVersion: latestTag,
              notes: releaseNotes,
              downloadUrl: apkDownloadUrl,
            );
          }
        } else if (forceShow && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ya tienes instalada la versión más reciente de InclusiChat (v$currentVersion).'),
              backgroundColor: AppColors.primary,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Update check error: $e');
    }
  }

  static bool _isVersionNewer(String latest, String current) {
    if (latest.isEmpty) return false;
    final latestParts = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final currentParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    for (int i = 0; i < latestParts.length && i < currentParts.length; i++) {
      if (latestParts[i] > currentParts[i]) return true;
      if (latestParts[i] < currentParts[i]) return false;
    }
    return latestParts.length > currentParts.length;
  }

  static void _showUpdateDialog(
    BuildContext context, {
    required String newVersion,
    required String notes,
    required String downloadUrl,
  }) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.system_update_rounded, color: AppColors.primary, size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                '¡Actualización disponible!',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hay una nueva versión de InclusiChat disponible: v$newVersion (tu versión actual es v$currentVersion).',
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Novedades de esta versión:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 6),
              Container(
                constraints: const BoxConstraints(maxHeight: 120),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceRaised,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    notes,
                    style: const TextStyle(fontSize: 12, height: 1.3),
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Más tarde', style: TextStyle(color: AppColors.textSecondary)),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Descargar e Instalar'),
            onPressed: () async {
              Navigator.of(ctx).pop();
              final uri = Uri.parse(downloadUrl);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
          ),
        ],
      ),
    );
  }
}

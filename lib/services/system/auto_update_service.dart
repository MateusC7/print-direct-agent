import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants.dart';
import '../../core/theme/app_colors.dart';
import '../logger_service.dart';
import '../settings_service.dart';

class UpdateInfo {
  final String version;
  final int buildNumber;
  final String downloadUrl;
  final String changelog;
  final bool forceUpdate;

  UpdateInfo({
    required this.version,
    required this.buildNumber,
    required this.downloadUrl,
    required this.changelog,
    this.forceUpdate = false,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    String url = '';
    if (Platform.isWindows) {
      url = json['download_url_windows'] ?? json['download_url'] ?? '';
    } else if (Platform.isAndroid) {
      url = json['download_url_android'] ?? json['download_url'] ?? '';
    } else if (Platform.isMacOS) {
      url = json['download_url_macos'] ?? json['download_url'] ?? '';
    } else {
      url = json['download_url_linux'] ?? json['download_url'] ?? '';
    }

    return UpdateInfo(
      version: json['version'] ?? '2.0.0',
      buildNumber: json['build_number'] ?? 1,
      downloadUrl: url,
      changelog: json['changelog'] ??
          'Mejoras continuas de rendimiento y estabilidad.',
      forceUpdate: json['force_update'] == true,
    );
  }
}

/// Servicio de Actualizaciones Automáticas y OTA (Over-The-Air).
/// Verifica al iniciar si existe una nueva versión en el servidor del negocio
/// y permite actualizar en 1 clic de forma transparente.
class AutoUpdateService {
  AutoUpdateService._();
  static final AutoUpdateService instance = AutoUpdateService._();

  bool _isChecking = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;

  bool get isChecking => _isChecking;
  bool get isDownloading => _isDownloading;
  double get downloadProgress => _downloadProgress;

  /// Compara dos versiones semánticas (ej. "2.1.0" > "2.0.0")
  bool _isVersionNewer(String remoteVersion, String currentVersion) {
    try {
      final remoteParts =
          remoteVersion.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final currentParts =
          currentVersion.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      while (remoteParts.length < 3) {
        remoteParts.add(0);
      }
      while (currentParts.length < 3) {
        currentParts.add(0);
      }

      for (int i = 0; i < 3; i++) {
        if (remoteParts[i] > currentParts[i]) return true;
        if (remoteParts[i] < currentParts[i]) return false;
      }
    } catch (_) {}
    return false;
  }

  /// Verifica si hay una nueva versión disponible
  Future<UpdateInfo?> checkForUpdates() async {
    if (_isChecking) return null;
    _isChecking = true;

    try {
      final settings = SettingsService.instance;
      final odooUrl = settings.odooUrl.trim().replaceAll(RegExp(r'/+$'), '');
      if (odooUrl.isEmpty) {
        _isChecking = false;
        return null;
      }

      var normalizedUrl = odooUrl;
      if (!normalizedUrl.startsWith('http://') &&
          !normalizedUrl.startsWith('https://')) {
        normalizedUrl = '${settings.odooProtocol}://$normalizedUrl';
      }
      final parsedUrl = Uri.parse(normalizedUrl);
      final basePath = parsedUrl.path.endsWith('/')
          ? parsedUrl.path.substring(0, parsedUrl.path.length - 1)
          : parsedUrl.path;
      final endpoint = parsedUrl
          .replace(
            path: '$basePath/web/print_agent/version.json',
            queryParameters: const {},
            fragment: '',
          )
          .toString();

      LoggerService.info(
          '🔍 [UPDATE] Comprobando actualizaciones en: $endpoint');

      final response = await http
          .get(Uri.parse(endpoint))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final updateInfo = UpdateInfo.fromJson(data);

        if (_isVersionNewer(updateInfo.version, AppConstants.appVersion)) {
          LoggerService.info(
              '🚀 [UPDATE] Nueva versión disponible: v${updateInfo.version}');
          _isChecking = false;
          return updateInfo;
        } else {
          LoggerService.info(
              '✅ [UPDATE] La aplicación está actualizada (v${AppConstants.appVersion}).');
        }
      }
    } catch (e) {
      LoggerService.warn('⚠️ [UPDATE] No se pudo verificar actualización: $e');
    } finally {
      _isChecking = false;
    }
    return null;
  }

  /// Descarga el instalador o APK e inicia la actualización
  Future<bool> downloadAndInstall(
    UpdateInfo info, {
    Function(double progress)? onProgress,
  }) async {
    if (_isDownloading) return false;
    _isDownloading = true;
    _downloadProgress = 0.0;

    try {
      if (info.downloadUrl.isEmpty) {
        throw Exception('URL de descarga vacía');
      }

      final uri = Uri.parse(info.downloadUrl);
      final client = http.Client();
      final request = http.Request('GET', uri);
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception('Error del servidor: HTTP ${response.statusCode}');
      }

      final contentLength = response.contentLength ?? 0;
      final tempDir = Directory.systemTemp;
      final extension = Platform.isWindows
          ? 'exe'
          : (Platform.isAndroid ? 'apk' : (Platform.isMacOS ? 'dmg' : 'bin'));

      final targetFile = File(
          '${tempDir.path}/SoftwareRestaurante_update_${info.version}.$extension');
      final sink = targetFile.openWrite();

      int downloaded = 0;
      await for (final chunk in response.stream) {
        sink.add(chunk);
        downloaded += chunk.length;
        if (contentLength > 0) {
          _downloadProgress = downloaded / contentLength;
          onProgress?.call(_downloadProgress);
        }
      }
      await sink.flush();
      await sink.close();

      LoggerService.info(
          '💾 [UPDATE] Archivo descargado en: ${targetFile.path}');

      // Ejecutar la actualización según la plataforma
      if (Platform.isWindows) {
        // Ejecutar el instalador en segundo plano y cerrar la app actual para permitir la sobreescritura
        await Process.start(targetFile.path, ['/SILENT', '/NORESTART'],
            mode: ProcessStartMode.detached);
        LoggerService.info('🔄 [UPDATE] Lanzando instalador de Windows...');
        exit(0);
      } else if (Platform.isAndroid) {
        // Abrir el APK para que el instalador de Android lo procese
        final fileUri = Uri.file(targetFile.path);
        if (await canLaunchUrl(fileUri)) {
          await launchUrl(fileUri, mode: LaunchMode.externalApplication);
        }
      } else if (Platform.isMacOS) {
        await Process.run('open', [targetFile.path]);
      }

      _isDownloading = false;
      return true;
    } catch (e) {
      LoggerService.error('❌ [UPDATE] Error durante la actualización: $e');
      _isDownloading = false;
      return false;
    }
  }

  /// Muestra el modal de actualización disponible al usuario
  void showUpdateDialog(BuildContext context, UpdateInfo info) {
    showDialog(
      context: context,
      barrierDismissible: !info.forceUpdate,
      builder: (ctx) {
        double currentProgress = 0.0;
        bool isDownloading = false;
        String? errorMessage;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;

            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1E1E22) : Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: kAccent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.system_update_rounded,
                        color: kAccent, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Actualización Disponible',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hay una nueva versión lista para instalar: v${info.version}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    info.changelog,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? const Color(0xFFA1A1AA)
                          : const Color(0xFF64748B),
                      height: 1.4,
                    ),
                  ),
                  if (isDownloading) ...[
                    const SizedBox(height: 18),
                    LinearProgressIndicator(
                      value: currentProgress > 0 ? currentProgress : null,
                      backgroundColor: isDark ? Colors.white10 : Colors.black12,
                      color: kAccent,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      currentProgress > 0
                          ? 'Descargando: ${(currentProgress * 100).toStringAsFixed(0)}%'
                          : 'Iniciando descarga...',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? const Color(0xFFA1A1AA)
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                  if (errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      errorMessage!,
                      style: const TextStyle(fontSize: 11, color: kError),
                    ),
                  ],
                ],
              ),
              actions: [
                if (!info.forceUpdate && !isDownloading)
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(
                      'Más tarde',
                      style: TextStyle(
                          color: isDark
                              ? const Color(0xFFA1A1AA)
                              : const Color(0xFF64748B)),
                    ),
                  ),
                ElevatedButton(
                  onPressed: isDownloading
                      ? null
                      : () async {
                          setDialogState(() {
                            isDownloading = true;
                            errorMessage = null;
                          });

                          final success = await downloadAndInstall(
                            info,
                            onProgress: (p) {
                              setDialogState(() {
                                currentProgress = p;
                              });
                            },
                          );

                          if (!success && context.mounted) {
                            setDialogState(() {
                              isDownloading = false;
                              errorMessage =
                                  'No se pudo completar la actualización. Intente nuevamente.';
                            });
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(
                      isDownloading ? 'Actualizando...' : 'Actualizar ahora'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

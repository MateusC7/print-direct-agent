import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../../core/constants.dart';

/// Resultado del proceso de generación de SSL.
class SslResult {
  final bool success;
  final String certPath;
  final String keyPath;
  final String message;

  const SslResult({
    required this.success,
    required this.certPath,
    required this.keyPath,
    required this.message,
  });
}

/// Servicio SSL: extrae mkcert del bundle, lo descarga si falta,
/// y genera localhost.pem + localhost-key.pem.
class SslService {
  SslService._();
  static final SslService instance = SslService._();

  String? _certPath;
  String? _keyPath;

  String? get certPath => _certPath;
  String? get keyPath => _keyPath;

  /// Callback de progreso para actualizar el log de la UI.
  Function(String)? onLog;

  void _log(String msg) => onLog?.call(msg);

  // ── Directorio de aplicación ──────────────────────────────────────
  Future<Directory> _getAppDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/SoftwareRestaurante/ssl');
    await dir.create(recursive: true);
    return dir;
  }

  // ── Verificar certificados existentes ─────────────────────────────
  bool _certsExist(Directory dir) {
    final cert = File('${dir.path}/${AppConstants.certFileName}');
    final key = File('${dir.path}/${AppConstants.keyFileName}');
    return cert.existsSync() && key.existsSync();
  }

  /// Punto de entrada principal. Devuelve SslResult con paths o error.
  Future<SslResult> ensureCertificates() async {
    final appDir = await _getAppDir();
    final certFile = '${appDir.path}/${AppConstants.certFileName}';
    final keyFile = '${appDir.path}/${AppConstants.keyFileName}';

    // 1. Si ya existen, reutilizar
    if (_certsExist(appDir)) {
      _certPath = certFile;
      _keyPath = keyFile;
      _log('Certificado SSL existente encontrado.');
      return SslResult(
        success: true,
        certPath: certFile,
        keyPath: keyFile,
        message: 'Certs found',
      );
    }

    // 2. Obtener mkcert
    final mkcertPath = await _ensureMkcert(appDir);
    if (mkcertPath == null) {
      return SslResult(
        success: false,
        certPath: '',
        keyPath: '',
        message: 'No se pudo obtener mkcert',
      );
    }

    // 3. Instalar CA local (requiere UAC en Windows, silencioso en Mac/Linux)
    _log('Instalando autoridad certificadora de mkcert...');
    try {
      await Process.run(mkcertPath, ['-install']);
    } catch (e) {
      _log('[ADVERTENCIA] mkcert -install: $e (puede requerir permiso de administrador)');
    }

    // 4. Generar certificados
    _log('Generando certificado SSL de confianza...');
    final localIp = await _getLocalIp();
    try {
      final result = await Process.run(mkcertPath, [
        '-cert-file', certFile,
        '-key-file', keyFile,
        'localhost',
        '127.0.0.1',
        localIp,
      ]);

      if (_certsExist(appDir)) {
        _certPath = certFile;
        _keyPath = keyFile;
        _log('Certificado SSL generado con éxito.');
        return SslResult(
          success: true,
          certPath: certFile,
          keyPath: keyFile,
          message: 'Certs generated',
        );
      }
      return SslResult(
        success: false,
        certPath: '',
        keyPath: '',
        message: 'mkcert no generó archivos: ${result.stderr}',
      );
    } catch (e) {
      return SslResult(
        success: false,
        certPath: '',
        keyPath: '',
        message: 'Error mkcert: $e',
      );
    }
  }

  // ── Obtener mkcert: primero del sistema, luego de assets, luego descarga ──
  Future<String?> _ensureMkcert(Directory appDir) async {
    // 1. Verificar si ya está instalado en el sistema (ej. Homebrew en macOS / Linux)
    if (!Platform.isWindows) {
      final systemPaths = [
        '/opt/homebrew/bin/mkcert', // Apple Silicon Homebrew
        '/usr/local/bin/mkcert',   // Intel Mac Homebrew / Linux usr/local
        '/usr/bin/mkcert',         // Linux distro package
      ];
      for (final p in systemPaths) {
        if (File(p).existsSync()) {
          _log('mkcert encontrado en el sistema: $p');
          return p;
        }
      }
    }

    final sep = Platform.pathSeparator;
    final mkcertExe = Platform.isWindows
        ? '${appDir.path}${sep}mkcert.exe'
        : Platform.isMacOS
            ? '${appDir.path}${sep}mkcert-darwin'
            : '${appDir.path}${sep}mkcert-linux';

    // 2. ¿Ya existe descargado en el directorio de la app?
    if (File(mkcertExe).existsSync()) {
      if (!Platform.isWindows) {
        await Process.run('chmod', ['+x', mkcertExe]);
      }
      return mkcertExe;
    }

    // 3. ¿Está en los assets del bundle?
    final assetKey = Platform.isWindows
        ? AppConstants.mkcertAssetWindows
        : Platform.isMacOS
            ? AppConstants.mkcertAssetMacos
            : AppConstants.mkcertAssetLinux;

    try {
      final data = await rootBundle.load(assetKey);
      final bytes = data.buffer.asUint8List();
      await File(mkcertExe).writeAsBytes(bytes);
      if (!Platform.isWindows) {
        await Process.run('chmod', ['+x', mkcertExe]);
      }
      _log('mkcert extraído de assets del bundle.');
      return mkcertExe;
    } catch (_) {
      // No está en assets — intentar descarga automática
    }

    // 4. Descargar de GitHub releases según plataforma y arquitectura (Apple Silicon vs Intel)
    String downloadUrl;
    if (Platform.isWindows) {
      downloadUrl = AppConstants.mkcertDownloadWindows;
    } else if (Platform.isMacOS) {
      final isArm = await _isMacArm64();
      downloadUrl = isArm
          ? AppConstants.mkcertDownloadMacosArm64
          : AppConstants.mkcertDownloadMacosAmd64;
      _log('Detectada arquitectura macOS: ${isArm ? "Apple Silicon (ARM64)" : "Intel (x86_64)"}');
    } else {
      downloadUrl = AppConstants.mkcertDownloadLinux;
    }

    final platform = Platform.operatingSystem;
    _log('Descargando mkcert para ${_platformName(platform)}...');
    try {
      final response = await http.get(Uri.parse(downloadUrl));
      if (response.statusCode == 200) {
        await File(mkcertExe).writeAsBytes(response.bodyBytes);
        if (!Platform.isWindows) {
          await Process.run('chmod', ['+x', mkcertExe]);
        }
        _log('mkcert descargado correctamente (${response.bodyBytes.length} bytes).');
        return mkcertExe;
      }
      _log('[ERROR] Descargando mkcert: HTTP ${response.statusCode}');
      return null;
    } catch (e) {
      _log('[ERROR] Descargando mkcert: $e');
      return null;
    }
  }

  /// Detecta si el sistema macOS es Apple Silicon (M1/M2/M3/M4) o Intel
  Future<bool> _isMacArm64() async {
    if (!Platform.isMacOS) return false;
    try {
      final res = await Process.run('uname', ['-m']);
      if (res.exitCode == 0) {
        final arch = (res.stdout as String).trim().toLowerCase();
        return arch.contains('arm') || arch.contains('aarch64');
      }
    } catch (_) {}
    // Fallback: verificar si /opt/homebrew existe (propio de Apple Silicon)
    return Directory('/opt/homebrew').existsSync();
  }

  // ── IP local ──────────────────────────────────────────────────────
  Future<String> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4, includeLoopback: false);
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return '127.0.0.1';
  }

  String _platformName(String p) => switch (p) {
        'windows' => 'Windows',
        'macos' => 'macOS',
        'linux' => 'Linux',
        _ => p,
      };

  /// Borra los certificados existentes (para regenerar en próximo arranque).
  Future<void> deleteCerts() async {
    final appDir = await _getAppDir();
    try {
      File('${appDir.path}/${AppConstants.certFileName}').deleteSync();
      File('${appDir.path}/${AppConstants.keyFileName}').deleteSync();
    } catch (_) {}
    _certPath = null;
    _keyPath = null;
  }
}

import 'dart:io';
import 'package:process_run/process_run.dart';
import '../logger_service.dart';

/// Servicio Universal de Auto-Arranque para Sistemas de Escritorio (Windows y macOS).
/// En Windows: Utiliza el Registro de Usuario (HKCU\...\Run).
/// En macOS: Utiliza LaunchAgents de usuario (~/Library/LaunchAgents).
/// No requiere permisos de Administrador ni Root en ninguna plataforma.
class AutoStartService {
  AutoStartService._();
  static final AutoStartService instance = AutoStartService._();

  static const String _appName = 'SoftwareRestaurantePrintAgent';
  static const String _macLabel = 'com.softwarerestaurante.printapp';
  static const String _winRegKeyPath = r'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run';

  /// Obtiene la ruta del archivo plist de LaunchAgents en macOS
  String? _getMacLaunchAgentPath() {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) return null;
    return '$home/Library/LaunchAgents/$_macLabel.plist';
  }

  /// Verifica si el inicio automático está activo en el sistema actual
  Future<bool> isAutoStartEnabled() async {
    if (Platform.isWindows) {
      return _isWindowsAutoStartEnabled();
    } else if (Platform.isMacOS) {
      return _isMacAutoStartEnabled();
    } else if (Platform.isLinux) {
      return _isLinuxAutoStartEnabled();
    }
    return false;
  }

  /// Habilita el inicio automático
  Future<bool> enableAutoStart() async {
    if (Platform.isWindows) {
      return _enableWindowsAutoStart();
    } else if (Platform.isMacOS) {
      return _enableMacAutoStart();
    } else if (Platform.isLinux) {
      return _enableLinuxAutoStart();
    }
    return false;
  }

  /// Deshabilita el inicio automático
  Future<bool> disableAutoStart() async {
    if (Platform.isWindows) {
      return _disableWindowsAutoStart();
    } else if (Platform.isMacOS) {
      return _disableMacAutoStart();
    } else if (Platform.isLinux) {
      return _disableLinuxAutoStart();
    }
    return false;
  }

  /// Alterna o establece el estado de inicio automático
  Future<bool> setAutoStart(bool enable) async {
    if (enable) {
      return await enableAutoStart();
    } else {
      return await disableAutoStart();
    }
  }

  // ── WINDOWS IMPLEMENTATION ──────────────────────────────────────────────

  Future<bool> _isWindowsAutoStartEnabled() async {
    try {
      final shell = Shell();
      final result = await shell.run(
        'powershell -NoProfile -Command "Get-ItemPropertyValue -Path \'$_winRegKeyPath\' -Name \'$_appName\' -ErrorAction SilentlyContinue"',
      );
      final output = result.outText.trim();
      return output.isNotEmpty;
    } catch (e) {
      LoggerService.error('Error consultando auto-arranque en Windows: $e');
      return false;
    }
  }

  Future<bool> _enableWindowsAutoStart() async {
    try {
      final exePath = Platform.resolvedExecutable;
      final shell = Shell();
      final cmd = 'powershell -NoProfile -Command "Set-ItemProperty -Path \'$_winRegKeyPath\' -Name \'$_appName\' -Value \'`"$exePath`"\'"';
      await shell.run(cmd);
      LoggerService.info('✅ Auto-arranque de Windows habilitado: $exePath');
      return true;
    } catch (e) {
      LoggerService.error('❌ Error habilitando auto-arranque en Windows: $e');
      return false;
    }
  }

  Future<bool> _disableWindowsAutoStart() async {
    try {
      final shell = Shell();
      final cmd = 'powershell -NoProfile -Command "Remove-ItemProperty -Path \'$_winRegKeyPath\' -Name \'$_appName\' -ErrorAction SilentlyContinue"';
      await shell.run(cmd);
      LoggerService.info('🚫 Auto-arranque de Windows deshabilitado.');
      return true;
    } catch (e) {
      LoggerService.error('❌ Error deshabilitando auto-arranque en Windows: $e');
      return false;
    }
  }

  // ── MACOS IMPLEMENTATION ────────────────────────────────────────────────

  Future<bool> _isMacAutoStartEnabled() async {
    try {
      final plistPath = _getMacLaunchAgentPath();
      if (plistPath == null) return false;
      return File(plistPath).existsSync();
    } catch (e) {
      LoggerService.error('Error consultando auto-arranque en macOS: $e');
      return false;
    }
  }

  Future<bool> _enableMacAutoStart() async {
    try {
      final plistPath = _getMacLaunchAgentPath();
      if (plistPath == null) return false;

      final plistFile = File(plistPath);
      final parentDir = plistFile.parent;
      if (!parentDir.existsSync()) {
        await parentDir.create(recursive: true);
      }

      // Obtener la ruta del ejecutable de la app (.app bundle o binary)
      final exePath = Platform.resolvedExecutable;

      final plistContent = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$_macLabel</string>
    <key>ProgramArguments</key>
    <array>
        <string>$exePath</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
''';

      await plistFile.writeAsString(plistContent);

      try {
        await Process.run('launchctl', ['load', plistPath]);
      } catch (_) {}

      LoggerService.info('✅ Auto-arranque de macOS habilitado: $plistPath');
      return true;
    } catch (e) {
      LoggerService.error('❌ Error habilitando auto-arranque en macOS: $e');
      return false;
    }
  }

  Future<bool> _disableMacAutoStart() async {
    try {
      final plistPath = _getMacLaunchAgentPath();
      if (plistPath == null) return false;

      final plistFile = File(plistPath);
      if (plistFile.existsSync()) {
        try {
          await Process.run('launchctl', ['unload', plistPath]);
        } catch (_) {}
        await plistFile.delete();
      }

      LoggerService.info('🚫 Auto-arranque de macOS deshabilitado.');
      return true;
    } catch (e) {
      LoggerService.error('❌ Error deshabilitando auto-arranque en macOS: $e');
      return false;
    }
  }

  // ── LINUX IMPLEMENTATION (XDG Autostart) ─────────────────────────────────

  String? _getLinuxAutostartPath() {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) return null;
    return '$home/.config/autostart/SoftwareRestaurante.desktop';
  }

  Future<bool> _isLinuxAutoStartEnabled() async {
    try {
      final path = _getLinuxAutostartPath();
      if (path == null) return false;
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  Future<bool> _enableLinuxAutoStart() async {
    try {
      final path = _getLinuxAutostartPath();
      if (path == null) return false;
      final file = File(path);
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }
      final exePath = Platform.resolvedExecutable;
      final content = '''[Desktop Entry]
Type=Application
Version=1.0
Name=Software Restaurante
Comment=Agente de Impresión Local
Exec="$exePath"
Icon=printer
Terminal=false
StartupNotify=false
Categories=Utility;
X-GNOME-Autostart-enabled=true
''';
      await file.writeAsString(content);
      LoggerService.info('🟢 Auto-arranque de Linux (.desktop) habilitado.');
      return true;
    } catch (e) {
      LoggerService.error('❌ Error habilitando auto-arranque en Linux: $e');
      return false;
    }
  }

  Future<bool> _disableLinuxAutoStart() async {
    try {
      final path = _getLinuxAutostartPath();
      if (path == null) return false;
      final file = File(path);
      if (file.existsSync()) {
        await file.delete();
      }
      LoggerService.info('🚫 Auto-arranque de Linux deshabilitado.');
      return true;
    } catch (e) {
      LoggerService.error('❌ Error deshabilitando auto-arranque en Linux: $e');
      return false;
    }
  }
}

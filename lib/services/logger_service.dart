import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Servicio de bitácora de logs persistente y rotativo en disco.
/// Limita el tamaño de archivo a 5MB y almacena un historial rotativo de hasta 3 archivos.
class LoggerService {
  static File? _logFile;
  static bool _initialized = false;
  static void Function(String message)? onLog;

  /// Inicializa la ruta física del archivo de bitácora en la carpeta de soporte de la app.
  static Future<void> init() async {
    if (_initialized) return;
    try {
      final base = await getApplicationSupportDirectory();
      final logDir = Directory('${base.path}/logs');
      await logDir.create(recursive: true);
      _logFile = File('${logDir.path}/agent.log');
      _initialized = true;
      info('=== INICIO DEL AGENTE DE IMPRESION ===');
      await _rotateLogsIfNeeded();
    } catch (e) {
      print('[ERROR] inicializando LoggerService: $e');
    }
  }

  /// Registra un mensaje informativo.
  static void info(String message) {
    _log('INFO', message);
  }

  /// Registra una advertencia.
  static void warn(String message) {
    _log('WARN', message);
  }

  /// Alias de compatibilidad para advertencia.
  static void warning(String message) {
    _log('WARN', message);
  }

  /// Registra un error o excepción.
  static void error(String message) {
    _log('ERROR', message);
  }

  /// Escribe el log formateado a la consola, UI y de forma persistente al archivo de disco.
  static void _log(String level, String message) {
    // Normalizar mensaje eliminando emojis si alguno llegara a escapar
    final cleanMessage = message.replaceAll(
      RegExp(r'[\u{1F300}-\u{1FAFF}]|[\u{2600}-\u{27BF}]|[\u{1F600}-\u{1F64F}]|[\u{1F680}-\u{1F6FF}]', unicode: true),
      '',
    ).trim();

    final timestamp = DateTime.now().toIso8601String();
    final formatted = '[$timestamp] [$level] $cleanMessage';
    print(formatted);

    try {
      onLog?.call(cleanMessage);
    } catch (_) {}

    if (_initialized && _logFile != null) {
      try {
        _logFile!.writeAsStringSync('$formatted\n', mode: FileMode.append, flush: true);
        _rotateLogsIfNeeded();
      } catch (e) {
        print('[ERROR] escribiendo log a disco: $e');
      }
    }
  }

  /// Verifica si el archivo excede los 5MB para realizar la rotación física (.log -> .log.1 -> .log.2 -> .log.3).
  static Future<void> _rotateLogsIfNeeded() async {
    if (_logFile == null || !_logFile!.existsSync()) return;
    try {
      final length = _logFile!.lengthSync();
      const maxBytes = 5 * 1024 * 1024; // 5MB
      if (length > maxBytes) {
        final path = _logFile!.path;

        final f3 = File('$path.3');
        if (f3.existsSync()) {
          f3.deleteSync();
        }

        final f2 = File('$path.2');
        if (f2.existsSync()) {
          f2.renameSync('$path.3');
        }

        final f1 = File('$path.1');
        if (f1.existsSync()) {
          f1.renameSync('$path.2');
        }

        _logFile!.renameSync('$path.1');

        // Re-inicializa el archivo de log principal vacío
        _logFile = File(path);
        _logFile!.writeAsStringSync(
          '[${DateTime.now().toIso8601String()}] [INFO] === ARCHIVO DE LOGS ROTADO (LIMITE DE 5MB EXCEDIDO) ===\n',
          mode: FileMode.write,
          flush: true,
        );
      }
    } catch (e) {
      print('❌ Error rotando logs de impresión: $e');
    }
  }
}

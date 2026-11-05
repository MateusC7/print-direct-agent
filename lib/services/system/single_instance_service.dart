import 'dart:io';
import '../logger_service.dart';

/// Servicio de Bloqueo de Instancia Única para escritorio (Windows / macOS / Linux).
/// Evita que múltiples ejecuciones de la app intenten vincular el mismo puerto o bloquear Win32.
class SingleInstanceService {
  SingleInstanceService._();
  static final SingleInstanceService instance = SingleInstanceService._();

  static const int _lockPort = 59182; // Puerto de bloqueo loopback interno
  ServerSocket? _lockSocket;

  /// Intenta adquirir el bloqueo de instancia única.
  /// Si ya existe otra instancia, le envía el comando "SHOW" para traerla al frente
  /// y devuelve `false` para que este proceso secundario se cierre limpiamente.
  Future<bool> acquireLock({Function()? onBringToFront}) async {
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
      return true;
    }

    try {
      _lockSocket = await ServerSocket.bind(InternetAddress.loopbackIPv4, _lockPort);
      LoggerService.info('🔒 Bloqueo de instancia única adquirido en el puerto $_lockPort');

      // Escuchar señales de segundas instancias que intenten abrirse
      _lockSocket!.listen((socket) {
        socket.listen((data) {
          final msg = String.fromCharCodes(data).trim();
          if (msg == 'SHOW') {
            onBringToFront?.call();
          }
        });
      });

      return true;
    } catch (e) {
      LoggerService.info('⚠️ Otra instancia detectada. Notificando para traer al frente...');
      try {
        final client = await Socket.connect(InternetAddress.loopbackIPv4, _lockPort,
            timeout: const Duration(seconds: 1));
        client.write('SHOW');
        await client.flush();
        await client.close();
      } catch (_) {}
      return false;
    }
  }

  /// Libera el bloqueo al cerrar la aplicación.
  void releaseLock() {
    try {
      _lockSocket?.close();
      _lockSocket = null;
    } catch (_) {}
  }
}

import 'dart:convert';
import 'dart:io';
import '../../services/logger_service.dart';
import '../../services/printer/printer_service.dart';
import '../../services/printer/print_queue_service.dart';
import '../../models/printer_model.dart';

/// Gestor de sesiones WebSocket bidireccionales en tiempo real.
/// Mantiene las conexiones activas con Odoo POS y difunde eventos de hardware al instante.
class WebSocketManager {
  static final WebSocketManager instance = WebSocketManager._internal();
  WebSocketManager._internal();

  final List<WebSocket> _clients = [];
  PrinterService? _printerService;

  /// Inicializa el servicio con el motor de impresoras.
  void init(PrinterService printerService) {
    _printerService = printerService;
  }

  /// Añade y escucha una nueva sesión de cliente WebSocket.
  void handleConnection(WebSocket socket) {
    _clients.add(socket);
    LoggerService.info(
        '🔌 WebSocket: Cliente POS conectado (Sesiones activas: ${_clients.length})');

    socket.listen(
      (message) {
        _handleMessage(socket, message);
      },
      onError: (err) {
        LoggerService.error('❌ WebSocket error en sesión: $err');
        _clients.remove(socket);
      },
      onDone: () {
        _clients.remove(socket);
        LoggerService.info(
            '🔌 WebSocket: Cliente POS desconectado (Sesiones activas: ${_clients.length})');
      },
      cancelOnError: true,
    );
  }

  /// Difunde un evento estructurado en JSON a todos los navegadores POS conectados.
  void broadcastEvent(String eventName, Map<String, dynamic> data) {
    if (_clients.isEmpty) return;

    final payload = jsonEncode({
      'event': eventName,
      ...data,
    });

    LoggerService.info(
        '📤 WebSocket: Difundiendo evento "$eventName" a ${_clients.length} cliente(s)');

    for (final client in _clients) {
      if (client.readyState == WebSocket.open) {
        try {
          client.add(payload);
        } catch (e) {
          LoggerService.error('Error enviando evento por socket: $e');
        }
      }
    }
  }

  /// Procesa los comandos entrantes enviados desde el POS.
  Future<void> _handleMessage(WebSocket socket, dynamic rawMessage) async {
    if (rawMessage is! String) return;
    try {
      final data = jsonDecode(rawMessage) as Map<String, dynamic>;
      final action = data['action'];
      final jobUuid = data['job_uuid'];

      if (action == 'print') {
        final printerName = data['printer'] as String?;
        final rawContent = data['data'] as String?; // base64
        final rawType = data['raw_type'] as String? ?? 'raw';
        final openCashbox = data['open_cashbox'] == true;

        if (printerName == null || rawContent == null) {
          socket.add(jsonEncode({
            'status': 'error',
            'job_uuid': jobUuid,
            'message': 'Parámetros "printer" o "data" faltantes.'
          }));
          return;
        }

        LoggerService.info(
            '📥 WebSocket: Recibido trabajo de impresión vía socket para "$printerName"');

        if (_printerService != null) {
          final printers = await _printerService!.getAllPrinters();
          PrinterModel? found;
          if (printerName.isNotEmpty &&
              printerName != 'POS-DEFAULT' &&
              printerName != 'default') {
            try {
              found = printers.firstWhere(
                (p) =>
                    p.name.toLowerCase().trim() ==
                        printerName.toLowerCase().trim() ||
                    p.name.toLowerCase().contains(printerName.toLowerCase()) ||
                    printerName.toLowerCase().contains(p.name.toLowerCase()),
              );
            } catch (_) {}
          }
          final PrinterModel target = found ??
              (printers.isNotEmpty
                  ? printers.firstWhere(
                      (p) =>
                          p.type == PrinterType.network ||
                          p.type == PrinterType.sunmi ||
                          p.type == PrinterType.bluetooth,
                      orElse: () => printers.first)
                  : PrinterModel(name: printerName, type: PrinterType.local));

          final bytes = base64Decode(rawContent.trim());
          final finalRawType = rawType;

          final uuid =
              jobUuid ?? 'job-${DateTime.now().microsecondsSinceEpoch}';

          // Encolamos el trabajo de impresión usando el motor de la Fase 2
          PrintQueueService.instance.enqueue(
            uuid: uuid,
            printerName: target.name,
            bytes: bytes,
            rawType: finalRawType,
            openCashbox: openCashbox,
          );

          socket.add(jsonEncode({
            'status': 'queued',
            'job_uuid': uuid,
          }));
        }
      } else if (action == 'ping') {
        socket.add(jsonEncode({'status': 'pong'}));
      }
    } catch (e) {
      LoggerService.error(
          '❌ WebSocket: Error de procesamiento de mensaje entrante: $e');
    }
  }
}

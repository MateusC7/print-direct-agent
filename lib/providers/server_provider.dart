import 'package:flutter/foundation.dart';
import '../services/server/http_server_service.dart';
import '../services/logger_service.dart';

/// Provider del estado del servidor HTTP/HTTPS local.
class ServerProvider extends ChangeNotifier {
  final HttpServerService _svc = HttpServerService.instance;

  final List<String> _logs = [];

  List<String> get logs => List.unmodifiable(_logs);
  ServerStatus get status => _svc.status;
  bool get isRunning => _svc.isRunning;
  String get lastError => _svc.lastError;

  ServerProvider() {
    _svc.onLog = _addLogEntry;
    _svc.onStatusChange = (_) => notifyListeners();
    LoggerService.onLog = (msg) => _addLogEntry(msg);
  }

  void _addLogEntry(String msg) {
    // Filtrar cualquier emoji residual para que la interfaz se mantenga 100% limpia
    final clean = msg.replaceAll(
      RegExp(r'[\u{1F300}-\u{1FAFF}]|[\u{2600}-\u{27BF}]|[\u{1F600}-\u{1F64F}]|[\u{1F680}-\u{1F6FF}]', unicode: true),
      '',
    ).replaceAll('  ', ' ').trim();

    final ts = _timestamp();
    final entry = '[$ts] $clean';
    if (_logs.isNotEmpty && _logs.last.contains(clean)) return; // Evitar duplicar
    _logs.add(entry);
    // Máximo 200 líneas en memoria
    if (_logs.length > 200) _logs.removeAt(0);
    notifyListeners();
  }

  void addLog(String msg) => _addLogEntry(msg);

  void clearLog() {
    _logs.clear();
    notifyListeners();
  }

  String _timestamp() {
    final now = DateTime.now();
    return '${_two(now.hour)}:${_two(now.minute)}:${_two(now.second)}';
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  Future<String> getLocalIp() => _svc.getLocalIp();
}

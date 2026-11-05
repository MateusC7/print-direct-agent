import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../settings_service.dart';
import '../logger_service.dart';
import 'cloud_relay_service.dart';
import '../../models/printer_model.dart';
import '../printer/printer_service.dart';

/// Servicio de Autodescubrimiento, Sincronización y Heartbeat con el Servidor.
/// Monitorea cambios de red y mantiene el hardware siempre sincronizado.
class OdooDeviceSyncService extends ChangeNotifier {
  OdooDeviceSyncService._();
  static final OdooDeviceSyncService instance = OdooDeviceSyncService._();

  Timer? _heartbeatTimer;
  String _lastKnownIp = '';
  bool _isSyncing = false;
  bool _isSynced = false;
  String _lastSyncMessage = '';
  DateTime? _lastSyncTime;
  PrinterService? _printerService;

  bool get isSynced => _isSynced;
  bool get isSyncing => _isSyncing;
  String get lastSyncMessage => _lastSyncMessage;
  DateTime? get lastSyncTime => _lastSyncTime;

  void init(PrinterService printerService) {
    _printerService = printerService;
  }

  /// Obtiene la IP local real del dispositivo en la red Wi-Fi/LAN.
  Future<String> getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback &&
              (addr.address.startsWith('192.168.') ||
               addr.address.startsWith('10.') ||
               addr.address.startsWith('172.'))) {
            return addr.address;
          }
        }
      }
      if (interfaces.isNotEmpty && interfaces.first.addresses.isNotEmpty) {
        return interfaces.first.addresses.first.address;
      }
    } catch (e) {
      debugPrint('Error obteniendo IP local: $e');
    }
    return '127.0.0.1';
  }

  /// Genera o recupera un identificador único persistente para este dispositivo.
  Future<String> getOrCreateDeviceUuid() async {
    final settings = SettingsService.instance;
    String uuid = settings.deviceUuid;
    if (uuid.isEmpty) {
      final String platformPrefix = defaultTargetPlatform == TargetPlatform.android
          ? 'android'
          : defaultTargetPlatform == TargetPlatform.iOS
              ? 'ios'
              : 'pc';
      uuid = 'box-$platformPrefix-${DateTime.now().millisecondsSinceEpoch}';
      await settings.setDeviceUuid(uuid);
    }
    return uuid;
  }

  /// Inicia el bucle de latido continuo cada 30 segundos.
  void startPeriodicHeartbeat({Duration interval = const Duration(seconds: 30)}) {
    stopPeriodicHeartbeat();
    _checkAndSync();

    _heartbeatTimer = Timer.periodic(interval, (_) async {
      await _checkAndSync();
    });
  }

  void stopPeriodicHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  Future<void> _checkAndSync() async {
    if (_isSyncing || _printerService == null) return;

    final currentIp = await getLocalIp();
    final ipChanged = _lastKnownIp.isNotEmpty && _lastKnownIp != currentIp;

    if (ipChanged) {
      LoggerService.info('🔄 [RED] IP local actualizada: $_lastKnownIp ➔ $currentIp');
    }

    final printers = await _printerService!.getAllPrinters();
    final res = await syncWithOdoo(printers: printers);

    if (res['success'] == true) {
      _lastKnownIp = currentIp;
      _isSynced = true;
      _lastSyncMessage = res['message'] ?? 'Sincronizado';
      _lastSyncTime = DateTime.now();
    } else {
      _isSynced = false;
      _lastSyncMessage = res['message'] ?? 'Error de sincronización';
    }
    notifyListeners();
  }

  /// Sincroniza explícitamente este dispositivo y sus impresoras con el servidor.
  Future<Map<String, dynamic>> syncWithOdoo({
    required List<PrinterModel> printers,
  }) async {
    final settings = SettingsService.instance;
    final String cleanUrl = settings.odooUrl.trim();
    if (cleanUrl.isEmpty) {
      return {'success': false, 'message': 'URL del servidor no configurada.'};
    }

    String baseUrl = cleanUrl;
    if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
      baseUrl = '${settings.odooProtocol}://$baseUrl';
    }
    while (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - 1);
    }

    _isSyncing = true;
    notifyListeners();

    final localIp = await getLocalIp();
    final uuid = await getOrCreateDeviceUuid();
    final deviceName = settings.deviceName.isNotEmpty
        ? settings.deviceName
        : (defaultTargetPlatform == TargetPlatform.android ? 'Tablet / Dispositivo Android' : 'Caja Local');
    final proxyUrl = 'http://$localIp:${settings.port}';

    final printersData = printers.map((p) => {
      'name': p.name,
      'type': p.type.name,
      'address': p.displayAddress,
    }).toList();

    final payload = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'identifier': uuid,
        'name': deviceName,
        'ip_url': proxyUrl,
        'token': settings.apiToken,
        'printers': printersData,
      },
      'id': DateTime.now().millisecondsSinceEpoch,
    };

    try {
      final response = await CloudRelayService.instance.signedPost(
        baseUrl,
        '/print_direct/register_agent',
        payload,
        timeout: const Duration(seconds: 8),
      );

      _isSyncing = false;

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        if (body.containsKey('result') && !body.containsKey('error')) {
          _isSynced = true;
          _lastSyncTime = DateTime.now();
          _lastSyncMessage = 'Dispositivo sincronizado con éxito.';
          notifyListeners();
          return {'success': true, 'message': _lastSyncMessage, 'data': body['result']};
        }
      }
      _isSynced = false;
      _lastSyncMessage = response.statusCode == 404
          ? 'No se pudo contactar al Sistema (HTTP 404). Revisa la dirección configurada.'
          : 'Servidor respondió con código: ${response.statusCode}';
      notifyListeners();
      return {'success': false, 'message': _lastSyncMessage};
    } catch (e) {
      _isSyncing = false;
      _isSynced = false;
      _lastSyncMessage = 'Error de conexión con el servidor: $e';
      notifyListeners();
      return {'success': false, 'message': _lastSyncMessage};
    }
  }
}

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/printer_model.dart';
import '../services/printer/printer_service.dart';
import '../services/printer/windows_printer_service.dart';
import '../services/printer/cups_printer_service.dart';
import '../services/printer/android_printer_service.dart';
import '../services/printer/network_printer_scanner.dart';
import '../services/server/http_server_service.dart';
import '../core/constants.dart';
import '../services/settings_service.dart';
import '../services/hardware/scale_service.dart';
import '../services/hardware/scanner_service.dart';

/// Provider de impresoras: lista, selección y acciones de impresión.
class PrinterProvider extends ChangeNotifier {
  late final PrinterService _service;

  List<PrinterModel> _printers = [];
  List<PrinterModel> _networkPrinters = [];
  List<PrinterModel> _iotDevices = [];
  PrinterModel? _selected;
  bool _loading = false;
  String? _error;

  List<PrinterModel> get printers => _printers;
  List<PrinterModel> get networkPrinters => _networkPrinters;
  List<PrinterModel> get iotDevices => _iotDevices;
  PrinterModel? get selected => _selected;
  bool get loading => _loading;
  String? get error => _error;

  PrinterProvider() {
    _iotDevices = SettingsService.instance.savedIotDevices;
    _networkPrinters = SettingsService.instance.savedNetworkPrinters;
    // Seleccionar el servicio correcto por plataforma
    if (Platform.isWindows) {
      _service = WindowsPrinterService();
    } else if (Platform.isAndroid || Platform.isIOS) {
      _service = AndroidPrinterService();
    } else {
      _service = CupsPrinterService();
    }

    // Escuchar a los servicios IoT para propagar cambios de estado
    ScaleService.instance.addListener(notifyListeners);
    ScannerService.instance.addListener(notifyListeners);

    // Iniciar conexiones IoT en segundo plano
    _updateIotConnections();
  }

  PrinterService get service => _service;

  static bool _backgroundPermissionsAsked = false;

  /// Pide (una sola vez por sesión) el permiso de notificaciones y la
  /// exclusión de ahorro de batería para que Android no mate el servicio de
  /// impresión en segundo plano. Un rechazo nunca bloquea la app.
  Future<void> _requestBackgroundPermissions() async {
    if (_backgroundPermissionsAsked) return;
    _backgroundPermissionsAsked = true;
    try {
      await Permission.notification.request();
      if (!await Permission.ignoreBatteryOptimizations.isGranted) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    } catch (_) {}
  }

  // ── Listar impresoras ─────────────────────────────────────────────
  Future<void> refresh() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      if (Platform.isAndroid) {
        // Solicitar permisos de Bluetooth a nivel de sistema operativo (solo Conectar para dispositivos vinculados)
        await Permission.bluetoothConnect.request();
        await _requestBackgroundPermissions();
      }

      final nativePrinters = await _service.listPrinters();
      final merged = <String, PrinterModel>{};
      for (final p in [...nativePrinters, ..._networkPrinters, ..._iotDevices]) {
        merged.putIfAbsent(p.id, () => p);
      }
      _printers = merged.values.toList();
      
      // Cargar la impresora seleccionada por defecto si no hay selección actual
      if (_selected == null) {
        final defId = SettingsService.instance.defaultPrinterId;
        if (defId.isNotEmpty) {
          try {
            _selected = _printers.firstWhere((p) => p.id == defId);
          } catch (_) {}
        }
      }

      // Si aún no hay selección, auto-seleccionar la impresora del sistema como fallback
      if (_selected == null) {
        try {
          _selected = _printers.firstWhere((p) => p.address == 'system_print');
        } catch (_) {}
      }

      // Si la seleccionada ya no existe, limpiar
      if (_selected != null && !_printers.any((p) => p.id == _selected!.id)) {
        _selected = null;
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ── Seleccionar impresora ─────────────────────────────────────────
  void select(PrinterModel printer) {
    _selected = printer;
    SettingsService.instance.setDefaultPrinterId(printer.id);
    notifyListeners();
  }

  // ── Añadir impresora de red (multiplataforma) ───────────────────
  Future<void> addNetworkPrinter(String name, String ip, int port) async {
    await addSavedPrinter(PrinterModel(
      name: name.isEmpty ? '$ip:$port' : name,
      type: PrinterType.network,
      address: ip,
      port: port,
    ));
  }

  /// Guarda una impresora (red o Bluetooth) sin duplicar la misma dirección.
  Future<void> addSavedPrinter(PrinterModel printer) async {
    if (_networkPrinters.any((p) => p.id == printer.id)) return;
    _networkPrinters.add(printer);
    await SettingsService.instance.saveNetworkPrinters(_networkPrinters);
    await refresh();
  }

  // ── Búsqueda automática (sin popups) ─────────────────────────────
  final NetworkPrinterScanner _scanner = NetworkPrinterScanner();

  /// Busca impresoras ESC/POS (puerto 9100) en la subred local y devuelve las
  /// que aún no están guardadas.
  Future<List<PrinterModel>> scanNetworkPrinters({
    void Function(PrinterModel printer)? onFound,
  }) async {
    final localIp = await HttpServerService.instance.getLocalIp();
    final hosts = NetworkPrinterScanner.subnetHosts(localIp);
    final known = _networkPrinters
        .where((p) => p.type == PrinterType.network)
        .map((p) => p.address)
        .toSet();
    final found = <PrinterModel>[];
    await _scanner.scan(
      hosts: hosts.where((h) => !known.contains(h)).toList(),
      onFound: (host) {
        final printer = PrinterModel(
          name: 'Impresora $host',
          type: PrinterType.network,
          address: host,
          port: AppConstants.defaultNetworkPort,
        );
        found.add(printer);
        onFound?.call(printer);
      },
    );
    return found;
  }

  /// Busca impresoras Bluetooth cercanas (solo Android) que aún no estén
  /// guardadas ni emparejadas ya listadas.
  Future<List<PrinterModel>> discoverBluetoothPrinters() async {
    final service = _service;
    if (service is! AndroidPrinterService) return const [];
    if (Platform.isAndroid) {
      await Permission.bluetoothScan.request();
      await Permission.bluetoothConnect.request();
      if (await Permission.bluetoothScan.isDenied) {
        // Android ≤ 11 usa la ubicación para buscar dispositivos cercanos.
        await Permission.locationWhenInUse.request();
      }
    }
    final nearby = await service.discoverBluetoothPrinters();
    final known = _printers.map((p) => p.id).toSet()
      ..addAll(_networkPrinters.map((p) => p.id));
    return nearby.where((p) => !known.contains(p.id)).toList();
  }

  // ── Eliminar impresora de red (multiplataforma) ─────────────────
  Future<void> removeNetworkPrinter(PrinterModel printer) async {
    _networkPrinters.removeWhere((p) => p.id == printer.id);
    await SettingsService.instance.saveNetworkPrinters(_networkPrinters);
    await refresh();
  }

  // ── Añadir / Eliminar Dispositivo IoT ──────────────────────────────
  Future<void> addIotDevice(PrinterModel device) async {
    _iotDevices.add(device);
    await SettingsService.instance.saveIotDevices(_iotDevices);
    await _updateIotConnections();
    await refresh();
  }

  Future<void> removeIotDevice(PrinterModel device) async {
    _iotDevices.removeWhere((d) => d.id == device.id);
    await SettingsService.instance.saveIotDevices(_iotDevices);
    await _updateIotConnections();
    await refresh();
  }

  // ── Actualizar conexiones de dispositivos IoT ───────────────────────
  Future<void> _updateIotConnections() async {
    // Balanza
    final scaleDevices = _iotDevices.where((d) => d.type == PrinterType.scale).toList();
    if (scaleDevices.isNotEmpty) {
      final scale = scaleDevices.first;
      if (scale.address != null && scale.address!.isNotEmpty) {
        if (!ScaleService.instance.isConnected) {
          debugPrint('[PrinterProvider] Conectando a báscula en ${scale.address}...');
          await ScaleService.instance.connect(scale.address!);
        }
      }
    } else {
      if (ScaleService.instance.isConnected) {
        debugPrint('[PrinterProvider] Desconectando báscula (eliminada)...');
        ScaleService.instance.disconnect();
      }
    }

    // Lector de códigos
    final scannerDevices = _iotDevices.where((d) => d.type == PrinterType.scanner).toList();
    if (scannerDevices.isNotEmpty) {
      final scanner = scannerDevices.first;
      if (scanner.address != null && scanner.address!.isNotEmpty) {
        if (!ScannerService.instance.isConnected) {
          debugPrint('[PrinterProvider] Conectando a lector en ${scanner.address}...');
          await ScannerService.instance.connect(scanner.address!);
        }
      }
    } else {
      if (ScannerService.instance.isConnected) {
        debugPrint('[PrinterProvider] Desconectando lector (eliminado)...');
        ScannerService.instance.disconnect();
      }
    }
  }

  // ── Imprimir prueba ───────────────────────────────────────────────
  Future<PrintResult> printTest() async {
    if (_selected == null) {
      return PrintResult.error('No hay impresora seleccionada');
    }
    return _service.printTest(_selected!);
  }

  // ── Imprimir RAW ──────────────────────────────────────────────────
  Future<PrintResult> printRaw({
    required PrinterModel printer,
    required List<int> bytes,
    String? rawType,
  }) async {
    return _service.printRaw(
      printer: printer,
      bytes: bytes,
      rawType: rawType,
    );
  }

  @override
  void dispose() {
    ScaleService.instance.removeListener(notifyListeners);
    ScannerService.instance.removeListener(notifyListeners);
    super.dispose();
  }
}

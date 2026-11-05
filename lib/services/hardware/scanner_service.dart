import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'android_usb_service.dart';
import '../server/websocket_manager.dart';

class ScannerService extends ChangeNotifier {
  static final ScannerService instance = ScannerService._internal();
  ScannerService._internal();

  String _lastBarcode = '';
  bool _isConnected = false;

  String get lastBarcode => _lastBarcode;
  bool get isConnected => _isConnected;

  Future<List<String>> getAvailablePorts() async {
    if (Platform.isAndroid) {
      return await AndroidUsbService.instance.getAvailableDevices();
    }
    if (Platform.isMacOS || Platform.isLinux) {
      try {
        final devDir = Directory('/dev');
        if (devDir.existsSync()) {
          final entities = devDir.listSync();
          final ports = <String>[];
          for (final e in entities) {
            final name = e.path;
            if (name.contains('cu.usb') ||
                name.contains('tty.usb') ||
                name.contains('ttyUSB') ||
                name.contains('ttyACM')) {
              ports.add(name);
            }
          }
          if (ports.isNotEmpty) return ports;
        }
      } catch (_) {}
      return [
        '/dev/cu.usbserial',
        '/dev/cu.usbmodem',
        '/dev/tty.usbserial',
        'Lector USB / Teclado HID',
      ];
    }
    return ['COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'Lector USB / Teclado'];
  }

  Future<bool> connect(String portName) async {
    try {
      disconnect();
      
      if (Platform.isAndroid) {
        final success = await AndroidUsbService.instance.connect(portName, _parseData);
        if (success) {
          _isConnected = true;
          notifyListeners();
        }
        return success;
      }
      
      _isConnected = true;
      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }

  void disconnect() {
    if (Platform.isAndroid) {
      AndroidUsbService.instance.disconnect();
    }
    
    _isConnected = false;
    notifyListeners();
  }

  String _buffer = '';

  void _parseData(Uint8List data) {
    final str = utf8.decode(data, allowMalformed: true);
    _buffer += str;

    // Escáneres típicamente terminan con \n o \r
    if (_buffer.contains('\n') || _buffer.contains('\r')) {
      final barcode = _buffer.replaceAll('\n', '').replaceAll('\r', '').trim();
      if (barcode.isNotEmpty) {
        _lastBarcode = barcode;
        notifyListeners();
        print('[ScannerService] Scanned: $_lastBarcode');
        WebSocketManager.instance.broadcastEvent('barcode_scanned', {
          'barcode': barcode,
        });
      }
      _buffer = '';
    }
  }

  /// Consume el código para que Odoo lo recoja una sola vez
  String consumeBarcode() {
    final code = _lastBarcode;
    _lastBarcode = '';
    return code;
  }

  /// Simula la lectura de un código de barras de forma manual para pruebas sin hardware.
  void simulateScan(String barcode) {
    if (barcode.isNotEmpty) {
      _lastBarcode = barcode;
      notifyListeners();
      print('[ScannerService] Simulated Scan: $_lastBarcode');
      WebSocketManager.instance.broadcastEvent('barcode_scanned', {
        'barcode': barcode,
      });
    }
  }
}

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'android_usb_service.dart';
import '../server/websocket_manager.dart';
import '../settings_service.dart';

class ScaleService extends ChangeNotifier {
  static final ScaleService instance = ScaleService._internal();
  ScaleService._internal();

  double _currentWeight = 0.0;
  String _unit = 'kg';
  bool _isConnected = false;

  double get currentWeight => _currentWeight;
  String get unit => _unit;
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
        'Báscula USB / Serie Virtual',
      ];
    }
    return ['COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'Puerto Serie Virtual'];
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
    _currentWeight = 0.0;
    notifyListeners();
  }

  void _parseData(Uint8List data) {
    final protocol = SettingsService.instance.scaleProtocol;
    final parsed = _decodeWeight(data, protocol);

    if (parsed != null && parsed != _currentWeight) {
      _currentWeight = parsed;
      notifyListeners();
      WebSocketManager.instance.broadcastEvent('weight_changed', {
        'weight': parsed,
        'unit': _unit,
      });
    }
  }

  double? _decodeWeight(Uint8List data, String protocol) {
    final str = String.fromCharCodes(data).trim();
    if (str.isEmpty) return null;

    switch (protocol) {
      case 'cas':
        // CAS format: e.g. "US , GS ,    0.350 kg\r\n"
        final parts = str.split(',');
        if (parts.length >= 3) {
          final weightPart = parts[2].trim();
          final match = RegExp(r'[-+]?\d*\.?\d+').firstMatch(weightPart);
          if (match != null) {
            return double.tryParse(match.group(0)!);
          }
        }
        break;

      case 'toledo':
        // Toledo format: STX [Status A-C] [Weight 6 chars] [Tare 6 chars] CR
        final cleanStr = str.replaceAll(RegExp(r'[^\d\.\-]'), '').trim();
        if (cleanStr.isNotEmpty) {
          final match = RegExp(r'[-+]?\d*\.?\d+').firstMatch(cleanStr);
          if (match != null) {
            return double.tryParse(match.group(0)!);
          }
        }
        break;

      case 'dibal':
        // Dibal format: e.g. "$001450k1\r\n" -> 1.450 kg
        if (str.startsWith('\$') && str.length >= 6) {
          final digits = str.replaceAll(RegExp(r'[^\d]'), '');
          final val = double.tryParse(digits);
          if (val != null) {
            return val / 1000.0; // Asume 3 decimales
          }
        }
        break;

      case 'generic':
      default:
        final RegExp regex = RegExp(r'[-+]?\d*\.?\d+');
        final match = regex.firstMatch(str);
        if (match != null) {
          final weightStr = match.group(0);
          if (weightStr != null) {
            return double.tryParse(weightStr);
          }
        }
        break;
    }
    return null;
  }

  /// Simula el peso de la báscula de forma manual para pruebas sin hardware.
  void simulateWeight(double weight) {
    _currentWeight = weight;
    notifyListeners();
    WebSocketManager.instance.broadcastEvent('weight_changed', {
      'weight': weight,
      'unit': _unit,
    });
  }
}

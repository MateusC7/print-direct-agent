import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:usb_serial/usb_serial.dart';

class AndroidUsbService {
  static final AndroidUsbService instance = AndroidUsbService._internal();
  AndroidUsbService._internal();

  UsbPort? _port;
  StreamSubscription? _subscription;

  Future<List<String>> getAvailableDevices() async {
    try {
      final devices = await UsbSerial.listDevices();
      return devices.map((d) => '${d.vid}:${d.pid} - ${d.productName ?? 'USB Device'}').toList();
    } catch (e) {
      print('[AndroidUsbService] Error listando dispositivos: $e');
      return [];
    }
  }

  Future<bool> connect(String identifier, Function(Uint8List) onData) async {
    try {
      disconnect();

      // Buscar el dispositivo por VID:PID
      final parts = identifier.split(' - ')[0].split(':');
      if (parts.length != 2) return false;
      
      final vid = int.tryParse(parts[0]);
      final pid = int.tryParse(parts[1]);

      final devices = await UsbSerial.listDevices();
      final device = devices.firstWhere(
        (d) => d.vid == vid && d.pid == pid, 
        orElse: () => throw Exception('Dispositivo no encontrado')
      );

      _port = await device.create();
      if (_port == null) return false;

      final openResult = await _port!.open();
      if (!openResult) {
        print('[AndroidUsbService] Error abriendo puerto USB');
        return false;
      }

      await _port!.setDTR(true);
      await _port!.setRTS(true);
      await _port!.setPortParameters(
        9600,
        UsbPort.DATABITS_8,
        UsbPort.STOPBITS_1,
        UsbPort.PARITY_NONE,
      );

      _subscription = _port!.inputStream?.listen((data) {
        onData(data);
      });

      print('[AndroidUsbService] Conectado a USB: $identifier');
      return true;
    } catch (e) {
      print('[AndroidUsbService] Excepción al conectar: $e');
      return false;
    }
  }

  void disconnect() {
    _subscription?.cancel();
    if (_port != null) {
      _port!.close();
      _port = null;
    }
  }
}

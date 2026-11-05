import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../models/printer_model.dart';
import '../../utils/image_utils.dart';
import 'printer_service.dart';

/// Motor de impresión para Android.
/// Soporta:
///   1. Impresoras de Red (TCP/IP puerto 9100 ESC/POS)
///   2. Bluetooth SPP (via MethodChannel nativo)
///   3. Sunmi built-in (via MethodChannel nativo)
class AndroidPrinterService implements PrinterService {
  static const _btChannel =
      MethodChannel('com.softwarerestaurante.print/bluetooth');
  static const _sunmiChannel =
      MethodChannel('com.softwarerestaurante.print/sunmi');

  /// Standard ESC/POS drawer kick (ESC p, pin 2); works on old and new Sunmi hardware.
  static const List<int> sunmiCashDrawerPulse = [0x1B, 0x70, 0x00, 0x32, 0xFA];

  /// Abre los Ajustes de Impresión nativos de Android (Servicios Canon, HP, Epson, Mopria)
  static Future<void> openPrintSettings() async {
    if (Platform.isAndroid) {
      try {
        await _btChannel.invokeMethod('openPrintSettings');
      } catch (_) {}
    }
  }

  /// Busca impresoras Bluetooth cercanas, emparejadas o no (hasta ~12 s).
  /// No abre diálogos: la conexión posterior usa un socket inseguro cuando
  /// el dispositivo no está emparejado.
  Future<List<PrinterModel>> discoverBluetoothPrinters() async {
    if (!Platform.isAndroid) return const [];
    try {
      final list = await _btChannel.invokeMethod<List>('discoverDevices');
      return [
        for (final device in list ?? const [])
          PrinterModel(
            name: (device as Map)['name'] as String? ?? 'BT Device',
            type: PrinterType.bluetooth,
            address: device['address'] as String?,
          ),
      ];
    } on PlatformException {
      return const [];
    }
  }

  @override
  Future<List<PrinterModel>> listPrinters() async {
    final printers = <PrinterModel>[];

    // ── Impresora del Sistema Android (Canon, HP, Epson, Mopria) ───────
    printers.add(const PrinterModel(
      name: 'Impresora Canon / Sistema Android (PDF)',
      type: PrinterType.local,
      address: 'system_print',
    ));

    // ── Bluetooth ──────────────────────────────────────────────────────
    try {
      final btList = await _btChannel.invokeMethod<List>('getPairedDevices');
      if (btList != null) {
        for (final device in btList) {
          final map = device as Map;
          printers.add(PrinterModel(
            name: map['name'] as String? ?? 'BT Device',
            type: PrinterType.bluetooth,
            address: map['address'] as String?,
          ));
        }
      }
    } on PlatformException {
      // Bluetooth no disponible o permiso denegado
    }

    // ── Sunmi ─────────────────────────────────────────────────────────
    try {
      final hasSunmi =
          await _sunmiChannel.invokeMethod<bool>('isAvailable') ?? false;
      if (hasSunmi) {
        printers.add(const PrinterModel(
          name: 'Sunmi Built-in Printer',
          type: PrinterType.sunmi,
          isSunmi: true,
        ));
      }
    } on PlatformException {
      // Sunmi SDK no disponible
    }

    return printers;
  }

  @override
  Future<PrintResult> printRaw({
    required PrinterModel printer,
    required List<int> bytes,
    String? rawType,
    bool openCashbox = false,
  }) async {
    List<int> effectiveBytes = bytes;

    // Si recibimos una imagen PNG/JPEG o rawType == 'image', convertir a ESC/POS Raster para Network/BT/Sunmi
    if (rawType == 'image' || ImageUtils.isImageBytes(bytes)) {
      if (printer.address == 'system_print' ||
          printer.type == PrinterType.local) {
        final pdfBytes = await ImageUtils.convertImageToPdf(bytes);
        if (pdfBytes != null) {
          effectiveBytes = pdfBytes;
          rawType = 'pdf';
        }
      } else {
        final raster = ImageUtils.convertImageToEscPosRaster(bytes);
        if (raster != null) {
          effectiveBytes = raster;
          rawType = 'raw';
        }
      }
    }

    if (printer.address == 'system_print') {
      return _printSystem(effectiveBytes, rawType);
    }
    switch (printer.type) {
      case PrinterType.network:
        return _printTcp(printer, effectiveBytes);
      case PrinterType.bluetooth:
        return _printBluetooth(printer, effectiveBytes);
      case PrinterType.sunmi:
        return _printSunmi(
          openCashbox ? [...sunmiCashDrawerPulse, ...effectiveBytes] : effectiveBytes,
        );
      case PrinterType.local:
        return _printSystem(effectiveBytes, rawType);
      case PrinterType.scale:
      case PrinterType.scanner:
      case PrinterType.display:
        return PrintResult.error(
            'Not supported on Android for direct raw printing');
    }
  }

  // ── TCP/IP ──────────────────────────────────────────────────────────
  Future<PrintResult> _printTcp(PrinterModel printer, List<int> bytes) async {
    try {
      String host = printer.address ?? '';
      int port = printer.port ?? 9100;

      if (host.isEmpty) {
        return PrintResult.error(
            'No IP address configured for ${printer.name}');
      }

      if (host.contains(':')) {
        final parts = host.split(':');
        host = parts[0];
        if (parts.length > 1) {
          port = int.tryParse(parts[1]) ?? port;
        }
      }

      final socket =
          await Socket.connect(host, port, timeout: const Duration(seconds: 5));
      socket.add(bytes);
      await socket.flush();
      await socket.close();
      return PrintResult.ok(
          'TCP/IP sent to $host:$port (${bytes.length} bytes)');
    } on SocketException catch (e) {
      return PrintResult.error('TCP error: ${e.message}');
    } catch (e) {
      return PrintResult.error('Network print error: $e');
    }
  }

  // ── Bluetooth ───────────────────────────────────────────────────────
  Future<PrintResult> _printBluetooth(
      PrinterModel printer, List<int> bytes) async {
    try {
      final result = await _btChannel.invokeMethod<bool>('printRaw', {
        'address': printer.address,
        // Native side reads byte[]; a plain List<int> would arrive as ArrayList.
        'data': bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
      });
      if (result == true) {
        return PrintResult.ok('Bluetooth sent to ${printer.address}');
      }
      return PrintResult.error('Bluetooth print returned false');
    } on PlatformException catch (e) {
      return PrintResult.error('Bluetooth error: ${e.message}');
    }
  }

  // ── Sunmi ────────────────────────────────────────────────────────────
  Future<PrintResult> _printSunmi(List<int> bytes) async {
    try {
      // The standard codec only maps Uint8List to byte[]; a plain List<int> arrives as ArrayList.
      final result = await _sunmiChannel.invokeMethod<bool>('printRaw', {
        'data': bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
      });
      if (result == true) {
        return PrintResult.ok('Sunmi: printed successfully');
      }
      return PrintResult.error('Sunmi print returned false');
    } on PlatformException catch (e) {
      return PrintResult.error('Sunmi error: ${e.message}');
    }
  }

  @override
  Future<PrintResult> printTest(PrinterModel printer) async {
    final List<int> testData = _buildTestTicket(printer.name);
    return printRaw(printer: printer, bytes: testData, rawType: 'raw');
  }

  List<int> _buildTestTicket(String printerName) {
    const esc = 0x1B;
    const gs = 0x1D;
    return [
      esc,
      0x40,
      esc,
      0x74,
      0x02,
      esc,
      0x61,
      0x01,
      esc,
      0x21,
      0x10,
      ...('================================\n'.codeUnits),
      ...('SoftwareRestaurante\n'.codeUnits),
      ...('Agente de Impresion v2.0\n'.codeUnits),
      ...('================================\n'.codeUnits),
      esc,
      0x21,
      0x00,
      esc,
      0x61,
      0x00,
      ...('Impresora: '.codeUnits),
      ...(printerName.substring(0, printerName.length.clamp(0, 28)).codeUnits),
      0x0A,
      ...('Estado: CONEXION EXITOSA\n'.codeUnits),
      0x0A,
      0x0A,
      0x0A,
      0x0A,
      gs,
      0x56,
      0x42,
      0x00,
    ];
  }

  // ── Imprimir via System Print (PDF Dialog) ──────────────────────────
  Future<PrintResult> _printSystem(List<int> bytes, String? rawType) async {
    try {
      List<int> pdfBytes;

      // Detectar si ya es un PDF
      final isPdf = bytes.length > 4 &&
          bytes[0] == 0x25 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x44 &&
          bytes[3] == 0x46; // %PDF

      if (isPdf || rawType == 'pdf') {
        pdfBytes = bytes;
      } else {
        // Es texto o ESC/POS, limpiarlo y convertir a PDF
        final text = _cleanEscPos(bytes);
        pdfBytes = await _convertTextToPdf(text);
      }

      final result = await _btChannel.invokeMethod<bool>('printSystem', {
        'data': Uint8List.fromList(pdfBytes),
        'jobName': 'Ticket de Venta',
      });

      if (result == true) {
        return PrintResult.ok('Sistema de impresión lanzado');
      }
      return PrintResult.error('No se pudo abrir el diálogo de impresión');
    } catch (e) {
      return PrintResult.error('Error de impresión del sistema: $e');
    }
  }

  String _cleanEscPos(List<int> bytes) {
    final cleanBytes = <int>[];
    int i = 0;
    while (i < bytes.length) {
      final b = bytes[i];
      if (b == 0x1B || b == 0x1D) {
        // ESC or GS, skip cmd and common args
        i++;
        if (i < bytes.length) {
          final cmd = bytes[i];
          if (cmd == 0x40) {
            i++;
          } else if (cmd == 0x21 ||
              cmd == 0x61 ||
              cmd == 0x74 ||
              cmd == 0x4A ||
              cmd == 0x64) {
            i += 2;
          } else if (cmd == 0x56 || cmd == 0x69 || cmd == 0x6D) {
            i += 2;
          } else {
            i++;
          }
        }
      } else {
        cleanBytes.add(b);
        i++;
      }
    }
    try {
      return utf8.decode(cleanBytes, allowMalformed: true);
    } catch (_) {
      return String.fromCharCodes(cleanBytes);
    }
  }

  Future<List<int>> _convertTextToPdf(String text) async {
    final pdf = pw.Document();
    final pageFormat = PdfPageFormat.roll80.copyWith(
      marginTop: 10,
      marginBottom: 10,
      marginLeft: 10,
      marginRight: 10,
    );

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (pw.Context context) {
          return pw.Text(
            text,
            style: pw.TextStyle(
              fontSize: 9,
              font: pw.Font.courier(),
            ),
          );
        },
      ),
    );
    return pdf.save();
  }

  @override
  Future<String> getPrinterStatus(String printerName) async {
    return 'online';
  }
}

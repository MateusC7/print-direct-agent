import 'dart:io';
import '../../models/printer_model.dart';
import '../../utils/image_utils.dart';
import 'printer_service.dart';
import 'print_route.dart';

/// Motor de impresión para macOS y Linux via CUPS.
/// Utiliza comandos nativos del sistema: lpstat, lp, lpr.
class CupsPrinterService implements PrinterService {
  /// Lista de rutas candidatas para los binarios de CUPS en macOS / Linux
  static const List<String> _lpstatPaths = [
    'lpstat',
    '/usr/bin/lpstat',
    '/usr/sbin/lpstat',
    '/bin/lpstat'
  ];
  static const List<String> _lpPaths = [
    'lp',
    '/usr/bin/lp',
    '/usr/sbin/lp',
    '/bin/lp'
  ];
  static const List<String> _lprPaths = [
    'lpr',
    '/usr/bin/lpr',
    '/usr/sbin/lpr',
    '/bin/lpr'
  ];

  /// Ejecuta un comando buscando en las rutas conocidas
  Future<ProcessResult?> _runCommand(
      List<String> candidatePaths, List<String> args) async {
    for (final cmd in candidatePaths) {
      try {
        final result = await Process.run(cmd, args,
            stdoutEncoding: const SystemEncoding());
        if (result.exitCode == 0 ||
            result.stdout.toString().isNotEmpty ||
            result.stderr.toString().isNotEmpty) {
          return result;
        }
      } catch (_) {
        // Intenta la siguiente ruta si el binario no está en PATH
      }
    }
    return null;
  }

  @override
  Future<List<PrinterModel>> listPrinters() async {
    final printers = <PrinterModel>[];
    final seenNames = <String>{};

    try {
      // 1. Método principal en macOS: 'lpstat -e' devuelve la lista exacta de impresoras
      final resEnum = await _runCommand(_lpstatPaths, ['-e']);
      if (resEnum != null && resEnum.exitCode == 0) {
        final out = resEnum.stdout as String;
        for (final line in out.split('\n')) {
          final name = line.trim();
          if (name.isNotEmpty && !seenNames.contains(name)) {
            seenNames.add(name);
            printers.add(PrinterModel(name: name, type: PrinterType.local));
          }
        }
      }

      // 2. Si 'lpstat -e' no devolvió impresoras, usar 'lpstat -p -d'
      if (printers.isEmpty) {
        final result = await _runCommand(_lpstatPaths, ['-p', '-d']);
        if (result != null && result.exitCode == 0) {
          final stdout = result.stdout as String;
          for (final line in stdout.split('\n')) {
            final trimmed = line.trim();
            // Soporte multilenguaje: "printer X is idle", "impresora X está inactiva", "la impresora X..."
            if (trimmed.startsWith('printer ') ||
                trimmed.startsWith('impresora ') ||
                trimmed.startsWith('la impresora ')) {
              final words = trimmed.split(' ');
              String? name;
              if (trimmed.startsWith('la impresora ') && words.length >= 3) {
                name = words[2].trim();
              } else if (words.length >= 2) {
                name = words[1].trim();
              }
              if (name != null &&
                  name.isNotEmpty &&
                  !seenNames.contains(name)) {
                seenNames.add(name);
                printers.add(PrinterModel(name: name, type: PrinterType.local));
              }
            }
          }
        }
      }

      // 3. Fallback: 'lpstat -a' (impresoras aceptando peticiones)
      if (printers.isEmpty) {
        final res2 = await _runCommand(_lpstatPaths, ['-a']);
        if (res2 != null && res2.exitCode == 0) {
          final out = res2.stdout as String;
          for (final line in out.split('\n')) {
            final parts = line.split(' ');
            if (parts.isNotEmpty) {
              final name = parts.first.trim();
              if (name.isNotEmpty && !seenNames.contains(name)) {
                seenNames.add(name);
                printers.add(PrinterModel(name: name, type: PrinterType.local));
              }
            }
          }
        }
      }
    } catch (_) {
      // CUPS no disponible o sin impresoras
    }

    // Si no hay impresoras físicas configuradas en CUPS aún, proveer impresora del sistema
    // para permitir vinculación inicial en Odoo y pruebas del agente
    if (printers.isEmpty) {
      printers.add(
        PrinterModel(
          name: 'Impresora del Sistema (PDF / Virtual)',
          type: PrinterType.local,
          address: 'system_print',
        ),
      );
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
    try {
      const pulse = [0x1B, 0x70, 0x00, 0x19, 0xFA];
      if (rawType == 'image' || ImageUtils.isImageBytes(bytes)) {
        if (selectPrintRoute(printerType: printer.type, isImage: true) ==
            PrintRoute.driver) {
          final pdfBytes = await ImageUtils.convertImageToPdf(bytes);
          if (pdfBytes != null) {
            bytes = pdfBytes;
            rawType = 'pdf';
          }
        } else {
          final raster = ImageUtils.convertImageToEscPosRaster(bytes);
          if (raster != null) {
            bytes = raster;
            rawType = 'raw';
          }
        }
      }

      if (printer.type == PrinterType.network) {
        return await _printTcp(
            printer, openCashbox ? [...pulse, ...bytes] : bytes);
      }

      if (openCashbox) {
        final pulseFile = await File(
          '${Directory.systemTemp.path}/sr_pulse_${DateTime.now().millisecondsSinceEpoch}.bin',
        ).writeAsBytes(pulse);
        try {
          await _runCommand(
              _lpPaths, ['-d', printer.name, '-o', 'raw', pulseFile.path]);
        } finally {
          Future.delayed(const Duration(seconds: 5), () {
            if (pulseFile.existsSync()) pulseFile.deleteSync();
          });
        }
      }

      // Detectar si el archivo es un documento PDF
      final isPdf = (rawType == 'pdf') ||
          (bytes.length > 4 &&
              bytes[0] == 0x25 &&
              bytes[1] == 0x50 &&
              bytes[2] == 0x44 &&
              bytes[3] == 0x46);

      final extension = isPdf ? 'pdf' : 'bin';

      // Crear archivo temporal con identificador único
      final tmp = await File(
              '${Directory.systemTemp.path}/sr_print_${DateTime.now().millisecondsSinceEpoch}.$extension')
          .writeAsBytes(bytes);

      try {
        final List<String> args;
        if (isPdf) {
          // Para PDF (A4/Carta), CUPS formatea y rasteriza el documento
          args = ['-d', printer.name, tmp.path];
        } else {
          // Para comandos RAW directos (ESC/POS, ZPL, cajón monedero), se usa '-o raw'
          args = ['-d', printer.name, '-o', 'raw', tmp.path];
        }

        final result = await _runCommand(_lpPaths, args);

        if (result != null && result.exitCode == 0) {
          return PrintResult.ok('CUPS enviado con éxito: ${result.stdout}');
        }

        // Fallback usando 'lpr' si 'lp' no está disponible o falló
        final List<String> lprArgs;
        if (isPdf) {
          lprArgs = ['-P', printer.name, tmp.path];
        } else {
          lprArgs = [
            '-P',
            printer.name,
            '-l',
            tmp.path
          ]; // '-l' = raw binary mode
        }

        final lprResult = await _runCommand(_lprPaths, lprArgs);
        if (lprResult != null && lprResult.exitCode == 0) {
          return PrintResult.ok(
              'CUPS (vía lpr) enviado con éxito: ${lprResult.stdout}');
        }

        final errMsg = result?.stderr.toString().trim() ??
            lprResult?.stderr.toString().trim() ??
            'Error ejecutando lp/lpr en CUPS';
        return PrintResult.error('Error CUPS: $errMsg');
      } finally {
        // Borrar archivo temporal tras 5 segundos
        Future.delayed(const Duration(seconds: 5), () {
          try {
            if (tmp.existsSync()) {
              tmp.deleteSync();
            }
          } catch (_) {}
        });
      }
    } catch (e) {
      return PrintResult.error('Excepción en CUPS: $e');
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
      esc, 0x40, // Reset
      esc, 0x74, 0x02, // Code page Latin
      esc, 0x61, 0x01, // Centrar
      esc, 0x21, 0x10, // Doble altura
      ...('================================\n'.codeUnits),
      ...('SoftwareRestaurante\n'.codeUnits),
      ...('Agente de Impresion v2.0\n'.codeUnits),
      ...('================================\n'.codeUnits),
      esc, 0x21, 0x00, // Normal
      esc, 0x61, 0x00, // Izquierda
      ...('Impresora: '.codeUnits),
      ...(printerName.substring(0, printerName.length.clamp(0, 30)).codeUnits),
      0x0A,
      ...('SO: macOS / Linux (CUPS Native)\n'.codeUnits),
      ...('Estado: CONEXION EXITOSA\n'.codeUnits),
      0x0A, 0x0A, 0x0A, 0x0A,
      gs, 0x56, 0x42, 0x00, // Corte de papel
    ];
  }

  @override
  Future<String> getPrinterStatus(String printerName) async {
    try {
      final result = await _runCommand(_lpstatPaths, ['-p', printerName]);
      if (result != null && result.exitCode == 0) {
        final out = result.stdout as String;
        if (out.contains('disabled') || out.contains('deshabilitada')) {
          return 'offline';
        }
        if (out.contains('paused') || out.contains('pausada')) {
          return 'paused';
        }
        return 'online';
      }
    } catch (_) {}
    return 'unknown';
  }

  /// Envía los bytes crudos a través de un TCP Socket directo a la impresora de red
  Future<PrintResult> _printTcp(PrinterModel printer, List<int> bytes) async {
    try {
      final host = printer.address;
      final port = printer.port ?? 9100;

      if (host == null || host.isEmpty) {
        return PrintResult.error('No hay IP configurada para ${printer.name}');
      }

      final socket =
          await Socket.connect(host, port, timeout: const Duration(seconds: 5));
      socket.add(bytes);
      await socket.flush();
      await socket.close();
      return PrintResult.ok(
          'TCP/IP enviado a $host:$port (${bytes.length} bytes)');
    } on SocketException catch (e) {
      return PrintResult.error('Error TCP: ${e.message}');
    } catch (e) {
      return PrintResult.error('Error de impresión en red: $e');
    }
  }
}

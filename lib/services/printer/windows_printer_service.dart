// ignore_for_file: non_constant_identifier_names, constant_identifier_names
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:win32/win32.dart';
import '../../models/printer_model.dart';
import '../../utils/image_utils.dart';
import 'printer_service.dart';
import 'print_route.dart';

// Constantes de estado de impresora de la API Win32
const int PRINTER_STATUS_PAUSED = 0x00000001;
const int PRINTER_STATUS_ERROR = 0x00000002;
const int PRINTER_STATUS_PAPER_JAM = 0x00000008;
const int PRINTER_STATUS_PAPER_OUT = 0x00000010;
const int PRINTER_STATUS_OFFLINE = 0x00000080;
const int PRINTER_STATUS_BUSY = 0x00000200;

base class _GdiDocInfo extends Struct {
  @Int32()
  external int cbSize;

  external Pointer<Utf16> lpszDocName;
  external Pointer<Utf16> lpszOutput;
  external Pointer<Utf16> lpszDatatype;
}

/// Motor de impresión nativo para Windows con protección exhaustiva de memoria (Win32 FFI).
/// Usa la API win32 directamente (EnumPrinters, OpenPrinter, WritePrinter).
class WindowsPrinterService implements PrinterService {
  List<PrinterModel>? _cachedPrinters;
  DateTime? _lastCacheTime;

  @override
  Future<List<PrinterModel>> listPrinters() async {
    final now = DateTime.now();
    if (_cachedPrinters != null &&
        _lastCacheTime != null &&
        now.difference(_lastCacheTime!).inSeconds < 15) {
      return _cachedPrinters!;
    }

    final printers = <PrinterModel>[];
    if (!Platform.isWindows) return printers;

    Pointer<DWORD>? pNeeded;
    Pointer<DWORD>? pReturned;
    Pointer<Uint8>? buffer;

    try {
      const flags = PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS;
      pNeeded = calloc<DWORD>();
      pReturned = calloc<DWORD>();

      // Primera llamada: obtener tamaño requerido
      EnumPrinters(flags, nullptr, 2, nullptr, 0, pNeeded, pReturned);

      final needed = pNeeded.value;
      if (needed == 0) {
        return printers;
      }

      buffer = calloc<Uint8>(needed);
      final result = EnumPrinters(
          flags, nullptr, 2, buffer.cast<BYTE>(), needed, pNeeded, pReturned);

      if (result != 0) {
        final count = pReturned.value;
        for (int i = 0; i < count; i++) {
          final info = (buffer.cast<PRINTER_INFO_2>() + i).ref;
          final name = info.pPrinterName.toDartString();
          if (name.isNotEmpty) {
            printers.add(PrinterModel(name: name, type: PrinterType.local));
          }
        }
      }
    } catch (e) {
      // Retorna las impresoras recolectadas hasta el momento
    } finally {
      if (buffer != null) calloc.free(buffer);
      if (pNeeded != null) calloc.free(pNeeded);
      if (pReturned != null) calloc.free(pReturned);
    }
    _cachedPrinters = printers;
    _lastCacheTime = now;
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
      // 1. Impresora de Red TCP/IP
      if (printer.type == PrinterType.network) {
        if (rawType == 'image' || ImageUtils.isImageBytes(bytes)) {
          final raster = ImageUtils.convertImageToEscPosRaster(bytes);
          if (raster != null) {
            return await _printTcp(
                printer, openCashbox ? [...pulse, ...raster] : raster);
          }
        }
        return await _printTcp(
            printer, openCashbox ? [...pulse, ...bytes] : bytes);
      }

      // 2. Local images go through the Windows driver so thermal printers keep
      // their configured driver behaviour (including completion feedback).
      if (rawType == 'image' || ImageUtils.isImageBytes(bytes)) {
        final route = selectPrintRoute(
          printerType: printer.type,
          isImage: true,
        );
        if (route == PrintRoute.driver) {
          if (openCashbox) {
            final pulseResult = await _sendRawToWin32(
              printer.name,
              Uint8List.fromList(pulse),
            );
            if (!pulseResult.success) return pulseResult;
          }
          final gdiResult = await _printImageWindowsGdi(printer.name, bytes);
          if (gdiResult.success) {
            return gdiResult;
          }

          final pdfBytes = await ImageUtils.convertImageToPdf(bytes);
          if (pdfBytes != null) {
            final pdfResult = await _printPdfWindows(printer.name, pdfBytes);
            if (pdfResult.success) {
              return pdfResult;
            }
          }
        }

        // If the driver format cannot be generated, retain a RAW fallback for
        // local thermal printers rather than dropping the print job.
        final raster = ImageUtils.convertImageToEscPosRaster(bytes);
        if (raster != null) {
          return await _sendRawToWin32(
            printer.name,
            Uint8List.fromList(openCashbox ? [...pulse, ...raster] : raster),
          );
        }
      }

      final Uint8List data = Uint8List.fromList(bytes);

      // Detectar tipo si no viene explícito
      if (rawType == null || rawType.isEmpty) {
        if (bytes.length > 4 &&
            bytes[0] == 0x25 &&
            bytes[1] == 0x50 &&
            bytes[2] == 0x44 &&
            bytes[3] == 0x46) {
          rawType = 'pdf'; // %PDF
        } else if (bytes.length > 4 &&
            bytes[0] == 0x5E &&
            bytes[1] == 0x58 &&
            bytes[2] == 0x41) {
          rawType = 'zpl'; // ^XA
        } else {
          rawType = 'raw';
        }
      }

      // Si es PDF, lo mandamos usando PDFtoPrinter.exe
      if (rawType == 'pdf') {
        return await _printPdfWindows(printer.name, data);
      }

      // Si es otro formato (ZPL, ESC/POS, Matricial, pulso cajón), win32 RAW seguro
      return await _sendRawToWin32(printer.name, data);
    } catch (e) {
      return PrintResult.error('Windows RAW error: $e');
    }
  }

  /// Sends an image through the Windows printer driver, matching the legacy
  /// agent path that lets thermal drivers handle the complete print job.
  Future<PrintResult> _printImageWindowsGdi(
    String printerName,
    List<int> inputBytes,
  ) async {
    if (!Platform.isWindows) {
      return PrintResult.error('GDI solo está disponible en Windows');
    }

    Pointer<IntPtr>? hdc;
    Pointer<_GdiDocInfo>? docInfo;
    Pointer<BITMAPINFO>? bitmapInfo;
    Pointer<Uint8>? pixels;
    Pointer<Utf16>? driverName;
    Pointer<Utf16>? deviceName;
    Pointer<Utf16>? docName;
    var documentStarted = false;
    var pageStarted = false;

    try {
      final image = img.decodeImage(Uint8List.fromList(inputBytes));
      if (image == null || image.width <= 0 || image.height <= 0) {
        return PrintResult.error('No se pudo decodificar la imagen para GDI');
      }

      final stride = ((image.width * 3 + 3) ~/ 4) * 4;
      final imageSize = stride * image.height;
      pixels = calloc<Uint8>(imageSize);

      for (var y = 0; y < image.height; y++) {
        final sourceY = image.height - y - 1;
        for (var x = 0; x < image.width; x++) {
          final pixel = image.getPixel(x, sourceY);
          final luminance = pixel.r * 0.299 + pixel.g * 0.587 + pixel.b * 0.114;
          final value = luminance < 130 ? 0 : 255;
          final offset = y * stride + x * 3;
          pixels[offset] = value;
          pixels[offset + 1] = value;
          pixels[offset + 2] = value;
        }
      }

      bitmapInfo = calloc<BITMAPINFO>();
      bitmapInfo.ref.bmiHeader
        ..biSize = sizeOf<BITMAPINFOHEADER>()
        ..biWidth = image.width
        ..biHeight = image.height
        ..biPlanes = 1
        ..biBitCount = 24
        ..biCompression = BI_RGB
        ..biSizeImage = imageSize;

      final gdi32 = DynamicLibrary.open('gdi32.dll');
      final createDc = gdi32.lookupFunction<
          IntPtr Function(
              Pointer<Utf16>, Pointer<Utf16>, Pointer<Utf16>, Pointer<DEVMODE>),
          int Function(Pointer<Utf16>, Pointer<Utf16>, Pointer<Utf16>,
              Pointer<DEVMODE>)>('CreateDCW');
      final startDoc = gdi32.lookupFunction<
          Int32 Function(IntPtr, Pointer<_GdiDocInfo>),
          int Function(int, Pointer<_GdiDocInfo>)>('StartDocW');
      final startPage =
          gdi32.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
              'StartPage');
      final getDeviceCaps = gdi32.lookupFunction<Int32 Function(IntPtr, Int32),
          int Function(int, int)>('GetDeviceCaps');
      final stretchDibits = gdi32.lookupFunction<
          Int32 Function(IntPtr, Int32, Int32, Int32, Int32, Int32, Int32,
              Int32, Int32, Pointer<Void>, Pointer<BITMAPINFO>, Uint32, Uint32),
          int Function(int, int, int, int, int, int, int, int, int,
              Pointer<Void>, Pointer<BITMAPINFO>, int, int)>('StretchDIBits');

      driverName = 'WINSPOOL'.toNativeUtf16();
      deviceName = printerName.toNativeUtf16();
      hdc = calloc<IntPtr>();
      hdc.value = createDc(driverName, deviceName, nullptr, nullptr);
      if (hdc.value == 0) {
        return PrintResult.error('CreateDC falló para "$printerName"');
      }

      final printerWidth = getDeviceCaps(hdc.value, HORZRES);
      if (printerWidth <= 0) {
        return PrintResult.error(
            'No se pudo obtener el ancho de "$printerName"');
      }
      final destinationHeight =
          (image.height * printerWidth / image.width).round();

      docName = 'Odoo Ticket'.toNativeUtf16();
      docInfo = calloc<_GdiDocInfo>();
      docInfo.ref
        ..cbSize = sizeOf<_GdiDocInfo>()
        ..lpszDocName = docName
        ..lpszOutput = nullptr
        ..lpszDatatype = nullptr;

      if (startDoc(hdc.value, docInfo) <= 0) {
        return PrintResult.error('StartDoc falló para "$printerName"');
      }
      documentStarted = true;

      if (startPage(hdc.value) <= 0) {
        return PrintResult.error('StartPage falló para "$printerName"');
      }
      pageStarted = true;

      final copied = stretchDibits(
        hdc.value,
        0,
        0,
        printerWidth,
        destinationHeight,
        0,
        0,
        image.width,
        image.height,
        pixels.cast<Void>(),
        bitmapInfo,
        DIB_RGB_COLORS,
        SRCCOPY,
      );
      if (copied == 0) {
        return PrintResult.error('StretchDIBits falló para "$printerName"');
      }

      return PrintResult.ok('GDI enviado al driver de $printerName');
    } catch (e) {
      return PrintResult.error('Windows GDI error: $e');
    } finally {
      if (hdc != null && hdc.value != 0) {
        final gdi32 = DynamicLibrary.open('gdi32.dll');
        final endPage =
            gdi32.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
                'EndPage');
        final endDoc =
            gdi32.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
                'EndDoc');
        final deleteDc =
            gdi32.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
                'DeleteDC');
        if (pageStarted) endPage(hdc.value);
        if (documentStarted) endDoc(hdc.value);
        deleteDc(hdc.value);
      }
      if (hdc != null) calloc.free(hdc);
      if (docInfo != null) calloc.free(docInfo);
      if (bitmapInfo != null) calloc.free(bitmapInfo);
      if (pixels != null) calloc.free(pixels);
      if (driverName != null) calloc.free(driverName);
      if (deviceName != null) calloc.free(deviceName);
      if (docName != null) calloc.free(docName);
    }
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

  /// Extrae el ejecutable PDFtoPrinter.exe de los assets de la app si no existe
  Future<String?> _ensurePDFtoPrinter() async {
    try {
      final sep = Platform.pathSeparator;
      final base = await getApplicationDocumentsDirectory();
      final appDir = Directory('${base.path}/SoftwareRestaurante/bin');
      await appDir.create(recursive: true);

      final pdfExePath = '${appDir.path}${sep}PDFtoPrinter.exe';

      if (File(pdfExePath).existsSync()) {
        return pdfExePath;
      }

      const assetKey = 'assets/apps/PDFtoPrinter.exe';
      final data = await rootBundle.load(assetKey);
      final bytes = data.buffer.asUint8List();
      await File(pdfExePath).writeAsBytes(bytes);
      return pdfExePath;
    } catch (e) {
      return null;
    }
  }

  /// Imprime un PDF nativamente en Windows usando PDFtoPrinter.exe
  Future<PrintResult> _printPdfWindows(
      String printerName, Uint8List pdfBytes) async {
    try {
      final exePath = await _ensurePDFtoPrinter();
      if (exePath == null) {
        return PrintResult.error(
            'No se pudo encontrar o extraer PDFtoPrinter.exe de los assets.');
      }

      final tempDir = Directory.systemTemp;
      final tempFile = File(
          '${tempDir.path}${Platform.pathSeparator}sr_print_${DateTime.now().millisecondsSinceEpoch}.pdf');
      await tempFile.writeAsBytes(pdfBytes);

      try {
        final result = await Process.run(exePath, [
          tempFile.path,
          printerName,
        ]);

        if (result.exitCode == 0) {
          return PrintResult.ok(
              'Documento PDF enviado con éxito a la impresora $printerName.');
        } else {
          return PrintResult.error(
              'PDFtoPrinter error (código ${result.exitCode}): ${result.stderr}');
        }
      } finally {
        Future.delayed(const Duration(seconds: 5), () {
          try {
            if (tempFile.existsSync()) {
              tempFile.deleteSync();
            }
          } catch (_) {}
        });
      }
    } catch (e) {
      return PrintResult.error('Error al imprimir PDF en Windows: $e');
    }
  }

  /// Enrutamiento RAW Win32 seguro con bloque try/finally estricto para evitar fugas de memoria
  Future<PrintResult> _sendRawToWin32(String printerName, Uint8List data) {
    if (!Platform.isWindows) {
      return Future.value(
          PrintResult.error('Plataforma no soportada para Win32'));
    }

    Pointer<HANDLE>? hPrinter;
    Pointer<Utf16>? pPrinterName;
    Pointer<Utf16>? jobName;
    Pointer<Utf16>? dataType;
    Pointer<DOC_INFO_1>? docInfo;
    Pointer<Uint8>? buffer;
    Pointer<DWORD>? written;
    int opened = 0;
    int docStarted = 0;
    int pageStarted = 0;

    try {
      hPrinter = calloc<HANDLE>();
      pPrinterName = printerName.toNativeUtf16();

      opened = OpenPrinter(pPrinterName, hPrinter, nullptr);
      if (opened == 0) {
        return Future.value(PrintResult.error(
            'OpenPrinter falló para "$printerName" (Error Win32: ${GetLastError()})'));
      }

      jobName = 'SoftwareRestaurante_Job'.toNativeUtf16();
      dataType = 'RAW'.toNativeUtf16();

      docInfo = calloc<DOC_INFO_1>()
        ..ref.pDocName = jobName
        ..ref.pOutputFile = nullptr
        ..ref.pDatatype = dataType;

      docStarted = StartDocPrinter(hPrinter.value, 1, docInfo.cast());
      if (docStarted == 0) {
        return Future.value(PrintResult.error(
            'StartDocPrinter falló (Error Win32: ${GetLastError()})'));
      }

      pageStarted = StartPagePrinter(hPrinter.value);

      buffer = calloc<Uint8>(data.length);
      for (int i = 0; i < data.length; i++) {
        buffer[i] = data[i];
      }
      written = calloc<DWORD>();
      final writeRes = WritePrinter(
          hPrinter.value, buffer.cast<Void>(), data.length, written);

      if (writeRes == 0) {
        return Future.value(PrintResult.error(
            'WritePrinter falló (Error Win32: ${GetLastError()})'));
      }

      final bytesWritten = written.value;
      return Future.value(
          PrintResult.ok('Escritos $bytesWritten bytes en $printerName'));
    } catch (e) {
      return Future.value(PrintResult.error('Excepción Win32: $e'));
    } finally {
      // Liberación garantizada de handles y memoria
      if (hPrinter != null && opened != 0) {
        if (pageStarted != 0) {
          EndPagePrinter(hPrinter.value);
        }
        if (docStarted != 0) {
          EndDocPrinter(hPrinter.value);
        }
        ClosePrinter(hPrinter.value);
      }
      if (pPrinterName != null) calloc.free(pPrinterName);
      if (jobName != null) calloc.free(jobName);
      if (dataType != null) calloc.free(dataType);
      if (docInfo != null) calloc.free(docInfo);
      if (buffer != null) calloc.free(buffer);
      if (written != null) calloc.free(written);
      if (hPrinter != null) calloc.free(hPrinter);
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
    final lines = [
      [esc, 0x40], // ESC @ — Reset
      [esc, 0x74, 0x02], // ESC t — Code page 850
      [esc, 0x61, 0x01], // ESC a 1 — Centrar
      [esc, 0x21, 0x10], // ESC ! — Double height
      ...('================================\n'.codeUnits),
      ...('SoftwareRestaurante\n'.codeUnits),
      ...('Agente de Impresion v2.0\n'.codeUnits),
      ...('================================\n'.codeUnits),
      [esc, 0x21, 0x00], // Normal
      [esc, 0x61, 0x00], // Izquierda
      ...('Impresora: '.codeUnits),
      ...(printerName.substring(0, printerName.length.clamp(0, 30)).codeUnits),
      [0x0A],
      ...('Estado: CONEXION EXITOSA\n'.codeUnits),
      [0x0A, 0x0A, 0x0A, 0x0A], // Feed
      [gs, 0x56, 0x42, 0x00], // GS V B — Full cut
    ];
    return lines.expand((e) => e is List<int> ? e : [e as int]).toList();
  }

  @override
  Future<String> getPrinterStatus(String printerName) async {
    if (!Platform.isWindows) return 'unknown';

    Pointer<HANDLE>? hPrinter;
    Pointer<Utf16>? pPrinterName;
    Pointer<DWORD>? pNeeded;
    Pointer<Uint8>? buffer;
    int opened = 0;

    try {
      hPrinter = calloc<HANDLE>();
      pPrinterName = printerName.toNativeUtf16();

      opened = OpenPrinter(pPrinterName, hPrinter, nullptr);
      if (opened == 0) {
        return 'offline';
      }

      pNeeded = calloc<DWORD>();
      GetPrinter(hPrinter.value, 2, nullptr, 0, pNeeded);

      final needed = pNeeded.value;
      if (needed == 0) {
        return 'error';
      }

      buffer = calloc<Uint8>(needed);
      final result =
          GetPrinter(hPrinter.value, 2, buffer.cast<BYTE>(), needed, pNeeded);

      String statusStr = 'online';

      if (result != 0) {
        final info = buffer.cast<PRINTER_INFO_2>().ref;
        final status = info.Status;

        if ((status & PRINTER_STATUS_PAPER_OUT) != 0) {
          statusStr = 'paper_out';
        } else if ((status & PRINTER_STATUS_OFFLINE) != 0) {
          statusStr = 'offline';
        } else if ((status & PRINTER_STATUS_PAUSED) != 0) {
          statusStr = 'paused';
        } else if ((status & PRINTER_STATUS_ERROR) != 0) {
          statusStr = 'error';
        } else if (status != 0) {
          statusStr = 'busy';
        }
      }

      return statusStr;
    } catch (e) {
      return 'error';
    } finally {
      if (hPrinter != null && opened != 0) {
        ClosePrinter(hPrinter.value);
      }
      if (buffer != null) calloc.free(buffer);
      if (pNeeded != null) calloc.free(pNeeded);
      if (pPrinterName != null) calloc.free(pPrinterName);
      if (hPrinter != null) calloc.free(hPrinter);
    }
  }
}

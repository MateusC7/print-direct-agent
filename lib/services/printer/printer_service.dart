import '../../models/printer_model.dart';
import '../settings_service.dart';

/// Interfaz abstracta del motor de impresión.
/// Cada plataforma implementa esta clase.
abstract class PrinterService {
  /// Lista las impresoras disponibles en el sistema.
  Future<List<PrinterModel>> listPrinters();

  /// Envía datos RAW (bytes) a la impresora indicada.
  Future<PrintResult> printRaw({
    required PrinterModel printer,
    required List<int> bytes,
    String? rawType,
    bool openCashbox = false,
  });

  /// Genera e imprime un ticket de prueba.
  Future<PrintResult> printTest(PrinterModel printer);

  /// Obtiene el estado físico de la impresora indicada.
  Future<String> getPrinterStatus(String printerName);
}

/// Extensión para obtener la lista unificada de impresoras (Nativas + Red + IoT).
extension PrinterServiceExt on PrinterService {
  Future<List<PrinterModel>> getAllPrinters() async {
    final nativePrinters = await listPrinters();
    final networkPrinters = SettingsService.instance.savedNetworkPrinters;
    final iotDevices = SettingsService.instance.savedIotDevices;

    final result = <PrinterModel>[...nativePrinters];

    for (final np in networkPrinters) {
      if (!result.any((p) => p.name == np.name || p.id == np.id)) {
        result.add(np);
      }
    }

    for (final iot in iotDevices) {
      if (!result.any((p) => p.name == iot.name || p.id == iot.id)) {
        result.add(iot);
      }
    }

    return result;
  }
}

/// Resultado de una operación de impresión.
class PrintResult {
  final bool success;
  final String message;
  const PrintResult({required this.success, required this.message});

  factory PrintResult.ok([String msg = 'OK']) =>
      PrintResult(success: true, message: msg);

  factory PrintResult.error(String msg) =>
      PrintResult(success: false, message: msg);

  @override
  String toString() => 'PrintResult(${success ? "✓" : "✗"} $message)';
}

import '../../models/printer_model.dart';

/// Selects the transport for a print request without exposing platform details
/// to the caller.
enum PrintRoute { driver, raw }

PrintRoute selectPrintRoute({
  required PrinterType printerType,
  required bool isImage,
}) {
  if (isImage && printerType == PrinterType.local) {
    return PrintRoute.driver;
  }
  return PrintRoute.raw;
}

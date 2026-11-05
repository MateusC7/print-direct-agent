import 'package:flutter_test/flutter_test.dart';
import 'package:print_app/models/printer_model.dart';
import 'package:print_app/services/printer/print_route.dart';

void main() {
  test('uses the system driver for images on local printers', () {
    expect(
      selectPrintRoute(printerType: PrinterType.local, isImage: true),
      PrintRoute.driver,
    );
  });

  test('keeps raw printing for network thermal printers', () {
    expect(
      selectPrintRoute(printerType: PrinterType.network, isImage: true),
      PrintRoute.raw,
    );
  });

  test('keeps explicit raw payloads raw on local printers', () {
    expect(
      selectPrintRoute(printerType: PrinterType.local, isImage: false),
      PrintRoute.raw,
    );
  });

  test('keeps Bluetooth and Sunmi printing raw', () {
    expect(
      selectPrintRoute(printerType: PrinterType.bluetooth, isImage: true),
      PrintRoute.raw,
    );
    expect(
      selectPrintRoute(printerType: PrinterType.sunmi, isImage: true),
      PrintRoute.raw,
    );
  });
}

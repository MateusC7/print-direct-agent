import 'package:flutter_test/flutter_test.dart';
import 'package:print_app/services/printer/android_printer_service.dart';

void main() {
  test('Sunmi cash drawer pulse is the standard ESC p pin 2 command', () {
    expect(AndroidPrinterService.sunmiCashDrawerPulse, [0x1B, 0x70, 0x00, 0x32, 0xFA]);
  });
}

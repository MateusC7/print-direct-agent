import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:print_app/models/printer_model.dart';
import 'package:print_app/services/printer/android_printer_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const btChannel = MethodChannel('com.softwarerestaurante.print/bluetooth');
  const sunmiChannel = MethodChannel('com.softwarerestaurante.print/sunmi');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  final captured = <String, Object?>{};

  setUp(() {
    captured.clear();
    for (final entry in {'bt': btChannel, 'sunmi': sunmiChannel}.entries) {
      messenger.setMockMethodCallHandler(entry.value, (call) async {
        captured[entry.key] = (call.arguments as Map)['data'];
        return true;
      });
    }
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(btChannel, null);
    messenger.setMockMethodCallHandler(sunmiChannel, null);
  });

  test('Bluetooth payload reaches the channel as Uint8List', () async {
    final result = await AndroidPrinterService().printRaw(
      printer: const PrinterModel(
          name: 'BT', type: PrinterType.bluetooth, address: 'AA:BB:CC:DD:EE:FF'),
      bytes: <int>[0x1B, 0x40, 0x41],
    );
    expect(result.success, isTrue);
    expect(captured['bt'], isA<Uint8List>());
    expect(captured['bt'], [0x1B, 0x40, 0x41]);
  });

  test('Sunmi payload is Uint8List and the drawer pulse is prepended on demand',
      () async {
    const sunmi = PrinterModel(name: 'Sunmi', type: PrinterType.sunmi);
    final service = AndroidPrinterService();

    await service.printRaw(
        printer: sunmi, bytes: <int>[0x41], openCashbox: true);
    expect(captured['sunmi'], isA<Uint8List>());
    expect(captured['sunmi'],
        [...AndroidPrinterService.sunmiCashDrawerPulse, 0x41]);

    await service.printRaw(printer: sunmi, bytes: <int>[0x41]);
    expect(captured['sunmi'], [0x41]);
  });
}

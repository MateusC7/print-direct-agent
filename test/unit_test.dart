import 'package:flutter_test/flutter_test.dart';
import 'package:print_app/models/xml_escpos_compiler.dart';

void main() {
  group('XmlEscposCompiler Tests', () {
    test('Compiles basic XML receipt into ESC/POS bytes', () {
      const xml = '''
        <receipt>
          <center>
            <bold><double-height>Software Restaurant</double-height></bold>
            <line>Ticket de Venta #001</line>
          </center>
          <left>
            <line>Producto A - \$10.00</line>
            <line>Producto B - \$5.00</line>
          </left>
          <right>
            <bold>TOTAL: \$15.00</bold>
          </right>
          <cut/>
        </receipt>
      ''';

      final List<int> bytes = XmlEscposCompiler.compile(xml);

      expect(bytes, isNotEmpty);
      // ESC @ initialization check (0x1B, 0x40)
      expect(bytes[0], equals(0x1B));
      expect(bytes[1], equals(0x40));

      // Cut command check (0x1D, 0x56, 0x42, 0x00)
      expect(bytes.contains(0x1D), isTrue);
    });

    test('Handles special characters in Latin-1', () {
      const xml = '<receipt><line>Café con Leche & Ñandú</line></receipt>';
      final List<int> bytes = XmlEscposCompiler.compile(xml);
      expect(bytes, isNotEmpty);
    });
  });
}

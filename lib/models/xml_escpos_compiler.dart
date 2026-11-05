import 'dart:convert';

/// Compila un ticket estructurado en XML nativo de Odoo a comandos binarios ESC/POS.
/// Esto permite al agente local emular por completo una Odoo IoT Box oficial.
class XmlEscposCompiler {
  static List<int> compile(String xmlString) {
    final List<int> bytes = [];

    // Inicializar impresora: ESC @
    bytes.addAll([0x1B, 0x40]);
    // Seleccionar tabla de caracteres latina (CP850 / Latin-1)
    bytes.addAll([0x1B, 0x74, 0x02]);

    // Regex para fragmentar el XML en etiquetas y texto plano
    final RegExp exp = RegExp(r'(<[^>]+>)|([^<]+)');
    final Iterable<RegExpMatch> matches = exp.allMatches(xmlString);

    bool isBold = false;
    bool isDoubleHeight = false;

    for (final match in matches) {
      final tag = match.group(1);
      final text = match.group(2);

      if (tag != null) {
        final cleanTag = tag.trim().toLowerCase();
        
        if (cleanTag.startsWith('<receipt') || cleanTag.startsWith('</receipt')) {
          continue;
        } else if (cleanTag.startsWith('<left')) {
          bytes.addAll([0x1B, 0x61, 0x00]); // Alinear izquierda
        } else if (cleanTag.startsWith('<center')) {
          bytes.addAll([0x1B, 0x61, 0x01]); // Alinear centro
        } else if (cleanTag.startsWith('<right')) {
          bytes.addAll([0x1B, 0x61, 0x02]); // Alinear derecha
        } else if (cleanTag.startsWith('</left') || cleanTag.startsWith('</center') || cleanTag.startsWith('</right')) {
          bytes.addAll([0x1B, 0x61, 0x00]); // Volver a izquierda
        } else if (cleanTag.startsWith('<bold')) {
          isBold = true;
          _updateStyles(bytes, isBold: isBold, isDoubleHeight: isDoubleHeight);
        } else if (cleanTag.startsWith('</bold')) {
          isBold = false;
          _updateStyles(bytes, isBold: isBold, isDoubleHeight: isDoubleHeight);
        } else if (cleanTag.startsWith('<double-height')) {
          isDoubleHeight = true;
          _updateStyles(bytes, isBold: isBold, isDoubleHeight: isDoubleHeight);
        } else if (cleanTag.startsWith('</double-height')) {
          isDoubleHeight = false;
          _updateStyles(bytes, isBold: isBold, isDoubleHeight: isDoubleHeight);
        } else if (cleanTag.startsWith('<cut')) {
          bytes.addAll([0x1D, 0x56, 0x42, 0x00]); // Comando de corte
        } else if (cleanTag.startsWith('<cashdraw') || cleanTag.startsWith('<open-cashbox')) {
          bytes.addAll([0x1B, 0x70, 0x00, 0x19, 0xFA]); // Comando de apertura
        } else if (cleanTag.startsWith('<line') || cleanTag.startsWith('</line')) {
          bytes.add(0x0A); // Salto de línea
        }
      } else if (text != null && text.isNotEmpty) {
        // Codificación segura Latin-1
        bytes.addAll(_latin1Encode(text));
      }
    }

    // Asegurar finalización limpia de impresión
    bytes.addAll([0x0A, 0x0A, 0x0A, 0x0A]);
    if (!xmlString.toLowerCase().contains('<cut')) {
      bytes.addAll([0x1D, 0x56, 0x42, 0x00]);
    }

    return bytes;
  }

  static void _updateStyles(List<int> bytes, {required bool isBold, required bool isDoubleHeight}) {
    int n = 0;
    if (isBold) n |= 0x08;
    if (isDoubleHeight) n |= 0x10;
    bytes.addAll([0x1B, 0x21, n]);
  }

  static List<int> _latin1Encode(String text) {
    final List<int> res = [];
    for (int i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      if (code < 256) {
        res.add(code);
      } else {
        // Reemplazar caracteres especiales fuera de Latin-1 por unicode aproximados
        res.add(0x3F); // '?'
      }
    }
    return res;
  }
}

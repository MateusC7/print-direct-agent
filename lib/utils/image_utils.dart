import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:image/image.dart' as img;

/// Utilidad para detectar y convertir imágenes (PNG/JPEG) a PDF o Raster ESC/POS.
class ImageUtils {
  /// Verifica si la cabecera del buffer corresponde a una imagen PNG o JPEG.
  static bool isImageBytes(List<int> bytes) {
    if (bytes.length < 4) return false;
    final isPng = bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47;
    final isJpeg = bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;
    return isPng || isJpeg;
  }

  /// Intenta parsear ancho y alto de un PNG leyéndolo directamente desde el bloque IHDR.
  static Map<String, int>? parsePngDimensions(Uint8List bytes) {
    if (bytes.length < 24) return null;
    if (bytes[0] != 0x89 || bytes[1] != 0x50 || bytes[2] != 0x4E || bytes[3] != 0x47) {
      return null;
    }
    try {
      final bd = ByteData.sublistView(bytes);
      final width = bd.getUint32(16);
      final height = bd.getUint32(20);
      if (width > 0 && height > 0 && width < 10000 && height < 30000) {
        return {'width': width, 'height': height};
      }
    } catch (_) {}
    return null;
  }

  /// Convierte bytes de imagen (PNG/JPEG) en un documento PDF ajustado a papel térmico de 80mm.
  static Future<Uint8List?> convertImageToPdf(List<int> inputBytes) async {
    try {
      final bytes = Uint8List.fromList(inputBytes);
      int? width;
      int? height;

      final dims = parsePngDimensions(bytes);
      if (dims != null) {
        width = dims['width'];
        height = dims['height'];
      } else {
        final imageObj = img.decodeImage(bytes);
        if (imageObj != null) {
          width = imageObj.width;
          height = imageObj.height;
        }
      }

      if (width == null || height == null || width == 0 || height == 0) {
        return null;
      }

      final pdf = pw.Document();
      final pdfImage = pw.MemoryImage(bytes);

      final double printWidth = 72.0 * PdfPageFormat.mm; // 72mm imprimible estándar en rollo de 80mm
      final double printHeight = (height / width) * printWidth;

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(
            printWidth,
            printHeight,
            marginAll: 0,
          ),
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Image(pdfImage, fit: pw.BoxFit.contain),
            );
          },
        ),
      );

      return await pdf.save();
    } catch (e) {
      print('[ImageUtils] Error convirtiendo imagen a PDF: $e');
      return null;
    }
  }

  /// Convierte una imagen PNG/JPEG a comandos raster ESC/POS (`GS v 0`) para impresoras de red o directas.
  static List<int>? convertImageToEscPosRaster(List<int> inputBytes, {int targetWidth = 576}) {
    try {
      final bytes = Uint8List.fromList(inputBytes);
      img.Image? image = img.decodeImage(bytes);
      if (image == null) return null;

      // Redimensionar al ancho exacto del cabezal térmico (576px para 80mm, 384px para 58mm)
      if (image.width != targetWidth) {
        image = img.copyResize(image, width: targetWidth);
      }

      image = img.grayscale(image);

      final width = image.width;
      final height = image.height;
      final widthBytes = (width + 7) ~/ 8;

      final List<int> escpos = [];

      // Resetear e inicializar alineación centrada
      escpos.addAll([0x1B, 0x40]); // ESC @
      escpos.addAll([0x1B, 0x61, 0x01]); // ESC a 1 (center)

      // Comando GS v 0 0 xL xH yL yH, en bandas de hasta 1024 filas: la altura
      // es de 16 bits (se corrompe con tickets muy largos) y muchas impresoras
      // limitan el tamaño de un único bloque raster.
      const int bandHeight = 1024;

      for (int y = 0; y < height; y++) {
        if (y % bandHeight == 0) {
          final rows = (height - y) < bandHeight ? (height - y) : bandHeight;
          escpos.addAll([
            0x1D, 0x76, 0x30, 0x00,
            widthBytes & 0xFF,
            (widthBytes >> 8) & 0xFF,
            rows & 0xFF,
            (rows >> 8) & 0xFF,
          ]);
        }
        for (int xByte = 0; xByte < widthBytes; xByte++) {
          int byteVal = 0;
          for (int bit = 0; bit < 8; bit++) {
            final x = xByte * 8 + bit;
            if (x < width) {
              final pixel = image.getPixel(x, y);
              final luminance = pixel.r * 0.299 + pixel.g * 0.587 + pixel.b * 0.114;
              if (luminance < 128) {
                byteVal |= (0x80 >> bit);
              }
            }
          }
          escpos.add(byteVal);
        }
      }

      // Avance de papel (5 líneas) y corte completo
      escpos.addAll([0x1B, 0x64, 0x05]); // ESC d 5
      escpos.addAll([0x1D, 0x56, 0x42, 0x00]); // GS V B 0 (Cut)

      return escpos;
    } catch (e) {
      print('[ImageUtils] Error convirtiendo imagen a ESC/POS raster: $e');
      return null;
    }
  }
}

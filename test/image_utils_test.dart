import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:print_app/utils/image_utils.dart';

void main() {
  List<int> pngOf(int width, int height) {
    final image = img.Image(width: width, height: height);
    img.fill(image, color: img.ColorRgb8(0, 0, 0));
    return img.encodePng(image);
  }

  /// Positions of every `GS v 0` header found in the stream.
  List<int> headerOffsets(List<int> bytes) {
    final offsets = <int>[];
    for (var i = 0; i + 7 < bytes.length; i++) {
      if (bytes[i] == 0x1D && bytes[i + 1] == 0x76 && bytes[i + 2] == 0x30) {
        offsets.add(i);
      }
    }
    return offsets;
  }

  test('short image keeps a single raster block', () {
    final out = ImageUtils.convertImageToEscPosRaster(pngOf(384, 100),
        targetWidth: 384)!;
    final headers = headerOffsets(out);
    expect(headers.length, 1);
    final h = headers.first;
    expect(out[h + 6] | (out[h + 7] << 8), 100);
  });

  test('tall image is split into bands of at most 1024 rows', () {
    final out = ImageUtils.convertImageToEscPosRaster(pngOf(384, 2500),
        targetWidth: 384)!;
    final headers = headerOffsets(out);
    expect(headers.length, 3);
    final rows = headers.map((h) => out[h + 6] | (out[h + 7] << 8)).toList();
    expect(rows, [1024, 1024, 452]);
  });
}

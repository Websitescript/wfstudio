import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Photo -> 240x280 RGB565 raw bitmap (2 bytes/pixel, 134,400 bytes).
class Rgb565 {
  static const int w = 240, h = 280;

  /// Cover-fit crop. zoom >= 1; dx/dy in -1..1 pan within the overflow.
  static img.Image cropToFit(img.Image src,
      {double zoom = 1, double dx = 0, double dy = 0}) {
    final scale = math.max(w / src.width, h / src.height) * zoom;
    final sw = (src.width * scale).ceil(), sh = (src.height * scale).ceil();
    final big = img.copyResize(src,
        width: sw, height: sh, interpolation: img.Interpolation.average);
    final x = (((sw - w) / 2) * (1 + dx)).round().clamp(0, sw - w);
    final y = (((sh - h) / 2) * (1 + dy)).round().clamp(0, sh - h);
    return img.copyCrop(big, x: x, y: y, width: w, height: h);
  }

  /// [bigEndian] must match the panel/firmware byte order (confirm via a test flash).
  static Uint8List encode(img.Image im, {bool bigEndian = false}) {
    assert(im.width == w && im.height == h);
    final out = Uint8List(w * h * 2);
    final bd = ByteData.view(out.buffer);
    final e = bigEndian ? Endian.big : Endian.little;
    var i = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = im.getPixel(x, y);
        final v = ((p.r.toInt() & 0xF8) << 8) |
            ((p.g.toInt() & 0xFC) << 3) |
            (p.b.toInt() >> 3);
        bd.setUint16(i, v, e);
        i += 2;
      }
    }
    return out;
  }

  static img.Image decode(Uint8List raw, int width, int height,
      {bool bigEndian = false}) {
    final im = img.Image(width: width, height: height);
    final bd = ByteData.view(raw.buffer, raw.offsetInBytes);
    final e = bigEndian ? Endian.big : Endian.little;
    for (var i = 0; i < width * height; i++) {
      final v = bd.getUint16(i * 2, e);
      im.setPixelRgb(i % width, i ~/ width, ((v >> 11) & 31) * 255 ~/ 31,
          ((v >> 5) & 63) * 255 ~/ 63, (v & 31) * 255 ~/ 31);
    }
    return im;
  }
}

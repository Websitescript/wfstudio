import 'dart:math' as math;
import 'package:image/image.dart' as img;
import 'rgb565.dart';
import 'wf_bin.dart';

/// Nothing-inspired starter faces: black, dot-matrix texture, white + signal red.
class NothingFaces {
  static final _white = img.ColorRgb8(245, 245, 245);
  static final _red = img.ColorRgb8(215, 25, 33);
  static final _dim = img.ColorRgb8(48, 48, 48);

  static img.Image _canvas() {
    final im = img.Image(width: 240, height: 280);
    img.fill(im, color: img.ColorRgb8(0, 0, 0));
    return im;
  }

  static WatchFace _wrap(String name, img.Image im, List<WElement> els) {
    final f = WatchFace(name: name, elements: [WElement(WType.background, assetId: 0), ...els]);
    f.assets[0] = WAsset(0, 240, 280, Rgb565.encode(im));
    return f;
  }

  static void _dotGrid(img.Image im, {int step = 12}) {
    for (var y = 8; y < 280; y += step) {
      for (var x = 8; x < 240; x += step) { img.fillCircle(im, x: x, y: y, radius: 1, color: _dim); }
    }
  }

  static WatchFace dotRing() {
    final im = _canvas();
    for (var i = 0; i < 60; i++) {
      final a = i * 6 * math.pi / 180;
      final big = i % 5 == 0;
      img.fillCircle(im, x: (120 + 108 * math.sin(a)).round(), y: (140 - 108 * math.cos(a)).round(),
          radius: big ? 3 : 1, color: i == 0 ? _red : _white);
    }
    img.fillCircle(im, x: 120, y: 140, radius: 4, color: _red);
    return _wrap('Nothing Dot Ring', im, [
      WElement(WType.hourHand, x: 120, y: 140, size: 52, pivotX: 10, color: 0xFFF5F5F5),
      WElement(WType.minuteHand, x: 120, y: 140, size: 84, pivotX: 12, color: 0xFFF5F5F5),
      WElement(WType.secondHand, x: 120, y: 140, size: 96, pivotX: 20, color: 0xFFD71921),
    ]);
  }

  static WatchFace dotMatrix() {
    final im = _canvas();
    _dotGrid(im);
    img.fillCircle(im, x: 214, y: 26, radius: 5, color: _red);
    return _wrap('Nothing Dot Matrix', im, [
      WElement(WType.digitalTime, x: 22, y: 90, size: 64, color: 0xFFF5F5F5),
      WElement(WType.date, x: 24, y: 170, size: 22, color: 0xFFD71921),
      WElement(WType.steps, x: 24, y: 214, size: 18, color: 0xFFF5F5F5),
      WElement(WType.battery, x: 150, y: 214, size: 18, color: 0xFFF5F5F5),
    ]);
  }

  static WatchFace signal() {
    final im = _canvas();
    for (final r in [100, 76, 52]) {
      for (var i = 0; i < 72; i++) {
        final a = i * 5 * math.pi / 180;
        img.fillCircle(im, x: (120 + r * math.sin(a)).round(), y: (140 - r * math.cos(a)).round(),
            radius: 1, color: r == 52 ? _red : _dim);
      }
    }
    return _wrap('Nothing Signal', im, [
      WElement(WType.hourHand, x: 120, y: 140, size: 40, pivotX: 0, color: 0xFFF5F5F5),
      WElement(WType.minuteHand, x: 120, y: 140, size: 70, pivotX: 0, color: 0xFFF5F5F5),
      WElement(WType.digitalTime, x: 78, y: 236, size: 26, color: 0xFFF5F5F5),
    ]);
  }

  static List<WatchFace> all() => [dotRing(), dotMatrix(), signal()];
}

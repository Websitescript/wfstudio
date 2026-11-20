import 'dart:typed_data';

/// NOTE: "WFS1" is a PLACEHOLDER container. The real boAt/Realtek watch face
/// layout must be reverse-engineered (decode an official face .bin / HCI log),
/// then implement it by changing only [compile]/[parse]/[validate] below.
enum WType {
  background, hourHand, minuteHand, secondHand, digitalTime, date,
  steps, heartRate, battery, weather, bluetooth
}

/// Hands: (x,y) = pivot on screen, size = length px, pivotX = tail px.
/// Others: (x,y) = top-left, size = font px.
class WElement {
  WType type;
  int x, y, pivotX, pivotY, assetId, color, size;
  WElement(this.type,
      {this.x = 0, this.y = 0, this.pivotX = 0, this.pivotY = 0,
      this.assetId = 0xFFFF, this.color = 0xFFFFFFFF, this.size = 20});
}

class WAsset {
  final int id, w, h;
  final Uint8List rgb565;
  WAsset(this.id, this.w, this.h, this.rgb565);
}

class WatchFace {
  String name;
  final List<WElement> elements;
  final Map<int, WAsset> assets;
  Uint8List? previewPng;
  WatchFace({this.name = 'Untitled', List<WElement>? elements,
      Map<int, WAsset>? assets})
      : elements = elements ?? [], assets = assets ?? {};
}

class Limits {
  final int maxFileBytes, maxAssets, maxElements;
  const Limits({this.maxFileBytes = 1 << 20, this.maxAssets = 32,
      this.maxElements = 48}); // tune to the watch's real flash/RAM budget
}

class Crc {
  static final List<int> _t32 = List.generate(256, (n) {
    var c = n;
    for (var k = 0; k < 8; k++) { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1; }
    return c;
  });
  static int crc32(List<int> d, [int start = 0]) {
    var c = 0xFFFFFFFF;
    for (var i = start; i < d.length; i++) { c = _t32[(c ^ d[i]) & 0xFF] ^ (c >> 8); }
    return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
  static int crc16(List<int> d) { // CCITT-FALSE
    var c = 0xFFFF;
    for (final b in d) {
      c ^= b << 8;
      for (var k = 0; k < 8; k++) { c = (c & 0x8000) != 0 ? ((c << 1) ^ 0x1021) & 0xFFFF : (c << 1) & 0xFFFF; }
    }
    return c;
  }
}

class WfBin {
  static const hdr = 32, elemSize = 20, assetSize = 16, ver = 1;
  static final magic = [0x57, 0x46, 0x53, 0x31]; // "WFS1"
  static const E = Endian.little;

  static Uint8List compile(WatchFace f, {Limits limits = const Limits()}) {
    final assets = f.assets.values.toList()..sort((a, b) => a.id - b.id);
    final elemOff = hdr;
    final assetOff = elemOff + f.elements.length * elemSize;
    var dataOff = assetOff + assets.length * assetSize;
    final total = dataOff + assets.fold<int>(0, (s, a) => s + a.rgb565.length);
    final out = Uint8List(total);
    final bd = ByteData.view(out.buffer);
    out.setRange(0, 4, magic);
    bd.setUint16(4, ver, E);
    bd.setUint16(8, 240, E);
    bd.setUint16(10, 280, E);
    bd.setUint16(12, f.elements.length, E);
    bd.setUint16(14, assets.length, E);
    bd.setUint32(16, elemOff, E);
    bd.setUint32(20, assetOff, E);
    bd.setUint32(24, total, E);
    var o = elemOff;
    for (final e in f.elements) {
      bd.setUint8(o, e.type.index);
      bd.setInt16(o + 2, e.x, E);
      bd.setInt16(o + 4, e.y, E);
      bd.setInt16(o + 6, e.pivotX, E);
      bd.setInt16(o + 8, e.pivotY, E);
      bd.setUint16(o + 10, e.assetId, E);
      bd.setUint32(o + 12, e.color, E);
      bd.setUint8(o + 16, e.size);
      o += elemSize;
    }
    o = assetOff;
    for (final a in assets) {
      bd.setUint16(o, a.id, E);
      bd.setUint16(o + 2, a.w, E);
      bd.setUint16(o + 4, a.h, E);
      bd.setUint8(o + 6, 0); // fmt 0 = RGB565
      bd.setUint32(o + 8, dataOff, E);
      bd.setUint32(o + 12, a.rgb565.length, E);
      out.setRange(dataOff, dataOff + a.rgb565.length, a.rgb565);
      dataOff += a.rgb565.length;
      o += assetSize;
    }
    bd.setUint32(28, Crc.crc32(out, hdr), E);
    final errs = validate(out, limits);
    if (errs.isNotEmpty) throw FormatException(errs.join('; '));
    return out;
  }

  /// Strict header/size/CRC/bounds check. Empty list == safe to flash.
  static List<String> validate(Uint8List b, [Limits l = const Limits()]) {
    final err = <String>[];
    if (b.length < hdr) return ['File smaller than header'];
    final bd = ByteData.view(b.buffer, b.offsetInBytes, b.length);
    for (var i = 0; i < 4; i++) { if (b[i] != magic[i]) return ['Bad magic']; }
    if (bd.getUint16(4, E) != ver) err.add('Unsupported version');
    if (bd.getUint16(8, E) != 240 || bd.getUint16(10, E) != 280) err.add('Resolution must be 240x280');
    if (bd.getUint32(24, E) != b.length) err.add('Length field mismatch');
    if (b.length > l.maxFileBytes) err.add('File ${b.length} B exceeds limit ${l.maxFileBytes} B');
    if (Crc.crc32(b, hdr) != bd.getUint32(28, E)) err.add('CRC32 mismatch');
    final ne = bd.getUint16(12, E), na = bd.getUint16(14, E);
    if (ne > l.maxElements) err.add('Too many elements ($ne)');
    if (na > l.maxAssets) err.add('Too many assets ($na)');
    final eo = bd.getUint32(16, E), ao = bd.getUint32(20, E);
    if (eo + ne * elemSize > b.length || ao + na * assetSize > b.length) return [...err, 'Table out of bounds'];
    final ids = <int>{};
    for (var i = 0; i < na; i++) {
      final o = ao + i * assetSize;
      final w = bd.getUint16(o + 2, E), h = bd.getUint16(o + 4, E);
      final off = bd.getUint32(o + 8, E), len = bd.getUint32(o + 12, E);
      if (len != w * h * 2) err.add('Asset ${bd.getUint16(o, E)} size != w*h*2');
      if (off + len > b.length) err.add('Asset ${bd.getUint16(o, E)} out of bounds');
      ids.add(bd.getUint16(o, E));
    }
    for (var i = 0; i < ne; i++) {
      final o = eo + i * elemSize;
      if (b[o] >= WType.values.length) err.add('Element $i bad type');
      final a = bd.getUint16(o + 10, E);
      if (a != 0xFFFF && !ids.contains(a)) err.add('Element $i missing asset $a');
    }
    return err;
  }

  static WatchFace parse(Uint8List b, {String name = 'Imported'}) {
    final errs = validate(b, const Limits(maxFileBytes: 1 << 26));
    if (errs.isNotEmpty) throw FormatException(errs.join('; '));
    final bd = ByteData.view(b.buffer, b.offsetInBytes, b.length);
    final f = WatchFace(name: name);
    final eo = bd.getUint32(16, E), ao = bd.getUint32(20, E);
    for (var i = 0; i < bd.getUint16(12, E); i++) {
      final o = eo + i * elemSize;
      f.elements.add(WElement(WType.values[b[o]],
          x: bd.getInt16(o + 2, E), y: bd.getInt16(o + 4, E),
          pivotX: bd.getInt16(o + 6, E), pivotY: bd.getInt16(o + 8, E),
          assetId: bd.getUint16(o + 10, E), color: bd.getUint32(o + 12, E),
          size: b[o + 16]));
    }
    for (var i = 0; i < bd.getUint16(14, E); i++) {
      final o = ao + i * assetSize;
      final id = bd.getUint16(o, E), off = bd.getUint32(o + 8, E), len = bd.getUint32(o + 12, E);
      f.assets[id] = WAsset(id, bd.getUint16(o + 2, E), bd.getUint16(o + 4, E),
          Uint8List.fromList(b.sublist(off, off + len)));
    }
    return f;
  }
}

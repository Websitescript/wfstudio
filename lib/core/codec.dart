import 'dart:math' as math;
import 'dart:typed_data';
import 'wf_bin.dart';

/// Every format (our placeholder WFS1, CMF Watch Pro, boAt Wave Connect) is a codec
/// to/from the shared WatchFace model. Conversion = decode(A) -> encode(B).
abstract class FaceCodec {
  String get id;
  bool sniff(Uint8List b);
  WatchFace decode(Uint8List b, {String name = 'Imported'});
  Uint8List encode(WatchFace f);
}

class WfsCodec implements FaceCodec {
  @override String get id => 'wfs1';
  @override bool sniff(Uint8List b) =>
      b.length > 4 && b[0] == 0x57 && b[1] == 0x46 && b[2] == 0x53 && b[3] == 0x31;
  @override WatchFace decode(Uint8List b, {String name = 'Imported'}) => WfBin.parse(b, name: name);
  @override Uint8List encode(WatchFace f) => WfBin.compile(f);
}

/// TODO: needs the real CMF layout. Fill sniff/decode once a sample file is analysed.
class CmfCodec implements FaceCodec {
  @override String get id => 'cmf';
  @override bool sniff(Uint8List b) => false;
  @override WatchFace decode(Uint8List b, {String name = 'Imported'}) =>
      throw UnsupportedError('CMF decoder not mapped yet');
  @override Uint8List encode(WatchFace f) => throw UnsupportedError('CMF encoder not mapped yet');
}

/// TODO: needs the real boAt Wave Connect layout (same process).
class BoatCodec implements FaceCodec {
  @override String get id => 'boat';
  @override bool sniff(Uint8List b) => false;
  @override WatchFace decode(Uint8List b, {String name = 'Imported'}) =>
      throw UnsupportedError('boAt decoder not mapped yet');
  @override Uint8List encode(WatchFace f) => throw UnsupportedError('boAt encoder not mapped yet');
}

class Codecs {
  static final all = <FaceCodec>[WfsCodec(), CmfCodec(), BoatCodec()];
  static FaceCodec? detect(Uint8List b) {
    for (final c in all) { if (c.sniff(b)) return c; }
    return null;
  }
  static final boat = all[2];
  static Uint8List convert(Uint8List src, FaceCodec to, {String name = 'Converted'}) {
    final from = detect(src);
    if (from == null) throw UnsupportedError('Unknown source format');
    return to.encode(from.decode(src, name: name));
  }
}

/// Reverse-engineering helper: describes an unknown .bin so its layout can be mapped.
class FormatInspector {
  static const _sizes = [[240, 280], [240, 240], [280, 240], [466, 466], [454, 454],
      [360, 360], [368, 448], [320, 380], [410, 502], [390, 450]];

  static String report(Uint8List b, {int headBytes = 64}) {
    final o = StringBuffer('size: ${b.length} bytes\n');
    final bd = ByteData.view(b.buffer, b.offsetInBytes, b.length);
    o.writeln('entropy: ${_entropy(b).toStringAsFixed(2)} bits/byte (>7.5 = compressed/encrypted)');
    o.writeln('head:');
    for (var i = 0; i < math.min(headBytes, b.length); i += 16) {
      final row = b.sublist(i, math.min(i + 16, b.length));
      o.writeln('${i.toRadixString(16).padLeft(4, '0')}  '
          '${row.map((x) => x.toRadixString(16).padLeft(2, '0')).join(' ')}  '
          '${String.fromCharCodes(row.map((x) => x >= 32 && x < 127 ? x : 46))}');
    }
    final lim = math.min(b.length - 3, 512);
    for (var i = 0; i < lim; i += 2) {
      final w = bd.getUint16(i, Endian.little), h = bd.getUint16(i + 2, Endian.little);
      for (final s in _sizes) { if (w == s[0] && h == s[1]) o.writeln('resolution $w x $h at offset $i'); }
    }
    for (var i = 0; i < math.min(b.length - 3, 128); i++) {
      final v = bd.getUint32(i, Endian.little);
      if (v == b.length) o.writeln('u32 at $i equals file length');
      if (v == b.length - 4 || v == b.length - 32) o.writeln('u32 at $i = length minus header ($v)');
    }
    final strs = <String>[];
    var cur = StringBuffer();
    for (var i = 0; i < math.min(b.length, 4096); i++) {
      if (b[i] >= 32 && b[i] < 127) { cur.writeCharCode(b[i]); }
      else { if (cur.length >= 4) strs.add(cur.toString()); cur = StringBuffer(); }
    }
    if (strs.isNotEmpty) o.writeln('strings: ${strs.take(12).join(' | ')}');
    return o.toString();
  }

  static double _entropy(Uint8List b) {
    final c = List.filled(256, 0);
    for (final x in b) { c[x]++; }
    var e = 0.0;
    for (final n in c) { if (n > 0) { final p = n / b.length; e -= p * math.log(p) / math.ln2; } }
    return e;
  }
}

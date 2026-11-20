import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/wf_bin.dart';

/// UUIDs + framing are a PROFILE, editable from the Packet Logger / UUID Mapper
/// screen once real values are captured from an HCI snoop log.
class FlashProfile {
  Guid service, writeChar, notifyChar;
  int window, maxRetries, ackTimeoutMs, requestMtu;
  bool withoutResponse;
  FlashProfile({required this.service, required this.writeChar,
      required this.notifyChar, this.window = 8, this.maxRetries = 5,
      this.ackTimeoutMs = 2000, this.requestMtu = 247,
      this.withoutResponse = true});
}

class PacketLog {
  final DateTime t = DateTime.now();
  final bool tx;
  final Uint8List data;
  PacketLog(this.tx, this.data);
  String get hex => data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
}

class BleFlasher {
  // Placeholder framing: START | DATA(seq u16) | END, replies ACK/NACK/DONE.
  static const kStart = 0x01, kData = 0x02, kEnd = 0x03;
  static const kAck = 0x10, kNack = 0x11, kDone = 0x12;

  final FlashProfile p;
  BleFlasher(this.p);

  BluetoothDevice? dev;
  BluetoothCharacteristic? _wc, _nc;
  final _log = StreamController<PacketLog>.broadcast();
  Stream<PacketLog> get log => _log.stream;
  final _rx = <Uint8List>[];
  Completer<void>? _wake;

  static Future<bool> ensurePermissions() async {
    final r = await [
      Permission.bluetoothScan, Permission.bluetoothConnect,
      Permission.locationWhenInUse, // needed for scanning on Android <= 11
    ].request();
    final ok = r[Permission.bluetoothScan]!.isGranted ||
        r[Permission.locationWhenInUse]!.isGranted;
    return ok && (r[Permission.bluetoothConnect]!.isGranted ||
        r[Permission.bluetoothConnect]!.isLimited ||
        !Platform.isAndroid || r[Permission.bluetoothConnect]!.isDenied == false);
  }

  Stream<List<ScanResult>> scan({Duration timeout = const Duration(seconds: 10)}) {
    FlutterBluePlus.startScan(timeout: timeout);
    return FlutterBluePlus.scanResults;
  }

  Future<void> connect(BluetoothDevice d) async {
    await FlutterBluePlus.stopScan();
    await d.connect(autoConnect: false, timeout: const Duration(seconds: 15));
    if (Platform.isAndroid) await d.requestMtu(p.requestMtu);
    for (final s in await d.discoverServices()) {
      if (s.uuid == p.service) {
        for (final c in s.characteristics) {
          if (c.uuid == p.writeChar) _wc = c;
          if (c.uuid == p.notifyChar) _nc = c;
        }
      }
    }
    if (_wc == null || _nc == null) {
      await d.disconnect();
      throw StateError('Service/characteristics not found - check UUID profile');
    }
    await _nc!.setNotifyValue(true);
    _nc!.onValueReceived.listen((v) {
      final d = Uint8List.fromList(v);
      _log.add(PacketLog(false, d));
      _rx.add(d);
      if (_wake?.isCompleted == false) _wake!.complete();
    });
    dev = d;
  }

  /// For the UUID Mapper screen: dump every service/characteristic + properties.
  Future<List<BluetoothService>> dumpGatt() => dev!.discoverServices();

  /// Raw write for the debugger (handshake experiments).
  Future<void> sendRaw(Uint8List data) => _tx(data);

  Future<void> _tx(Uint8List d) async {
    _log.add(PacketLog(true, d));
    await _wc!.write(d, withoutResponse: p.withoutResponse);
  }

  Future<Uint8List?> _resp() async {
    if (_rx.isEmpty) {
      _wake = Completer<void>();
      await _wake!.future.timeout(Duration(milliseconds: p.ackTimeoutMs), onTimeout: () {});
      _wake = null;
    }
    return _rx.isEmpty ? null : _rx.removeAt(0);
  }

  /// Validates, chunks to MTU, sliding-window ACK/NACK with retransmit.
  Future<void> flash(Uint8List bin, void Function(double) onProgress,
      {Limits limits = const Limits()}) async {
    final errs = WfBin.validate(bin, limits);
    if (errs.isNotEmpty) throw StateError('Refusing to flash: ${errs.join('; ')}');
    if (_wc == null || dev == null) throw StateError('Not connected');

    final chunk = dev!.mtuNow - 3 /*ATT*/ - 3 /*op+seq*/;
    if (chunk < 20) throw StateError('MTU too small ($chunk B payload)');
    final total = (bin.length + chunk - 1) ~/ chunk;
    _rx.clear();

    final start = ByteData(9)
      ..setUint8(0, kStart)
      ..setUint32(1, bin.length, Endian.little)
      ..setUint32(5, Crc.crc32(bin), Endian.little);
    await _tx(start.buffer.asUint8List());
    final first = await _resp();
    if (first == null || first[0] != kAck) throw StateError('No ACK to START');

    var base = 0, next = 0, retries = 0;
    while (base < total) {
      while (next < total && next < base + p.window) {
        final s = next * chunk, e = (s + chunk).clamp(0, bin.length);
        final f = BytesBuilder()
          ..addByte(kData)
          ..add([next & 0xFF, next >> 8])
          ..add(bin.sublist(s, e));
        await _tx(f.toBytes());
        next++;
      }
      final r = await _resp();
      if (r == null) {
        if (++retries > p.maxRetries) throw TimeoutException('Watch stopped responding');
        next = base; // go-back-N
        continue;
      }
      final seq = r.length >= 3 ? r[1] | (r[2] << 8) : 0;
      if (r[0] == kAck) {
        base = seq + 1 > base ? seq + 1 : base;
        retries = 0;
        onProgress(base / total);
      } else if (r[0] == kNack) {
        if (++retries > p.maxRetries) throw StateError('Too many NACKs at chunk $seq');
        base = seq; next = seq;
      }
    }
    final end = ByteData(3)..setUint8(0, kEnd)..setUint16(1, Crc.crc16(bin), Endian.little);
    await _tx(end.buffer.asUint8List());
    final done = await _resp();
    if (done == null || done[0] != kDone) throw StateError('Watch did not confirm transfer');
    onProgress(1);
  }

  Future<void> disconnect() async => dev?.disconnect();
}

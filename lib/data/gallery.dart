import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

class SavedFace {
  final String id, name, source;
  final Uint8List bin;
  final Uint8List? thumb;
  final int ts;
  SavedFace(this.id, this.name, this.source, this.bin, this.thumb, this.ts);
  factory SavedFace.fromMap(Map m) => SavedFace(m['id'], m['name'], m['source'], m['bin'], m['thumb'], m['ts']);
}

/// Offline-first gallery: everything lives in a local Hive box.
class Gallery {
  static late Box _box;
  static Future<void> init() async {
    await Hive.initFlutter();
    _box = await Hive.openBox('faces');
  }
  static ValueListenable<Box> get listenable => _box.listenable();
  static List<SavedFace> all() =>
      _box.values.map((m) => SavedFace.fromMap(Map.from(m as Map))).toList()..sort((a, b) => b.ts - a.ts);
  static Future<void> save(String name, Uint8List bin, {Uint8List? thumb, String source = 'studio'}) {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    return _box.put(id, {'id': id, 'name': name, 'source': source, 'bin': bin, 'thumb': thumb,
        'ts': DateTime.now().millisecondsSinceEpoch});
  }
  static Future<void> delete(String id) => _box.delete(id);
}

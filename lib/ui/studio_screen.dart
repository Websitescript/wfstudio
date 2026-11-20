import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import '../core/rgb565.dart';
import '../core/wf_bin.dart';

class StudioScreen extends StatefulWidget {
  final void Function(Uint8List bin, String name, Uint8List? thumb)? onCompiled;
  final WatchFace? initial;
  const StudioScreen({super.key, this.onCompiled, this.initial});
  @override
  State<StudioScreen> createState() => _StudioState();
}

class _StudioState extends State<StudioScreen> {
  late WatchFace face;
  img.Image? _src;
  Uint8List? _bgPng;
  double zoom = 1, panX = 0, panY = 0;
  WElement? sel;
  DateTime now = DateTime.now();
  Timer? _t;

  static const _sample = {
    WType.digitalTime: '10:09', WType.date: 'THU 19', WType.steps: '8,432',
    WType.heartRate: '72 bpm', WType.battery: '85%', WType.weather: '24°C',
    WType.bluetooth: 'BT',
  };

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => now = DateTime.now()));
    face = widget.initial ?? WatchFace(name: 'My Face');
    final a0 = face.assets[0];
    if (a0 != null) _bgPng = Uint8List.fromList(img.encodePng(Rgb565.decode(a0.rgb565, a0.w, a0.h)));
    if (widget.initial == null) face.elements.addAll([
      WElement(WType.hourHand, x: 120, y: 140, size: 50, pivotX: 10, color: 0xFFFFFFFF),
      WElement(WType.minuteHand, x: 120, y: 140, size: 75, pivotX: 12, color: 0xFFFFFFFF),
      WElement(WType.secondHand, x: 120, y: 140, size: 85, pivotX: 18, color: 0xFFFF6B5E),
    ]);
  }

  @override
  void dispose() { _t?.cancel(); super.dispose(); }

  Future<void> _pickBg() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (f == null) return;
    _src = img.decodeImage(await f.readAsBytes());
    zoom = 1; panX = 0; panY = 0;
    _rebuildBg();
  }

  void _rebuildBg() {
    if (_src == null) return;
    final c = Rgb565.cropToFit(_src!, zoom: zoom, dx: panX, dy: panY);
    face.assets[0] = WAsset(0, Rgb565.w, Rgb565.h, Rgb565.encode(c));
    if (!face.elements.any((e) => e.type == WType.background)) {
      face.elements.insert(0, WElement(WType.background, assetId: 0));
    }
    setState(() => _bgPng = Uint8List.fromList(img.encodePng(c)));
  }

  void _add(WType t) => setState(() {
        final e = WElement(t, x: 60, y: 200, size: 22, color: 0xFFFFFFFF);
        face.elements.add(e);
        sel = e;
      });

  void _compile() {
    try {
      final bin = WfBin.compile(face);
      face.previewPng = _bgPng;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Compiled ${(bin.length / 1024).toStringAsFixed(1)} KB / '
              '${(const Limits().maxFileBytes / 1024).round()} KB')));
      widget.onCompiled?.call(bin, face.name, _bgPng);
    } on FormatException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  bool _isHand(WType t) => t == WType.hourHand || t == WType.minuteHand || t == WType.secondHand;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(title: const Text('Watch Face Studio'), actions: [
        IconButton(icon: const Icon(Icons.image), onPressed: _pickBg),
        IconButton(icon: const Icon(Icons.memory), onPressed: _compile),
      ]),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: AspectRatio(
              aspectRatio: 240 / 280,
              child: LayoutBuilder(builder: (_, c) {
                final s = c.maxWidth / 240;
                return ClipRRect(
                  borderRadius: BorderRadius.circular(28 * s),
                  child: Stack(children: [
                    Positioned.fill(child: Container(color: Colors.black)),
                    if (_bgPng != null)
                      Positioned.fill(child: Image.memory(_bgPng!, fit: BoxFit.fill, gaplessPlayback: true)),
                    Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _Hands(face.elements, now, s)))),
                    for (final e in face.elements.where((e) => e.type != WType.background))
                      Positioned(
                        left: e.x * s - (_isHand(e.type) ? 14 : 0),
                        top: e.y * s - (_isHand(e.type) ? 14 : 0),
                        child: GestureDetector(
                          onTap: () => setState(() => sel = e),
                          onPanUpdate: (d) => setState(() {
                            sel = e;
                            e.x = (e.x + d.delta.dx / s).round().clamp(0, 240);
                            e.y = (e.y + d.delta.dy / s).round().clamp(0, 280);
                          }),
                          child: _isHand(e.type)
                              ? Container(width: 28, height: 28, decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: identical(sel, e) ? const Color(0xFF2DD4BF) : Colors.transparent, width: 2)))
                              : Container(
                                  decoration: BoxDecoration(border: Border.all(color: identical(sel, e) ? const Color(0xFF2DD4BF) : Colors.transparent)),
                                  child: Text(_sample[e.type] ?? '',
                                      style: TextStyle(fontSize: e.size * s, color: Color(e.color), fontFamily: 'monospace'))),
                        ),
                      ),
                  ]),
                );
              }),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_src != null) ...[
          _slider('Zoom', zoom, 1, 3, (v) { zoom = v; _rebuildBg(); }),
          _slider('Pan X', panX, -1, 1, (v) { panX = v; _rebuildBg(); }),
          _slider('Pan Y', panY, -1, 1, (v) { panY = v; _rebuildBg(); }),
        ],
        Wrap(spacing: 6, children: [
          for (final t in _sample.keys)
            ActionChip(label: Text(t.name), onPressed: () => _add(t)),
        ]),
        if (sel != null && sel!.type != WType.background) ...[
          const Divider(),
          Text('Selected: ${sel!.type.name}', style: const TextStyle(color: Colors.white70)),
          _slider(_isHand(sel!.type) ? 'Length' : 'Font size', sel!.size.toDouble(), 8, 140,
              (v) => setState(() => sel!.size = v.round())),
          if (_isHand(sel!.type))
            _slider('Tail (pivot offset)', sel!.pivotX.toDouble(), 0, 40,
                (v) => setState(() => sel!.pivotX = v.round())),
          Row(children: [
            for (final c in [0xFFFFFFFF, 0xFF2DD4BF, 0xFFFF6B5E, 0xFFE5B84B])
              GestureDetector(
                onTap: () => setState(() => sel!.color = c),
                child: Container(margin: const EdgeInsets.all(4), width: 28, height: 28,
                    decoration: BoxDecoration(color: Color(c), shape: BoxShape.circle)),
              ),
            const Spacer(),
            IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => setState(() { face.elements.remove(sel); sel = null; })),
          ]),
        ],
      ]),
    );
  }

  Widget _slider(String l, double v, double a, double b, ValueChanged<double> cb) =>
      Row(children: [SizedBox(width: 96, child: Text(l, style: const TextStyle(color: Colors.white70, fontSize: 12))),
        Expanded(child: Slider(value: v.clamp(a, b), min: a, max: b, onChanged: cb))]);
}

class _Hands extends CustomPainter {
  final List<WElement> els; final DateTime t; final double s;
  _Hands(this.els, this.t, this.s);
  @override
  void paint(Canvas c, Size _) {
    for (final e in els) {
      final double a;
      switch (e.type) {
        case WType.hourHand: a = ((t.hour % 12) + t.minute / 60) * 30; break;
        case WType.minuteHand: a = (t.minute + t.second / 60) * 6; break;
        case WType.secondHand: a = t.second * 6; break;
        default: continue;
      }
      final r = a * math.pi / 180, dx = math.sin(r), dy = -math.cos(r);
      final p = Offset(e.x * s, e.y * s);
      c.drawLine(p - Offset(dx, dy) * (e.pivotX * s), p + Offset(dx, dy) * (e.size * s),
          Paint()..color = Color(e.color)..strokeWidth = (e.type == WType.secondHand ? 1.5 : 3.5) * s..strokeCap = StrokeCap.round);
    }
  }
  @override
  bool shouldRepaint(_) => true;
}

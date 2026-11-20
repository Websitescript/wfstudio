import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/codec.dart';
import '../core/nothing_faces.dart';
import '../core/rgb565.dart';
import '../core/wf_bin.dart';
import '../data/gallery.dart';
import 'package:image/image.dart' as img;

class GalleryScreen extends StatelessWidget {
  final void Function(SavedFace) onEdit;
  const GalleryScreen({super.key, required this.onEdit});

  void _msg(BuildContext c, String m) =>
      ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _import(BuildContext c) async {
    final r = await FilePicker.platform.pickFiles(withData: true, allowMultiple: true);
    if (r == null) return;
    for (final f in r.files) {
      final b = f.bytes;
      if (b == null) continue;
      final name = f.name.replaceAll(RegExp(r'\.bin$', caseSensitive: false), '');
      final codec = Codecs.detect(b);
      if (codec == null) {
        if (!c.mounted) return;
        await showDialog(context: c, builder: (_) => AlertDialog(
          title: Text('Unknown format: ${f.name}'),
          content: SingleChildScrollView(child: SelectableText(FormatInspector.report(b),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11))),
          actions: [
            TextButton(onPressed: () => Clipboard.setData(ClipboardData(text: FormatInspector.report(b))),
                child: const Text('Copy report')),
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Close')),
          ],
        ));
        continue;
      }
      await Gallery.save(name, b, source: codec.id);
    }
  }

  Future<void> _addNothing(BuildContext c) async {
    for (final f in NothingFaces.all()) {
      final a = f.assets[0]!;
      final png = Uint8List.fromList(img.encodePng(Rgb565.decode(a.rgb565, a.w, a.h)));
      await Gallery.save(f.name, WfBin.compile(f), thumb: png, source: 'nothing-pack');
    }
    if (c.mounted) _msg(c, 'Added 3 Nothing-style faces');
  }

  void _actions(BuildContext c, SavedFace s) => showModalBottomSheet(context: c, builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(s.name), subtitle: Text('${(s.bin.length / 1024).toStringAsFixed(1)} KB · ${s.source}')),
          ListTile(leading: const Icon(Icons.edit), title: const Text('Edit in Studio'), onTap: () { Navigator.pop(c); onEdit(s); }),
          ListTile(leading: const Icon(Icons.watch), title: const Text('Convert to boAt format'), onTap: () {
            Navigator.pop(c);
            try { Codecs.convert(s.bin, Codecs.boat, name: s.name); }
            on UnsupportedError catch (e) { _msg(c, e.message ?? 'Not supported yet'); }
          }),
          ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Delete'),
              onTap: () { Navigator.pop(c); Gallery.delete(s.id); }),
        ])));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Gallery'), actions: [
          IconButton(tooltip: 'Add Nothing-style pack', icon: const Icon(Icons.auto_awesome), onPressed: () => _addNothing(context)),
          IconButton(tooltip: 'Import .bin', icon: const Icon(Icons.file_open), onPressed: () => _import(context)),
        ]),
        body: ValueListenableBuilder(
          valueListenable: Gallery.listenable,
          builder: (_, __, ___) {
            final faces = Gallery.all();
            if (faces.isEmpty) return const Center(child: Text('No faces yet. Import a .bin or add the Nothing pack.'));
            return GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2, childAspectRatio: 240 / 320, crossAxisSpacing: 12, mainAxisSpacing: 12),
              itemCount: faces.length,
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => _actions(context, faces[i]),
                child: Column(children: [
                  Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(18),
                      child: faces[i].thumb != null
                          ? Image.memory(faces[i].thumb!, fit: BoxFit.cover, width: double.infinity)
                          : Container(color: Colors.black26, child: const Center(child: Icon(Icons.watch))))),
                  const SizedBox(height: 6),
                  Text(faces[i].name, maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
            );
          },
        ),
      );
}

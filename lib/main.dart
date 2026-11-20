import 'package:flutter/material.dart';
import 'core/wf_bin.dart';
import 'data/gallery.dart';
import 'ui/gallery_screen.dart';
import 'ui/studio_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Gallery.init();
  runApp(MaterialApp(debugShowCheckedModeBanner: false, theme: ThemeData.dark(useMaterial3: true), home: const Home()));
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int tab = 0;
  WatchFace? editing;
  int rev = 0;

  void _edit(SavedFace s) {
    try {
      setState(() { editing = WfBin.parse(s.bin, name: s.name); rev++; tab = 1; });
    } on FormatException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(index: tab, children: [
          GalleryScreen(onEdit: _edit),
          StudioScreen(
            key: ValueKey(rev),
            initial: editing,
            onCompiled: (bin, name, thumb) => Gallery.save(name, bin, thumb: thumb),
          ),
        ]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() => tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.grid_view), label: 'Gallery'),
            NavigationDestination(icon: Icon(Icons.brush), label: 'Studio'),
          ],
        ),
      );
}

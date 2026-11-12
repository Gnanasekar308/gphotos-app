import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/app_settings.dart';
import 'core/media_library.dart';
import 'faces/face_store.dart';
import 'faces/faces_page.dart';
import 'screens/albums_page.dart';
import 'screens/home_page.dart';
import 'screens/photos_page.dart';
import 'screens/tools_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // keep decoded images bounded for very large libraries
  PaintingBinding.instance.imageCache.maximumSizeBytes = 120 << 20;
  final prefs = await SharedPreferences.getInstance();
  runApp(GApp(settings: AppSettings(prefs)));
}

class GApp extends StatelessWidget {
  const GApp({super.key, required this.settings, this.home});
  final AppSettings settings;
  final Widget? home;

  @override
  Widget build(BuildContext context) {
    return SettingsScope(
      settings: settings,
      child: ListenableBuilder(
        listenable: settings,
        builder: (_, __) => MaterialApp(
          title: 'Gphotos',
          debugShowCheckedModeBanner: false,
          themeMode: settings.themeMode,
          theme: settings.theme(Brightness.light),
          darkTheme: settings.theme(Brightness.dark),
          home: home ?? const Shell(),
        ),
      ),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int i = 0;
  bool? ok;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    i = AppSettings.tabIds.indexOf(SettingsScope.of(context).startTab).clamp(0, 4);
    _init();
  }

  Future<void> _init() async {
    final access = await MediaLibrary.instance.requestAccess();
    if (!mounted) return;
    setState(() => ok = access);
    if (access) {
      await MediaLibrary.instance.reload();
      await FaceStore.instance.load();
      FaceStore.instance.prune(MediaLibrary.instance.all.map((a) => a.id).toSet());
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    if (ok == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (ok == false) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Image.asset('assets/icon/gphotos_icon.png', width: 120, errorBuilder: (_, __, ___) => const Icon(Icons.photo, size: 96)),
              const SizedBox(height: 16),
              const Text('Gphotos needs access to your photos to show them.', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _init, child: const Text('Allow access')),
              TextButton(onPressed: PhotoManager.openSetting, child: const Text('Open settings')),
            ]),
          ),
        ),
      );
    }
    final pages = [
      HomePage(go: (n) => setState(() => i = n)),
      const PhotosPage(),
      const AlbumsPage(),
      const FacesPage(),
      const ToolsPage(),
    ];
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: i, children: pages)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: i,
        labelBehavior: s.showNavLabels ? NavigationDestinationLabelBehavior.alwaysShow : NavigationDestinationLabelBehavior.alwaysHide,
        onDestinationSelected: (n) => setState(() => i = n),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.photo_outlined), selectedIcon: Icon(Icons.photo), label: 'Photos'),
          NavigationDestination(icon: Icon(Icons.photo_album_outlined), selectedIcon: Icon(Icons.photo_album), label: 'Albums'),
          NavigationDestination(icon: Icon(Icons.face_outlined), selectedIcon: Icon(Icons.face), label: 'People'),
          NavigationDestination(icon: Icon(Icons.apps_outlined), selectedIcon: Icon(Icons.apps), label: 'Tools'),
        ],
      ),
    );
  }
}

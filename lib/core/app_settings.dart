import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// All user customization, persisted in SharedPreferences.
class AppSettings extends ChangeNotifier {
  AppSettings(this._p) {
    _read();
  }

  final SharedPreferences _p;

  static const accents = <int>[0xFF3D7BFF, 0xFFE91E63, 0xFF00BFA5, 0xFFFF9800, 0xFF9C27B0, 0xFF26C6DA];
  static const tabIds = <String>['home', 'photos', 'albums', 'faces', 'tools'];

  late ThemeMode themeMode;
  late Color accent;
  late int gridColumns;
  late double gridSpacing;
  late bool squareThumbs;
  late bool showNavLabels;
  late String startTab;
  late bool pinchToChangeColumns;
  late bool swipeDownToClose;
  late bool dragToSelect;
  late bool haptics;

  void _read() {
    themeMode = ThemeMode.values[(_p.getInt('themeMode') ?? ThemeMode.dark.index).clamp(0, 2)];
    accent = Color(_p.getInt('accent') ?? accents.first);
    gridColumns = (_p.getInt('cols') ?? 3).clamp(2, 6);
    gridSpacing = (_p.getDouble('gridSpacing') ?? 2).clamp(0, 8).toDouble();
    squareThumbs = _p.getBool('squareThumbs') ?? true;
    showNavLabels = _p.getBool('navLabels') ?? true;
    final t = _p.getString('startTab') ?? 'home';
    startTab = tabIds.contains(t) ? t : 'home';
    pinchToChangeColumns = _p.getBool('pinchCols') ?? true;
    swipeDownToClose = _p.getBool('swipeClose') ?? true;
    dragToSelect = _p.getBool('dragSelect') ?? true;
    haptics = _p.getBool('haptics') ?? true;
  }

  Future<void> setThemeMode(ThemeMode m) async {
    themeMode = m;
    await _p.setInt('themeMode', m.index);
    notifyListeners();
  }

  Future<void> setAccent(Color c) async {
    accent = c;
    await _p.setInt('accent', c.toARGB32());
    notifyListeners();
  }

  Future<void> setGridColumns(int n) async {
    gridColumns = n.clamp(2, 6);
    await _p.setInt('cols', gridColumns);
    notifyListeners();
  }

  Future<void> setGridSpacing(double v) async {
    gridSpacing = v.clamp(0, 8);
    await _p.setDouble('gridSpacing', gridSpacing);
    notifyListeners();
  }

  Future<void> setSquareThumbs(bool v) => _setBool('squareThumbs', v, () => squareThumbs = v);
  Future<void> setShowNavLabels(bool v) => _setBool('navLabels', v, () => showNavLabels = v);
  Future<void> setPinchToChangeColumns(bool v) => _setBool('pinchCols', v, () => pinchToChangeColumns = v);
  Future<void> setSwipeDownToClose(bool v) => _setBool('swipeClose', v, () => swipeDownToClose = v);
  Future<void> setDragToSelect(bool v) => _setBool('dragSelect', v, () => dragToSelect = v);
  Future<void> setHaptics(bool v) => _setBool('haptics', v, () => haptics = v);

  Future<void> setStartTab(String id) async {
    if (!tabIds.contains(id)) return;
    startTab = id;
    await _p.setString('startTab', id);
    notifyListeners();
  }

  Future<void> resetAll() async {
    for (final k in ['themeMode', 'accent', 'cols', 'gridSpacing', 'squareThumbs', 'navLabels', 'startTab', 'pinchCols', 'swipeClose', 'dragSelect', 'haptics']) {
      await _p.remove(k);
    }
    _read();
    notifyListeners();
  }

  Future<void> _setBool(String k, bool v, VoidCallback apply) async {
    apply();
    await _p.setBool(k, v);
    notifyListeners();
  }

  ThemeData theme(Brightness b) {
    final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: b);
    final dark = b == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: dark ? scheme.copyWith(surface: const Color(0xFF111633)) : scheme,
      scaffoldBackgroundColor: dark ? const Color(0xFF0A0F2C) : null,
      appBarTheme: AppBarTheme(backgroundColor: dark ? const Color(0xFF0A0F2C) : null, elevation: 0),
    );
  }
}

/// Gives widgets access to [AppSettings] and rebuilds them when it changes.
class SettingsScope extends InheritedNotifier<AppSettings> {
  const SettingsScope({super.key, required AppSettings settings, required super.child}) : super(notifier: settings);

  static AppSettings of(BuildContext c) => c.dependOnInheritedWidgetOfExactType<SettingsScope>()!.notifier!;
}

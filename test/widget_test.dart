import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gphotos/core/app_settings.dart';
import 'package:gphotos/main.dart';
import 'package:gphotos/screens/settings_page.dart';
import 'package:gphotos/screens/tools_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('settings persist across restarts', () async {
    SharedPreferences.setMockInitialValues({});
    final p = await SharedPreferences.getInstance();
    final s = AppSettings(p);
    expect(s.gridColumns, 3);
    await s.setGridColumns(5);
    await s.setThemeMode(ThemeMode.light);
    await s.setAccent(const Color(0xFFE91E63));
    await s.setStartTab('faces');
    await s.setSwipeDownToClose(false);
    await s.setGridColumns(99);
    final again = AppSettings(p);
    expect(again.gridColumns, 6, reason: 'clamped');
    expect(again.themeMode, ThemeMode.light);
    expect(again.accent.toARGB32(), 0xFFE91E63);
    expect(again.startTab, 'faces');
    expect(again.swipeDownToClose, isFalse);
    await again.resetAll();
    expect(AppSettings(p).gridColumns, 3);
  });

  testWidgets('settings page changes the theme and grid', (t) async {
    SharedPreferences.setMockInitialValues({});
    final s = AppSettings(await SharedPreferences.getInstance());
    await t.pumpWidget(GApp(settings: s, home: const SettingsPage()));
    expect(find.text('Settings'), findsOneWidget);
    await t.tap(find.text('Light'));
    await t.pumpAndSettle();
    expect(s.themeMode, ThemeMode.light);
    await t.tap(find.byKey(const ValueKey('accent_${0xFF00BFA5}')));
    await t.pumpAndSettle();
    expect(s.accent.toARGB32(), 0xFF00BFA5);
    final MaterialApp app = t.widget(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.light);
  });

  testWidgets('tools page marks unsupported AI features honestly', (t) async {
    SharedPreferences.setMockInitialValues({});
    final s = AppSettings(await SharedPreferences.getInstance());
    await t.pumpWidget(GApp(settings: s, home: const Scaffold(body: ToolsPage())));
    await t.scrollUntilVisible(find.text('Object eraser'), 200);
    expect(find.text('Not supported'), findsNWidgets(4));
  });
}

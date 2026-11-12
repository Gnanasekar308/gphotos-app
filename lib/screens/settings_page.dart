import 'package:flutter/material.dart';

import '../core/app_settings.dart';
import '../core/file_ops.dart';
import '../widgets/thumb.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  static const _tabNames = {'home': 'Home', 'photos': 'Photos', 'albums': 'Albums', 'faces': 'People', 'tools': 'Tools'};

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    final h = Theme.of(context).textTheme.titleSmall;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Theme', style: h),
        const SizedBox(height: 8),
        SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(value: ThemeMode.system, label: Text('System')),
            ButtonSegment(value: ThemeMode.light, label: Text('Light')),
            ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
          ],
          selected: {s.themeMode},
          onSelectionChanged: (v) => s.setThemeMode(v.first),
        ),
        const SizedBox(height: 20),
        Text('Accent colour', style: h),
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 12, children: [
          for (final k in AppSettings.accents)
            GestureDetector(
              key: ValueKey('accent_$k'),
              onTap: () => s.setAccent(Color(k)),
              child: CircleAvatar(
                backgroundColor: Color(k),
                child: s.accent.toARGB32() == k ? const Icon(Icons.check, color: Colors.white) : null,
              ),
            ),
        ]),
        const SizedBox(height: 20),
        Text('Grid', style: h),
        Row(children: [
          const Text('Columns'),
          Expanded(
            child: Slider(min: 2, max: 6, divisions: 4, value: s.gridColumns.toDouble(), label: '${s.gridColumns}', onChanged: (v) => s.setGridColumns(v.round())),
          ),
          Text('${s.gridColumns}'),
        ]),
        Row(children: [
          const Text('Spacing'),
          Expanded(child: Slider(min: 0, max: 8, divisions: 8, value: s.gridSpacing, label: '${s.gridSpacing.round()}', onChanged: s.setGridSpacing)),
          Text('${s.gridSpacing.round()}'),
        ]),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Square (cropped) thumbnails'), value: s.squareThumbs, onChanged: s.setSquareThumbs),
        const SizedBox(height: 12),
        Text('Navigation', style: h),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Show tab labels'), value: s.showNavLabels, onChanged: s.setShowNavLabels),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Start on'),
          trailing: DropdownButton<String>(
            value: s.startTab,
            items: [for (final e in _tabNames.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => v == null ? null : s.setStartTab(v),
          ),
        ),
        const SizedBox(height: 12),
        Text('Gestures', style: h),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Long-press + slide to select'), subtitle: const Text('Off: long-press selects one photo'), value: s.dragToSelect, onChanged: s.setDragToSelect),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Pinch the grid to change columns'), value: s.pinchToChangeColumns, onChanged: s.setPinchToChangeColumns),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Swipe down to close a photo'), value: s.swipeDownToClose, onChanged: s.setSwipeDownToClose),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Haptic feedback'), value: s.haptics, onChanged: s.setHaptics),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.cleaning_services),
          title: const Text('Clear thumbnail cache'),
          onTap: () {
            ThumbCache.instance.clear();
            PaintingBinding.instance.imageCache.clear();
            snack(context, 'Cache cleared');
          },
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.restore),
          title: const Text('Reset customization'),
          onTap: () async {
            if (await confirm(context, title: 'Reset?', message: 'Theme, colours, grid, navigation and gestures go back to defaults.', action: 'Reset', destructive: false)) {
              await s.resetAll();
            }
          },
        ),
        const ListTile(contentPadding: EdgeInsets.zero, title: Text('About Gphotos'), subtitle: Text('Version 1.1.0 • everything runs on this device')),
      ]),
    );
  }
}

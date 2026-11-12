import 'dart:io';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:share_plus/share_plus.dart';

import 'media_library.dart';

void snack(BuildContext c, String m) {
  ScaffoldMessenger.of(c)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));
}

/// Shares several photos at once (one share sheet, all files attached).
Future<int> sharePhotos(List<AssetEntity> items) async {
  final files = <XFile>[];
  for (final a in items) {
    final File? f = await a.file;
    if (f != null) files.add(XFile(f.path, mimeType: a.mimeType));
  }
  if (files.isEmpty) return 0;
  await Share.shareXFiles(files);
  return files.length;
}

Future<bool> confirm(BuildContext c, {required String title, required String message, required String action, bool destructive = true}) async {
  final cs = Theme.of(c).colorScheme;
  final r = await showDialog<bool>(
    context: c,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: cs.error, foregroundColor: cs.onError) : null,
          onPressed: () => Navigator.pop(d, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Deletes photos after the user confirms in our dialog. Android 11+ additionally shows its own
/// system confirmation; only the ids the system reports as deleted are removed from the app.
Future<List<String>> deletePhotos(BuildContext c, List<AssetEntity> items) async {
  if (items.isEmpty) return const [];
  final n = items.length;
  final ok = await confirm(c,
      title: 'Delete $n photo${n == 1 ? '' : 's'}?',
      message: 'The photo${n == 1 ? '' : 's'} will be deleted from this device. This cannot be undone from Gphotos.',
      action: 'Delete');
  if (!ok) return const [];
  final done = await PhotoManager.editor.deleteWithIds(items.map((e) => e.id).toList());
  MediaLibrary.instance.removeIds(done);
  if (c.mounted) {
    snack(c, done.length == n ? 'Deleted $n' : 'Deleted ${done.length} of $n');
  }
  return done;
}

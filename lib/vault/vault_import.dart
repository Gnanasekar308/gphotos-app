import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../core/file_ops.dart';
import '../core/media_library.dart';
import 'vault_page.dart';
import 'vault_store.dart';

/// Moves photos into the encrypted vault:
/// 1. the vault must be unlocked (PIN / biometrics),
/// 2. each photo is encrypted and verified (decrypt + SHA-256 compare),
/// 3. only then the user is asked, separately, whether to delete the originals from the gallery.
/// Returns the ids of originals that were actually deleted (empty if the user kept them).
Future<List<String>> moveToVault(BuildContext context, List<AssetEntity> items) async {
  if (items.isEmpty) return const [];
  final store = await VaultGate.unlockFlow(context);
  if (store == null || !context.mounted) return const [];
  final progress = ValueNotifier<int>(0);
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Encrypting'),
        content: ValueListenableBuilder<int>(
          valueListenable: progress,
          builder: (_, v, __) => Column(mainAxisSize: MainAxisSize.min, children: [
            LinearProgressIndicator(value: items.isEmpty ? null : v / items.length),
            const SizedBox(height: 12),
            Text('$v of ${items.length}'),
          ]),
        ),
      ),
    ),
  );
  final ok = <AssetEntity>[];
  final failed = <String>[];
  for (final a in items) {
    try {
      final f = await a.originFile;
      if (f == null) throw StateError('no file');
      final bytes = await f.readAsBytes();
      final th = await a.thumbnailDataWithSize(const ThumbnailSize.square(300), quality: 80);
      await store.add(
        bytes: bytes,
        thumb: th,
        name: a.title ?? '${a.id}.jpg',
        mime: a.mimeType ?? 'image/jpeg',
        created: a.createDateSecond ?? 0,
        width: a.orientatedWidth,
        height: a.orientatedHeight,
      );
      ok.add(a);
    } catch (_) {
      failed.add(a.title ?? a.id);
    }
    progress.value++;
  }
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  if (!context.mounted) return const [];
  if (ok.isEmpty) {
    snack(context, 'Nothing was added to the vault');
    return const [];
  }
  final del = await confirm(context,
      title: 'Delete ${ok.length} original${ok.length == 1 ? '' : 's'}?',
      message: '${ok.length} photo${ok.length == 1 ? ' is' : 's are'} encrypted in the vault and verified'
          '${failed.isEmpty ? '' : ' (${failed.length} failed and were left untouched)'}.\n\n'
          'Delete the original${ok.length == 1 ? '' : 's'} from the gallery so they are only in the vault? '
          'If you keep them, they stay visible in the gallery.',
      action: 'Delete originals');
  if (!del) {
    if (context.mounted) snack(context, 'Copied to vault. Originals kept in the gallery.');
    return const [];
  }
  final done = await PhotoManager.editor.deleteWithIds(ok.map((e) => e.id).toList());
  MediaLibrary.instance.removeIds(done);
  if (context.mounted) snack(context, 'Moved ${done.length} to the vault');
  return done;
}

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../core/file_ops.dart';
import '../core/media_library.dart';
import '../viewer/viewer_page.dart';
import '../widgets/thumb.dart';
import 'face_model.dart';
import 'face_scanner.dart';
import 'face_store.dart';

/// Face crop drawn from the (cached) photo thumbnail; nothing extra is stored on disk.
class FaceAvatar extends StatefulWidget {
  const FaceAvatar({super.key, required this.face, this.size = 72});
  final FaceRecord face;
  final double size;
  @override
  State<FaceAvatar> createState() => _FaceAvatarState();
}

class _FaceAvatarState extends State<FaceAvatar> {
  ui.Image? _img;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(FaceAvatar old) {
    super.didUpdateWidget(old);
    if (old.face.id != widget.face.id) _load();
  }

  Future<void> _load() async {
    final a = await AssetEntity.fromId(widget.face.assetId);
    if (a == null) return;
    final b = await ThumbCache.instance.get(a, 512);
    if (b == null) return;
    final codec = await ui.instantiateImageCodec(b);
    final fr = await codec.getNextFrame();
    if (!mounted) {
      fr.image.dispose();
      return;
    }
    setState(() {
      _img?.dispose();
      _img = fr.image;
    });
  }

  @override
  void dispose() {
    _img?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final i = _img;
    return ClipOval(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: i == null
            ? ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest, child: const Icon(Icons.face))
            : CustomPaint(painter: _FacePainter(i, widget.face.box)),
      ),
    );
  }
}

class _FacePainter extends CustomPainter {
  _FacePainter(this.image, this.box);
  final ui.Image image;
  final List<double> box;

  @override
  void paint(Canvas c, Size s) {
    final w = image.width.toDouble(), h = image.height.toDouble();
    // the 512 thumbnail keeps the aspect ratio of the 1024 one that was analysed, so normalised boxes map 1:1
    final cx = (box[0] + box[2] / 2) * w, cy = (box[1] + box[3] / 2) * h;
    final side = (box[2] * w > box[3] * h ? box[2] * w : box[3] * h) * 1.35;
    final src = Rect.fromCenter(center: Offset(cx, cy), width: side, height: side);
    c.drawImageRect(image, src, Offset.zero & s, Paint()..filterQuality = FilterQuality.medium);
  }

  @override
  bool shouldRepaint(_FacePainter o) => o.image != image || o.box != box;
}

class FacesPage extends StatefulWidget {
  const FacesPage({super.key});
  @override
  State<FacesPage> createState() => _FacesPageState();
}

class _FacesPageState extends State<FacesPage> {
  final store = FaceStore.instance;
  final scanner = FaceScanner.instance;
  bool showHidden = false;

  @override
  void initState() {
    super.initState();
    store.load();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([store, scanner, MediaLibrary.instance]),
      builder: (_, __) {
        final people = store.sortedPeople(includeHidden: showHidden);
        final lib = MediaLibrary.instance;
        final unscanned = lib.all.where((a) => !store.scanned.contains(a.id)).length;
        return CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: Card(
              margin: const EdgeInsets.all(12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.face_retouching_natural),
                    const SizedBox(width: 8),
                    Expanded(child: Text('${people.length} people • ${store.faces.length} faces', style: const TextStyle(fontWeight: FontWeight.w600))),
                    PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'hidden') setState(() => showHidden = !showHidden);
                        if (v == 'reset' && await confirm(context, title: 'Reset face data?', message: 'All faces, names and corrections are removed. Photos are not touched.', action: 'Reset')) {
                          scanner.stop();
                          await store.resetAll();
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(value: 'hidden', child: Text(showHidden ? 'Hide hidden people' : 'Show hidden people')),
                        const PopupMenuItem(value: 'reset', child: Text('Reset face data')),
                      ],
                    ),
                  ]),
                  const SizedBox(height: 8),
                  if (scanner.running) ...[
                    LinearProgressIndicator(value: scanner.total == 0 ? null : scanner.progress),
                    const SizedBox(height: 6),
                    Text(lib.complete ? 'Scanning ${scanner.done} / ${scanner.total} photos' : 'Loading library (${lib.all.length} / ${lib.total})...'),
                    TextButton(onPressed: scanner.stop, child: const Text('Pause')),
                  ] else ...[
                    Text(unscanned == 0 && lib.complete ? 'All ${lib.all.length} photos scanned.' : '$unscanned photos not scanned yet.'),
                    const SizedBox(height: 6),
                    FilledButton.icon(
                      onPressed: unscanned == 0 && lib.complete ? null : scanner.start,
                      icon: const Icon(Icons.play_arrow),
                      label: Text(store.scanned.isEmpty ? 'Scan library' : 'Continue scan'),
                    ),
                  ],
                  if (scanner.error != null) Text('Scan stopped: ${scanner.error}', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  const SizedBox(height: 6),
                  Text(
                    'Detection is on-device (ML Kit). Grouping uses a simple appearance descriptor, not a trained '
                    'recognition model, so check groups and fix them with Merge, Split and Move. The scan runs while the app is open '
                    'and resumes where it stopped.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ]),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 120, mainAxisExtent: 140, crossAxisSpacing: 8, mainAxisSpacing: 8),
              delegate: SliverChildBuilderDelegate(childCount: people.length, (_, i) {
                final p = people[i];
                final cover = p.coverFaceId == null ? null : store.faces[p.coverFaceId];
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PersonPage(personId: p.id))),
                  child: Column(children: [
                    const SizedBox(height: 6),
                    if (cover != null) FaceAvatar(face: cover, size: 84) else const CircleAvatar(radius: 42, child: Icon(Icons.face)),
                    const SizedBox(height: 6),
                    Text(p.name.isEmpty ? 'Add name' : p.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontStyle: p.name.isEmpty ? FontStyle.italic : null, color: p.hidden ? Colors.grey : null)),
                    Text('${store.countOf(p.id)}', style: Theme.of(context).textTheme.bodySmall),
                  ]),
                );
              }),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ]);
      },
    );
  }
}

Future<String?> askName(BuildContext c, String current) async {
  final tc = TextEditingController(text: current);
  return showDialog<String>(
    context: c,
    builder: (d) => AlertDialog(
      title: const Text('Name'),
      content: TextField(controller: tc, autofocus: true, textCapitalization: TextCapitalization.words, onSubmitted: (v) => Navigator.pop(d, v)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(d, tc.text), child: const Text('Save')),
      ],
    ),
  );
}

/// Picks another person (for merge / move). Returns its id, or 'new' for a new person.
Future<String?> pickPerson(BuildContext c, {required String exclude, bool allowNew = false}) {
  final store = FaceStore.instance;
  final people = store.sortedPeople(includeHidden: true).where((p) => p.id != exclude).toList();
  return showModalBottomSheet<String>(
    context: c,
    isScrollControlled: true,
    builder: (s) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(c).height * 0.6,
        child: ListView(children: [
          if (allowNew) ListTile(leading: const Icon(Icons.person_add), title: const Text('New person'), onTap: () => Navigator.pop(s, 'new')),
          for (final p in people)
            ListTile(
              leading: p.coverFaceId != null && store.faces[p.coverFaceId] != null ? FaceAvatar(face: store.faces[p.coverFaceId]!, size: 40) : const Icon(Icons.face),
              title: Text(p.name.isEmpty ? 'Unnamed (${store.countOf(p.id)})' : p.name),
              onTap: () => Navigator.pop(s, p.id),
            ),
        ]),
      ),
    ),
  );
}

/// One person: their faces (select to split / move / remove / set cover), rename, merge, hide, and the
/// photos they appear in.
class PersonPage extends StatefulWidget {
  const PersonPage({super.key, required this.personId});
  final String personId;
  @override
  State<PersonPage> createState() => _PersonPageState();
}

class _PersonPageState extends State<PersonPage> {
  final store = FaceStore.instance;
  final sel = <String>{};
  int tab = 0;

  Future<List<AssetEntity>> _photos(List<FaceRecord> faces) async {
    final ids = faces.map((f) => f.assetId).toSet();
    final out = <AssetEntity>[];
    for (final id in ids) {
      final a = await AssetEntity.fromId(id);
      if (a != null) out.add(a);
    }
    out.sort((a, b) => b.createDateTime.compareTo(a.createDateTime));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (_, __) {
        final p = store.people[widget.personId];
        if (p == null) return const Scaffold(body: Center(child: Text('This person was merged')));
        final faces = store.facesOf(p.id);
        return Scaffold(
          appBar: AppBar(
            title: GestureDetector(
              onTap: () async {
                final n = await askName(context, p.name);
                if (n != null) store.rename(p.id, n);
              },
              child: Text(p.name.isEmpty ? 'Add a name' : p.name),
            ),
            actions: [
              IconButton(
                tooltip: 'Rename',
                icon: const Icon(Icons.edit),
                onPressed: () async {
                  final n = await askName(context, p.name);
                  if (n != null) store.rename(p.id, n);
                },
              ),
              PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'merge') {
                    final other = await pickPerson(context, exclude: p.id);
                    if (other == null || !context.mounted) return;
                    final o = store.people[other];
                    if (await confirm(context, title: 'Merge?', message: 'All faces of "${o?.name.isEmpty ?? true ? 'that person' : o!.name}" move into this person.', action: 'Merge', destructive: false)) {
                      store.merge(p.id, other);
                    }
                  }
                  if (v == 'hide') store.setHidden(p.id, !p.hidden);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'merge', child: Text('Merge with another person')),
                  PopupMenuItem(value: 'hide', child: Text(p.hidden ? 'Show in People' : 'Hide from People')),
                ],
              ),
            ],
          ),
          body: Column(children: [
            SegmentedButton<int>(
              segments: [
                ButtonSegment(value: 0, label: Text('Faces (${faces.length})')),
                const ButtonSegment(value: 1, label: Text('Photos')),
              ],
              selected: {tab},
              onSelectionChanged: (s) => setState(() {
                tab = s.first;
                sel.clear();
              }),
            ),
            if (tab == 0 && sel.isNotEmpty)
              Wrap(alignment: WrapAlignment.center, children: [
                TextButton.icon(icon: const Icon(Icons.call_split), label: const Text('Split off'), onPressed: () async {
                  final n = await askName(context, '');
                  final id = store.split(sel.toList(), name: n ?? '');
                  setState(sel.clear);
                  if (context.mounted) snack(context, 'Split into a new person');
                  if (store.countOf(p.id) == 0 && context.mounted) {
                    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => PersonPage(personId: id)));
                  }
                }),
                TextButton.icon(icon: const Icon(Icons.drive_file_move), label: const Text('Move to...'), onPressed: () async {
                  final to = await pickPerson(context, exclude: p.id, allowNew: true);
                  if (to == null) return;
                  if (to == 'new') {
                    store.split(sel.toList());
                  } else {
                    store.moveFaces(sel.toList(), to);
                  }
                  setState(sel.clear);
                }),
                TextButton.icon(icon: const Icon(Icons.account_circle), label: const Text('Set as cover'), onPressed: sel.length != 1 ? null : () {
                  store.setCover(p.id, sel.first);
                  setState(sel.clear);
                }),
                TextButton.icon(icon: const Icon(Icons.not_interested), label: const Text('Not a face'), onPressed: () {
                  store.removeFaces(sel.toList());
                  setState(sel.clear);
                }),
              ]),
            Expanded(
              child: tab == 0
                  ? GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 96, crossAxisSpacing: 10, mainAxisSpacing: 10),
                      itemCount: faces.length,
                      itemBuilder: (_, i) {
                        final f = faces[i];
                        final on = sel.contains(f.id);
                        return GestureDetector(
                          onTap: () => setState(() => on ? sel.remove(f.id) : sel.add(f.id)),
                          child: Stack(children: [
                            Positioned.fill(child: FaceAvatar(face: f, size: 96)),
                            if (on) Positioned(right: 0, top: 0, child: Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary)),
                            if (p.coverFaceId == f.id) const Positioned(left: 0, bottom: 0, child: Icon(Icons.star, size: 18, color: Colors.amber)),
                          ]),
                        );
                      },
                    )
                  : FutureBuilder<List<AssetEntity>>(
                      future: _photos(faces),
                      builder: (_, s) {
                        final list = s.data;
                        if (list == null) return const Center(child: CircularProgressIndicator());
                        return GridView.builder(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 2, mainAxisSpacing: 2),
                          itemCount: list.length,
                          itemBuilder: (_, i) => GestureDetector(
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ViewerPage(items: list, start: i))),
                            child: PhotoThumb(list[i], size: 300),
                          ),
                        );
                      },
                    ),
            ),
          ]),
        );
      },
    );
  }
}

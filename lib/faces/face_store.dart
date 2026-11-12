import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'face_model.dart';

/// Persistent faces and people (JSON in app-private storage, written atomically).
/// All corrections (name, merge, split, move, remove) are saved immediately and are never undone by
/// a later scan: scanned photos are remembered and manual assignments are kept.
class FaceStore extends ChangeNotifier {
  FaceStore({Directory? dir}) : _dirOverride = dir;
  static final instance = FaceStore();

  final Directory? _dirOverride;
  final Map<String, FaceRecord> faces = {};
  final Map<String, Person> people = {};
  final Set<String> scanned = {};
  bool loaded = false;
  int _seq = 0;

  Future<File> _file() async {
    final d = _dirOverride ?? await getApplicationSupportDirectory();
    return File('${d.path}/faces_v1.json');
  }

  Future<void> load() async {
    if (loaded) return;
    final f = await _file();
    if (await f.exists()) {
      try {
        final m = jsonDecode(await f.readAsString()) as Map;
        for (final e in (m['faces'] as List)) {
          final r = FaceRecord.fromJson(e as Map);
          faces[r.id] = r;
        }
        for (final e in (m['people'] as List)) {
          final p = Person.fromJson(e as Map);
          people[p.id] = p;
        }
        scanned.addAll((m['scanned'] as List).cast<String>());
        _seq = (m['seq'] ?? 0) as int;
      } catch (_) {
        // a corrupt file is kept aside instead of being silently overwritten
        await f.rename('${f.path}.corrupt');
      }
    }
    loaded = true;
    notifyListeners();
  }

  Future<void>? _saving;
  bool _dirty = false;

  /// Saves are serialised: overlapping calls coalesce into one more write after the current one.
  Future<void> save() async {
    if (_saving != null) {
      _dirty = true;
      return _saving;
    }
    final run = _saveLoop();
    _saving = run;
    try {
      await run;
    } finally {
      _saving = null;
    }
  }

  Future<void> _saveLoop() async {
    do {
      _dirty = false;
      await _writeOnce();
    } while (_dirty);
  }

  Future<void> _writeOnce() async {
    final f = await _file();
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode({
      'seq': _seq,
      'faces': faces.values.map((e) => e.toJson()).toList(),
      'people': people.values.map((e) => e.toJson()).toList(),
      'scanned': scanned.toList(),
    }), flush: true);
    await tmp.rename(f.path);
  }

  String newId(String p) => '$p${++_seq}';

  List<FaceRecord> facesOf(String personId) => faces.values.where((f) => f.personId == personId).toList();

  /// People sorted by number of faces (named first).
  List<Person> sortedPeople({bool includeHidden = false}) {
    final counts = <String, int>{};
    for (final f in faces.values) {
      if (f.personId != null) counts[f.personId!] = (counts[f.personId!] ?? 0) + 1;
    }
    final list = people.values.where((p) => (includeHidden || !p.hidden) && (counts[p.id] ?? 0) > 0).toList();
    list.sort((a, b) {
      if (a.name.isNotEmpty != b.name.isNotEmpty) return a.name.isNotEmpty ? -1 : 1;
      return (counts[b.id] ?? 0).compareTo(counts[a.id] ?? 0);
    });
    return list;
  }

  int countOf(String personId) => faces.values.where((f) => f.personId == personId).length;

  Map<String, List<double>> centroids() {
    final by = <String, List<List<double>>>{};
    for (final f in faces.values) {
      if (f.personId != null) (by[f.personId!] ??= []).add(f.sig);
    }
    return by.map((k, v) => MapEntry(k, centroid(v)));
  }

  /// Adds newly detected faces of one photo and groups them.
  void addDetected(String assetId, List<({List<double> box, List<double> sig})> found, Map<String, List<double>> cents) {
    for (final d in found) {
      final id = newId('f');
      String? pid = d.sig.isEmpty ? null : nearestPerson(d.sig, cents);
      if (pid == null) {
        pid = newId('p');
        people[pid] = Person(id: pid, coverFaceId: id);
        if (d.sig.isNotEmpty) cents[pid] = d.sig;
      } else {
        // update the running centroid a little so the cluster follows its members
        final c = cents[pid]!;
        cents[pid] = normalise([for (var i = 0; i < c.length; i++) c[i] * 0.9 + d.sig[i] * 0.1]);
      }
      faces[id] = FaceRecord(id: id, assetId: assetId, box: d.box, sig: d.sig, personId: pid);
    }
    scanned.add(assetId);
  }

  void rename(String personId, String name) {
    people[personId]?.name = name.trim();
    _changed();
  }

  /// Moves every face of [from] into [into] and deletes [from].
  void merge(String into, String from) {
    if (into == from) return;
    for (final f in faces.values) {
      if (f.personId == from) f.personId = into;
    }
    final a = people[into], b = people.remove(from);
    if (a != null && a.name.isEmpty && b != null && b.name.isNotEmpty) a.name = b.name;
    _changed();
  }

  /// Splits [faceIds] off into a new person; returns its id.
  String split(Iterable<String> faceIds, {String name = ''}) {
    final pid = newId('p');
    people[pid] = Person(id: pid, name: name, coverFaceId: faceIds.isEmpty ? null : faceIds.first);
    for (final id in faceIds) {
      faces[id]?.personId = pid;
    }
    _changed();
    return pid;
  }

  void moveFaces(Iterable<String> faceIds, String personId) {
    for (final id in faceIds) {
      faces[id]?.personId = personId;
    }
    _changed();
  }

  /// "Not a face" / wrong detection: removes the face records (the photo stays scanned).
  void removeFaces(Iterable<String> faceIds) {
    for (final id in faceIds) {
      faces.remove(id);
    }
    _changed();
  }

  void setCover(String personId, String faceId) {
    people[personId]?.coverFaceId = faceId;
    _changed();
  }

  void setHidden(String personId, bool hidden) {
    people[personId]?.hidden = hidden;
    _changed();
  }

  /// Forgets photos that no longer exist.
  void prune(Set<String> existingAssetIds) {
    faces.removeWhere((_, f) => !existingAssetIds.contains(f.assetId));
    scanned.removeWhere((a) => !existingAssetIds.contains(a));
    _changed();
  }

  Future<void> resetAll() async {
    faces.clear();
    people.clear();
    scanned.clear();
    _changed();
  }

  void _changed() {
    for (final p in people.values) {
      if (p.coverFaceId == null || faces[p.coverFaceId]?.personId != p.id) {
        p.coverFaceId = faces.values.where((f) => f.personId == p.id).firstOrNull?.id;
      }
    }
    save();
    notifyListeners();
  }

  void notify() => notifyListeners();
}

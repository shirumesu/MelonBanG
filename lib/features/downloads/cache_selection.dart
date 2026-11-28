import 'dart:math' as math;

import '../../domain/transfer.dart';

/// A row of the cache page: a task, or one video of a finished batch.
typedef CachePick = ({String task, String? file});

/// The cache rows picked to delete together, as in a file manager: a click
/// picks one row, or lets go of it when it was the only one; a Ctrl or Cmd
/// click adds or removes one; a Shift click picks the rows from the last
/// clicked one, within the same show. A picked batch includes its videos.
class CacheSelection {
  final _picks = <CachePick>{};
  CachePick? _anchor;
  String? _anchorEntry;

  int get length => _picks.length;
  bool get isEmpty => _picks.isEmpty;

  /// Whether [pick] is picked itself or through its batch.
  bool contains(CachePick pick) =>
      _picks.contains(pick) ||
      (pick.file != null && _picks.contains((task: pick.task, file: null)));

  /// A click on [pick], one of [rows]: the picks of [entry], one show, in
  /// the order they show.
  void click(
    String entry,
    List<CachePick> rows,
    CachePick pick, {
    required bool toggle,
    required bool range,
  }) {
    final anchor = _anchor;
    if (range && anchor != null && _anchorEntry == entry) {
      final from = rows.indexOf(anchor), to = rows.indexOf(pick);
      if (from >= 0 && to >= 0) {
        if (!toggle) _picks.clear();
        _picks.addAll(rows.sublist(math.min(from, to), math.max(from, to) + 1));
        _settle();
        return;
      }
    }
    final whole = (task: pick.task, file: null);
    if (toggle) {
      if (pick.file != null && _picks.remove(whole)) {
        // Letting go of one video of a picked batch keeps the others.
        _picks.addAll(
          rows.where((row) => row.task == pick.task && row.file != null),
        );
        _picks.remove(pick);
      } else if (!_picks.remove(pick)) {
        _picks.add(pick);
      }
    } else if (_picks.length == 1 && _picks.contains(pick)) {
      _picks.clear();
    } else {
      _picks
        ..clear()
        ..add(pick);
    }
    _anchor = pick;
    _anchorEntry = entry;
    _settle();
  }

  /// Picks [pick] alone, for a menu opened on a row outside the picks.
  void only(String entry, CachePick pick) {
    _picks
      ..clear()
      ..add(pick);
    _anchor = pick;
    _anchorEntry = entry;
  }

  void clear() {
    _picks.clear();
    _anchor = _anchorEntry = null;
  }

  /// Drops the picks [keep] refuses, such as rows that were deleted or
  /// left the view.
  void retain(bool Function(CachePick pick) keep) {
    _picks.retainWhere(keep);
    if (_anchor case final anchor? when !keep(anchor)) {
      _anchor = _anchorEntry = null;
    }
  }

  /// A picked batch's videos need no picks of their own.
  void _settle() => _picks.removeWhere(
    (pick) =>
        pick.file != null && _picks.contains((task: pick.task, file: null)),
  );

  /// What deleting the picks removes from [tasks]: whole tasks, and videos
  /// of the others; a batch whose every video is picked goes whole.
  ({Set<String> tasks, Map<String, Set<String>> files}) resolve(
    Map<String, DownloadTask> tasks,
  ) {
    final whole = <String>{};
    final files = <String, Set<String>>{};
    for (final pick in _picks) {
      if (!tasks.containsKey(pick.task)) continue;
      switch (pick.file) {
        case null:
          whole.add(pick.task);
        case final file:
          files.putIfAbsent(pick.task, () => {}).add(file);
      }
    }
    for (final id in files.keys.toList()) {
      if (tasks[id]!.videos.every((video) => files[id]!.contains(video.id))) {
        files.remove(id);
        whole.add(id);
      }
    }
    return (tasks: whole, files: files);
  }

  /// The bytes deleting the picks frees.
  int bytes(Map<String, DownloadTask> tasks) {
    final removed = resolve(tasks);
    var sum = 0;
    for (final id in removed.tasks) {
      sum += tasks[id]!.totalBytes;
    }
    for (final MapEntry(key: id, value: ids) in removed.files.entries) {
      for (final file in tasks[id]!.files) {
        if (ids.contains(file.id)) sum += file.size;
      }
    }
    return sum;
  }
}

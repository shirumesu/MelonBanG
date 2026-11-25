import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// What a notice is about: a plain message, something finished, something
/// to look at, or something that failed.
enum NoticeTone { info, done, warning, failed }

/// A button on a notice; pressing it also closes the notice.
class NoticeAction {
  const NoticeAction(this.label, this.onPressed);
  final String label;
  final VoidCallback onPressed;
}

/// A message shown as a card in the window's corner: what happened, why it
/// matters in a second line, and what to do about it.
class Notice {
  const Notice(
    this.title, {
    this.detail,
    this.tone = NoticeTone.info,
    this.actions = const [],
    this.key,
    this.sticky = false,
    this.onOpen,
  });
  final String title;
  final String? detail;
  final NoticeTone tone;
  final List<NoticeAction> actions;

  /// A notice with the key of one still shown takes its place instead of
  /// adding a card, so a state that changes says so once.
  final Object? key;

  /// Stays until closed or acted on, for a choice that waits, such as an
  /// update to restart for.
  final bool sticky;

  /// Clicking the card itself, such as opening the show it is about.
  final VoidCallback? onOpen;

  /// Long enough to read: a few words go after four seconds, a sentence
  /// stays longer; one with buttons waits for a decision, and a failure is
  /// read twice.
  Duration get duration {
    final length = title.length + (detail?.length ?? 0);
    var milliseconds = (3000 + 60 * length).clamp(4000, 9000);
    if (actions.isNotEmpty) milliseconds += 3000;
    if (tone == NoticeTone.failed) {
      milliseconds = math.max(milliseconds, 8000);
    }
    return Duration(milliseconds: milliseconds);
  }
}

/// A notice on screen, with the time it has left.
class ShownNotice {
  ShownNotice._(this.id, this.notice, this._owner) : _left = notice.duration;
  final int id;
  Notice notice;
  final Notices _owner;
  Duration _left;
  final _running = Stopwatch();
  Timer? _timer;
  bool _held = false;

  /// The time left before it closes itself.
  Duration get left {
    if (_timer == null) return _left;
    final left = _left - _running.elapsed;
    return left.isNegative ? Duration.zero : left;
  }

  /// Whether that time is running now: not while the pointer rests on it,
  /// the window cannot be seen, or it waits for a decision.
  bool get running => _timer != null;

  void _resume() {
    _pause();
    if (notice.sticky || _held || _owner._away) return;
    _running
      ..reset()
      ..start();
    _timer = Timer(_left, () => _owner.dismiss(this));
  }

  void _pause() {
    if (_timer == null) return;
    _timer!.cancel();
    _timer = null;
    _running.stop();
    _left -= _running.elapsed;
    if (_left.isNegative) _left = Duration.zero;
  }

  /// Starts its time over, for a notice that replaced the one shown.
  void _restart(Notice next) {
    notice = next;
    _pause();
    _left = next.duration;
    _resume();
  }
}

/// The notices the window shows, oldest first. Their time runs only while
/// the window can be seen: one that arrives while it is minimized or hidden
/// to the tray waits there until it shows again. Behind another app it
/// still shows, so time runs there.
///
/// It tells its listeners when a notice comes, goes or changes, and when
/// one's time stops or runs again.
class Notices extends ChangeNotifier {
  /// Cards shown at once; a new one beyond them closes the oldest.
  static const limit = 4;

  final _shown = <ShownNotice>[];
  int _ids = 0;
  bool _away = false;

  List<ShownNotice> get shown => List.unmodifiable(_shown);

  void show(Notice notice) {
    if (notice.key case final key?) {
      for (final entry in _shown) {
        if (entry.notice.key == key) {
          entry._restart(notice);
          notifyListeners();
          return;
        }
      }
    }
    final entry = ShownNotice._(++_ids, notice, this);
    _shown.add(entry);
    while (_shown.length > limit) {
      // The oldest one not being read or waiting on a decision goes first,
      // else the oldest of all; never the one just shown.
      final oldest = _shown
          .take(_shown.length - 1)
          .firstWhere(
            (shown) => !shown._held && !shown.notice.sticky,
            orElse: () => _shown.first,
          );
      oldest._pause();
      _shown.remove(oldest);
    }
    entry._resume();
    notifyListeners();
  }

  void dismiss(ShownNotice entry) {
    if (!_shown.remove(entry)) return;
    entry._pause();
    notifyListeners();
  }

  /// Closes the notice shown under [key], if one is.
  void dismissKey(Object key) {
    for (final entry in [..._shown]) {
      if (entry.notice.key == key) dismiss(entry);
    }
  }

  /// Keeps [entry] while the pointer rests on it.
  void hold(ShownNotice entry, bool held) {
    if (entry._held == held) return;
    entry._held = held;
    held ? entry._pause() : entry._resume();
    notifyListeners();
  }

  /// Set while the window cannot be seen: minimized or hidden to the tray.
  set away(bool value) {
    if (_away == value) return;
    _away = value;
    for (final entry in _shown) {
      value ? entry._pause() : entry._resume();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    for (final entry in _shown) {
      entry._pause();
    }
    super.dispose();
  }
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app_services.dart';

class Playback extends ChangeNotifier {
  Playback(this.service, this.preferences) {
    video = VideoController(player);
    _subscriptions.add(
      player.stream.error.listen((value) {
        error = value;
        notifyListeners();
      }),
    );
    _subscriptions.add(
      player.stream.completed.listen((done) {
        if (done) unawaited(saveProgress(ended: true));
      }),
    );
    _subscriptions.add(
      player.stream.playing.listen((_) {
        unawaited(saveProgress());
      }),
    );
    _lastAudibleVolume = player.state.volume > 0 ? player.state.volume : 80;
    _subscriptions.add(
      player.stream.volume.listen((volume) {
        if (volume > 0) _lastAudibleVolume = volume;
      }),
    );
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(saveProgress());
    });
  }
  final AppServices service;
  final SharedPreferences preferences;
  final player = Player(
    configuration: const PlayerConfiguration(title: 'Melonbang', libass: true),
  );
  late final VideoController video;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  Timer? _timer;
  Json? session;
  String? uri;
  String? error;
  bool opening = false;
  bool _closed = false;
  bool danmakuEnabled = true;
  double subtitleDelay = 0;
  double danmakuOpacity = .9;
  double danmakuSize = 23;
  double danmakuArea = .6;
  List<Json> comments = [];
  Future<void> _openQueue = Future.value();
  Future<void> _progressWrites = Future.value();
  Future<void>? _closing;
  double _lastAudibleVolume = 80;

  Future<void> toggleMute() async {
    final volume = player.state.volume;
    if (volume > 0) _lastAudibleVolume = volume;
    await player.setVolume(volume == 0 ? _lastAudibleVolume : 0);
  }

  Future<void> offsetSubtitle(double delta) async {
    subtitleDelay += delta;
    final platform = player.platform;
    if (platform is NativePlayer) {
      await platform.setProperty('sub-delay', '$subtitleDelay');
    }
  }

  Future<void> open(Json next) {
    if (_closed) return Future.error(StateError('播放器已关闭'));
    final operation = _openQueue.then((_) => _open(next));
    _openQueue = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _open(Json next) async {
    if (_closed) return;
    await saveProgress();
    opening = true;
    error = null;
    notifyListeners();
    try {
      if (next['status'] == 'failed') {
        throw StateError('${next['errorMessage']}');
      }
      session = next;
      comments = [];
      subtitleDelay = 0;
      uri = object(next['source'])['url'] as String?;
      if (uri == null) throw StateError('没有可播放的文件。');
      final platform = player.platform;
      if (platform is NativePlayer) {
        await platform.setProperty('sub-auto', 'fuzzy');
        await platform.setProperty('sub-ass-override', 'no');
        await platform.setProperty('sub-delay', '0');
      }
      await player.open(Media(uri!), play: false);
      if (Platform.environment['MELONBANG_MUTE_AUDIO'] == '1') {
        await player.setVolume(0);
      }
      var resume = preferences.getDouble('progress:$uri') ?? 0;
      if (next['subjectId'] != null && next['episodeId'] != null) {
        try {
          final saved = object(
            await service.library.progress(
              next['subjectId'] as int,
              next['episodeId'] as int,
            ),
          );
          if (saved['completed'] == true) {
            resume = 0;
          } else if (saved.isNotEmpty) {
            resume = number(saved['positionSeconds']);
          }
        } catch (_) {}
      }
      if (resume > 0) {
        await player.seek(Duration(milliseconds: (resume * 1000).round()));
      }
      await player.play();
      if (!_closed && service.library.current?['id'] == next['id']) {
        unawaited(
          service.library.autoMatch(
            player.state.duration.inMilliseconds / 1000,
            sessionId: next['id'] as String,
          ),
        );
      }
    } catch (e) {
      error = e.toString();
      session = null;
      uri = null;
      await player.stop();
      rethrow;
    } finally {
      opening = false;
      notifyListeners();
    }
  }

  Future<void> openLocal(String path, {int? subjectId, int? episodeId}) async {
    await saveProgress();
    Json next;
    try {
      next = object(
        await service.library.local(
          path,
          subjectId: subjectId,
          episodeId: episodeId,
        ),
      );
    } catch (_) {
      if (!File(path).existsSync()) rethrow;
      // Local playback remains usable independently of account/download services.
      next = {
        'id': 'local',
        'title': Uri.file(path).pathSegments.last,
        'source': {'url': Uri.file(path).toString()},
        'status': 'ready',
      };
    }
    await open(next);
  }

  void accept(Json next) {
    if (next['id'] != session?['id']) return;
    session = next;
    final incoming = objects(next['danmaku']);
    if (incoming.isNotEmpty || comments.isNotEmpty) comments = incoming;
    notifyListeners();
  }

  Future<void> saveProgress({bool ended = false}) {
    if (uri == null || session == null || opening) return _progressWrites;
    final savedUri = uri!;
    final savedSession = session!;
    ended = ended || player.state.completed;
    final position = player.state.position.inMilliseconds / 1000;
    final duration = player.state.duration.inMilliseconds / 1000;
    final completed = ended;
    return _progressWrites = _progressWrites.then((_) async {
      try {
        await preferences.setDouble(
          'progress:$savedUri',
          completed ? 0 : position,
        );
        await service.library.save(savedSession, position, duration, completed);
      } catch (_) {
        /* Playback is independent of progress storage availability. */
      }
    });
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    _timer?.cancel();
    await _openQueue;
    await saveProgress();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await player.dispose();
  }
}

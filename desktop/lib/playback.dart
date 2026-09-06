import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'service.dart';

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
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(saveProgress());
    });
  }
  final Service service;
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
  double danmakuOpacity = .9;
  double danmakuSize = 23;
  double danmakuArea = .6;
  List<Json> comments = [];
  Future<void> _openQueue = Future.value();

  Future<void> open(Json next) {
    final operation = _openQueue.then((_) => _open(next));
    _openQueue = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _open(Json next) async {
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
      uri = object(next['source'])['url'] as String?;
      if (uri == null) throw StateError('没有可播放的文件。');
      final platform = player.platform;
      if (platform is NativePlayer) {
        await platform.setProperty('sub-auto', 'fuzzy');
        await platform.setProperty('sub-ass-override', 'no');
      }
      await player.open(Media(uri!), play: false);
      if (Platform.environment['MELONBANG_MUTE_AUDIO'] == '1') {
        await player.setVolume(0);
      }
      var resume = preferences.getDouble('progress:$uri') ?? 0;
      if (next['subjectId'] != null && next['episodeId'] != null) {
        try {
          final saved = object(
            await service.call('playback.getEpisodeProgress', [
              {'subjectId': next['subjectId'], 'episodeId': next['episodeId']},
            ]),
          );
          if (saved['completed'] != true) {
            resume = number(saved['positionSeconds']);
          }
        } catch (_) {}
      }
      if (resume > 0) {
        await player.seek(Duration(milliseconds: (resume * 1000).round()));
      }
      await preferences.setString('lastMedia', jsonEncodeSession(next));
      await player.play();
    } catch (e) {
      error = e.toString();
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
        await service.call('playback.startLocal', [
          {'path': path, 'subjectId': ?subjectId, 'episodeId': ?episodeId},
        ]),
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

  Future<void> saveProgress({bool ended = false}) async {
    if (uri == null || session == null || opening) return;
    ended = ended || player.state.completed;
    final position = player.state.position.inMilliseconds / 1000;
    final duration = player.state.duration.inMilliseconds / 1000;
    try {
      await preferences.setDouble('progress:$uri', ended ? 0 : position);
      if (session!['id'] != 'local') {
        await service.call('playback.updateProgress', [
          {
            'sessionId': session!['id'],
            'positionSeconds': position,
            'durationSeconds': duration > 0 ? duration : null,
            'timelineOffsetSeconds': 0,
            'paused': !player.state.playing,
            'ended': ended,
          },
        ]);
      }
    } catch (_) {
      /* Playback is independent of progress storage availability. */
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    await saveProgress();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await player.dispose();
  }
}

// History stores only the media locator and episode association, never credentials.
String jsonEncodeSession(Json session) => '${object(session['source'])['url']}';

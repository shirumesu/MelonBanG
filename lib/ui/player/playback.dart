import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../app_services.dart';
import 'playback_preferences.dart';

class Playback extends ChangeNotifier {
  Playback(this.service, this.preferences) {
    settings = PlaybackPreferences(preferences);
    danmaku = DanmakuPreferences(preferences);
    danmaku.addListener(_presentationChanged);
    settings.addListener(_settingsChanged);
    _savedRate = preferences.getDouble('player-rate') ?? 1;
    unawaited(player.setRate(_savedRate));
    video = VideoController(player);
    _subscriptions.add(
      player.stream.error.listen((value) {
        error = value;
        notifyListeners();
      }),
    );
    _subscriptions.add(
      player.stream.completed.listen((done) {
        if (done && !opening) {
          unawaited(saveProgress(ended: true));
          unawaited(_prepareAutoplay());
        }
      }),
    );
    _subscriptions.add(
      player.stream.playing.listen((_) {
        unawaited(saveProgress());
      }),
    );
    _lastAudibleVolume = preferences.getDouble(_volumeKey) ?? 80;
    if (preferences.getBool(_mutedKey) == true) {
      unawaited(player.setVolume(0));
    } else {
      unawaited(player.setVolume(_lastAudibleVolume));
    }
    _subscriptions.add(
      player.stream.volume.listen((volume) {
        if (volume > 0) _lastAudibleVolume = volume;
        if (Platform.environment['MELONBANG_MUTE_AUDIO'] == '1') return;
        // Sliders emit continuously; persist once the value settles.
        _volumeWrite?.cancel();
        _volumeWrite = Timer(const Duration(milliseconds: 400), () {
          unawaited(preferences.setDouble(_volumeKey, _lastAudibleVolume));
          unawaited(preferences.setBool(_mutedKey, volume == 0));
        });
      }),
    );
    _subscriptions.add(
      player.stream.rate.listen((rate) {
        if (opening) return;
        _savedRate = rate;
        _rateWrite?.cancel();
        _rateWrite = Timer(
          const Duration(milliseconds: 400),
          () => unawaited(preferences.setDouble('player-rate', rate)),
        );
      }),
    );
    _subscriptions.add(
      player.stream.tracks.listen((tracks) {
        if (!opening) unawaited(_preferTracks(tracks));
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
  Timer? _timer, _volumeWrite, _rateWrite, _autoplayTimer;
  late final PlaybackPreferences settings;
  late final DanmakuPreferences danmaku;
  double _savedRate = 1;
  bool frameStepping = false;
  bool _manualSubtitle = false, _manualAudio = false;
  bool _scoredSubtitle = false, _scoredAudio = false;
  int danmakuRevision = 0, _autoplayTicket = 0;
  String? _completedSession;
  Future<AutoplayTarget?> Function(Json session)? resolveNext;
  AutoplayTarget? autoplayTarget;
  Json? autoplayEndEpisode;
  String? autoplayMessage;
  int autoplaySeconds = 0;
  List<Json> _comments = [];
  List<Json> visibleComments = [];
  Map<String, double> danmakuOffsets = {};
  Future<void>? _offsetTable;
  static const _volumeKey = 'player-volume', _mutedKey = 'player-muted';
  Json? session;
  String? uri;
  String? error, notice;
  Media? _manifest;
  void showNotice(String value) {
    notice = value;
    notifyListeners();
  }

  void showResourceFailure(Json episode) {
    cancelAutoplay(notify: false);
    autoplayEndEpisode = episode;
    autoplayMessage = '第 ${episode['sort']} 话暂无可直接播放的资源';
    notifyListeners();
  }

  bool opening = false;
  bool _closed = false;
  bool get danmakuEnabled => danmaku.enabled;
  set danmakuEnabled(bool value) =>
      danmaku.update(() => danmaku.enabled = value);
  double subtitleDelay = 0;
  double get danmakuOpacity => danmaku.opacity;
  set danmakuOpacity(double value) =>
      danmaku.update(() => danmaku.opacity = value);
  double get danmakuSize => danmaku.size;
  set danmakuSize(double value) => danmaku.update(() => danmaku.size = value);
  double get danmakuArea => danmaku.area;
  set danmakuArea(double value) => danmaku.update(() => danmaku.area = value);
  List<Json> get comments => _comments;
  set comments(List<Json> value) {
    _comments = value;
    _presentationChanged();
  }

  Future<void> _openQueue = Future.value();
  Future<void> _frameQueue = Future.value();
  Future<void> _progressWrites = Future.value();
  Future<void>? _closing;
  double _lastAudibleVolume = 80;

  Future<void> resume() async {
    cancelAutoplay();
    if (frameStepping) {
      frameStepping = false;
      danmakuRevision++;
      notifyListeners();
    }
    await player.play();
  }

  Future<void> playOrPause() =>
      player.state.playing ? player.pause() : resume();

  Future<void> toggleMute() async {
    cancelAutoplay();
    final volume = player.state.volume;
    if (volume > 0) _lastAudibleVolume = volume;
    await player.setVolume(volume == 0 ? _lastAudibleVolume : 0);
  }

  /// Adjusts volume by [delta] percent and returns the new value.
  Future<double> adjustVolume(double delta) async {
    cancelAutoplay();
    final next = (player.state.volume + delta).clamp(0.0, 100.0);
    await player.setVolume(next);
    return next;
  }

  void toggleDanmaku() {
    cancelAutoplay();
    danmakuEnabled = !danmakuEnabled;
  }

  Future<void> offsetSubtitle(double delta) async {
    cancelAutoplay();
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
    cancelAutoplay();
    _completedSession = null;
    autoplayEndEpisode = null;
    autoplayMessage = null;
    frameStepping = false;
    _manualSubtitle = _manualAudio = _scoredSubtitle = _scoredAudio = false;
    opening = true;
    error = null;
    notifyListeners();
    try {
      if (next['status'] == 'failed') {
        throw StateError('${next['errorMessage']}');
      }
      session = next;
      comments = [];
      danmakuOffsets = {};
      await _loadOffsets(next);
      subtitleDelay = 0;
      uri = object(next['source'])['url'] as String?;
      if (uri == null) throw StateError('没有可播放的文件。');
      final platform = player.platform;
      if (platform is NativePlayer) {
        final filteredHls = object(next['source'])['playlist'] is String;
        await platform.setProperty('demuxer', filteredHls ? 'lavf' : 'auto');
        await platform.setProperty(
          'demuxer-lavf-format',
          filteredHls ? 'hls' : '',
        );
        await platform.setProperty('sub-auto', 'fuzzy');
        await platform.setProperty('sub-ass-override', 'no');
        await platform.setProperty('sub-delay', '0');
        await platform.setProperty(
          'slang',
          languageCodes(settings.subtitleLanguage),
        );
        await platform.setProperty(
          'alang',
          languageCodes(settings.audioLanguage),
        );
      }
      var resume = preferences.getDouble(
        'progress:${next['resumeKey'] ?? uri}',
      );
      if (resume == null && next['path'] is String) {
        final path = next['path'] as String;
        resume = preferences.getDouble('progress:${Uri.file(path)}');
        final storage = service.storage;
        if (resume == null &&
            storage != null &&
            p.isWithin(storage.media, path)) {
          for (final previous in storage.previousMedia.reversed) {
            final oldPath = p.join(
              previous,
              p.relative(path, from: storage.media),
            );
            resume = preferences.getDouble('progress:${Uri.file(oldPath)}');
            if (resume != null) break;
          }
        }
      }
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
      if (next['startSeconds'] is num) resume = number(next['startSeconds']);
      // Apply continuation while loading; open() can return before native seek is ready.
      final source = object(next['source']);
      _manifest = source['playlist'] is String
          ? await Media.memory(
              Uint8List.fromList(utf8.encode(source['playlist'] as String)),
            )
          : null;
      await player.open(
        Media(
          _manifest?.uri ?? uri!,
          httpHeaders: object(object(next['source'])['headers'])
              .map((key, value) => MapEntry(key, '$value')),
          start: Duration(milliseconds: ((resume ?? 0) * 1000).round()),
        ),
        play: false,
      );
      if (Platform.environment['MELONBANG_MUTE_AUDIO'] == '1') {
        await player.setVolume(0);
      }
      await player.setRate(_savedRate);
      await _preferTracks(player.state.tracks);
      service.releasePlaybackStreams(next['streamId'] as int?);
      await player.play();
      if (!_closed &&
          next['standalone'] != true &&
          service.library.current?['id'] == next['id']) {
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
      service.releasePlaybackStreams(null);
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
        'id': newId(),
        'standalone': true,
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
    final savedUri = session!['resumeKey'] ?? uri!;
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

  void _settingsChanged() {
    if (!settings.autoplay) cancelAutoplay();
    notifyListeners();
  }

  void _presentationChanged() {
    visibleComments = danmaku.visible(_comments, danmakuOffsets);
    danmakuRevision++;
    notifyListeners();
  }

  Future<void> _ensureOffsetTable() =>
      _offsetTable ??= service.store.database.execute(
        'CREATE TABLE IF NOT EXISTS danmaku_offsets (resume_key TEXT NOT NULL, source TEXT NOT NULL, seconds REAL NOT NULL, PRIMARY KEY(resume_key,source))',
      );

  Future<void> _loadOffsets(Json next) async {
    final key = next['resumeKey'] ?? object(next['source'])['url'];
    if (key == null) return;
    try {
      await _ensureOffsetTable();
      final rows = await service.store.database.query(
        'danmaku_offsets',
        where: 'resume_key=?',
        whereArgs: ['$key'],
      );
      if (session?['id'] != next['id']) return;
      danmakuOffsets = {
        for (final row in rows) '${row['source']}': number(row['seconds']),
      };
      _presentationChanged();
    } catch (_) {
      _offsetTable = null;
      /* Standalone playback may precede database startup. */
    }
  }

  Future<void> offsetDanmaku(String provider, double seconds) async {
    final key = session?['resumeKey'] ?? uri;
    if (key == null) return;
    danmakuOffsets = {...danmakuOffsets, provider: seconds};
    _presentationChanged();
    await _ensureOffsetTable();
    await service.store.database.rawInsert(
      'INSERT OR REPLACE INTO danmaku_offsets (resume_key,source,seconds) VALUES (?,?,?)',
      ['$key', provider, seconds],
    );
  }

  Future<void> selectSubtitle(SubtitleTrack track) async {
    cancelAutoplay();
    _manualSubtitle = true;
    await player.setSubtitleTrack(track);
  }

  Future<void> selectAudio(AudioTrack track) async {
    cancelAutoplay();
    _manualAudio = true;
    await player.setAudioTrack(track);
  }

  Future<void> _preferTracks(Tracks tracks) async {
    final id = session?['id'];
    if (id == null) return;
    if (!_manualSubtitle && !_scoredSubtitle) {
      final candidates = tracks.subtitle
          .where((track) => track.id != 'auto' && track.id != 'no')
          .toList();
      if (candidates.isNotEmpty) {
        _scoredSubtitle = true;
        candidates.sort(
          (a, b) =>
              languageScore(
                settings.subtitleLanguage,
                b.language,
                b.title ?? b.id,
              ).compareTo(
                languageScore(
                  settings.subtitleLanguage,
                  a.language,
                  a.title ?? a.id,
                ),
              ),
        );
        final best = candidates.first;
        final selected = player.state.track.subtitle;
        if (languageScore(
                  settings.subtitleLanguage,
                  best.language,
                  best.title ?? best.id,
                ) >
                languageScore(
                  settings.subtitleLanguage,
                  selected.language,
                  selected.title ?? selected.id,
                ) &&
            session?['id'] == id &&
            !_manualSubtitle) {
          await player.setSubtitleTrack(best);
        }
      }
    }
    if (!_manualAudio && !_scoredAudio) {
      final candidates = tracks.audio
          .where((track) => track.id != 'auto' && track.id != 'no')
          .toList();
      if (candidates.isNotEmpty) {
        _scoredAudio = true;
        candidates.sort(
          (a, b) => languageScore(settings.audioLanguage, b.language, b.title)
              .compareTo(
                languageScore(settings.audioLanguage, a.language, a.title),
              ),
        );
        final best = candidates.first;
        final selected = player.state.track.audio;
        if (languageScore(settings.audioLanguage, best.language, best.title) >
                languageScore(
                  settings.audioLanguage,
                  selected.language,
                  selected.title,
                ) &&
            session?['id'] == id &&
            !_manualAudio) {
          await player.setAudioTrack(best);
        }
      }
    }
  }

  Future<Duration> stepFrame(bool forward) {
    final id = session?['id'];
    final operation = _frameQueue.then(
      (_) => session?['id'] == id
          ? _stepFrame(forward)
          : Future.value(player.state.position),
    );
    _frameQueue = operation.then<void>((_) {}).catchError((Object _) {});
    return operation;
  }

  Future<Duration> _stepFrame(bool forward) async {
    cancelAutoplay();
    final platform = player.platform;
    if (platform is! NativePlayer) throw StateError('当前播放器不支持逐帧');
    frameStepping = true;
    await player.pause();
    notifyListeners();
    final id = session?['id'];
    final before = double.tryParse(await platform.getProperty('time-pos'));
    if (!forward && before != null && before <= 0) return Duration.zero;
    await platform.command([forward ? 'frame-step' : 'frame-back-step']);
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    double? position;
    do {
      position = double.tryParse(await platform.getProperty('time-pos'));
      if (position != null &&
          position != before &&
          await platform.getProperty('seeking') != 'yes') {
        break;
      }
      if (!DateTime.now().isBefore(deadline) ||
          _closed ||
          session?['id'] != id) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    } while (true);
    return Duration(
      microseconds:
          ((position ?? player.state.position.inMicroseconds / 1000000) *
                  1000000)
              .round(),
    );
  }

  Future<void> _prepareAutoplay() async {
    final current = session;
    if (!settings.autoplay ||
        current == null ||
        current['subjectId'] == null ||
        current['episodeId'] == null ||
        current['standalone'] == true ||
        _completedSession == current['id'] ||
        resolveNext == null) {
      return;
    }
    _completedSession = current['id'] as String?;
    final ticket = ++_autoplayTicket;
    try {
      final target = await resolveNext!(Map<String, dynamic>.from(current));
      if (_closed ||
          ticket != _autoplayTicket ||
          session?['id'] != current['id']) {
        return;
      }
      if (target == null) {
        autoplayMessage = '播放已结束';
        notifyListeners();
        return;
      }
      if (target.unavailable) {
        autoplayEndEpisode = target.episode;
        autoplayMessage = '第 ${target.episode['sort']} 话暂无可直接播放的资源';
        notifyListeners();
        return;
      }
      autoplayTarget = target;
      autoplaySeconds = 5;
      notifyListeners();
      _autoplayTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        autoplaySeconds--;
        if (autoplaySeconds <= 0) {
          unawaited(playAutoplay());
        } else {
          notifyListeners();
        }
      });
    } catch (e) {
      if (ticket != _autoplayTicket) return;
      autoplayMessage = '自动连播已停止：$e';
      notifyListeners();
    }
  }

  void cancelAutoplay({bool notify = true}) {
    final changed = autoplayTarget != null;
    _autoplayTicket++;
    _autoplayTimer?.cancel();
    _autoplayTimer = null;
    autoplayTarget = null;
    autoplaySeconds = 0;
    if (changed && notify) notifyListeners();
  }

  Future<void> playAutoplay() async {
    final target = autoplayTarget;
    if (target == null) return;
    cancelAutoplay();
    try {
      await target.play();
    } catch (e) {
      autoplayMessage = '下一话打开失败：$e';
      notifyListeners();
    }
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    _timer?.cancel();
    _volumeWrite?.cancel();
    _rateWrite?.cancel();
    cancelAutoplay();
    await preferences.setDouble('player-rate', _savedRate);
    danmaku.removeListener(_presentationChanged);
    settings.removeListener(_settingsChanged);
    await _openQueue;
    await _frameQueue;
    await saveProgress();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await player.dispose();
    service.releasePlaybackStreams(null);
  }
}

class AutoplayTarget {
  const AutoplayTarget({
    required this.episode,
    required this.sourceLabel,
    required this.play,
    this.unavailable = false,
  });
  final Json episode;
  final String sourceLabel;
  final Future<void> Function() play;
  final bool unavailable;
}

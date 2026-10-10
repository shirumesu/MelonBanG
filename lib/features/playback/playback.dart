import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/catalog.dart';
import '../../domain/playback_session.dart';
import '../../domain/sources.dart';
import '../danmaku/danmaku_controller.dart';
import '../danmaku/danmaku_repository.dart';
import '../downloads/download_repository.dart';
import 'playback_library.dart';
import 'playback_preferences.dart';

class Playback extends ChangeNotifier {
  Playback(this.library, this.downloads, this.danmaku, this.preferences) {
    settings = PlaybackPreferences(preferences);
    danmaku.addListener(_danmakuChanged);
    settings.addListener(_settingsChanged);
    _savedRate = preferences.getDouble('player-rate') ?? 1;
    unawaited(player.setRate(_savedRate));
    video = VideoController(player);
    _subscriptions.add(
      player.stream.error.listen((value) {
        error ??= value;
        notifyListeners();
      }),
    );
    _subscriptions.add(
      player.stream.completed.listen((done) {
        if (done && !opening && error == null) {
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
  final PlaybackLibrary library;
  final DownloadRepository downloads;
  final DanmakuController danmaku;
  final SharedPreferences preferences;
  final player = Player(
    configuration: const PlayerConfiguration(title: 'Melonbang', libass: true),
  );
  late final VideoController video;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  Timer? _timer, _volumeWrite, _rateWrite, _autoplayTimer;
  late final PlaybackPreferences settings;
  double _savedRate = 1;
  bool frameStepping = false;
  bool _manualSubtitle = false, _manualAudio = false;
  bool _scoredSubtitle = false, _scoredAudio = false;
  int danmakuRevision = 0, _autoplayTicket = 0;
  String? _completedSession;
  Future<AutoplayTarget?> Function(PlaybackSession session)? resolveNext;
  AutoplayTarget? autoplayTarget;
  Episode? autoplayEndEpisode;
  String? autoplayMessage;
  int autoplaySeconds = 0;
  static const _volumeKey = 'player-volume', _mutedKey = 'player-muted';
  PlaybackSession? session;
  String? uri;
  String? error, notice;
  Media? _manifest;
  void showNotice(String value) {
    notice = value;
    notifyListeners();
  }

  void showResourceFailure(Episode episode) {
    cancelAutoplay(notify: false);
    autoplayEndEpisode = episode;
    autoplayMessage = '第 ${episode.number} 话暂无可直接播放的资源';
    notifyListeners();
  }

  bool opening = false;
  bool _closed = false;
  bool get danmakuEnabled => danmaku.preferences.enabled;
  double subtitleDelay = 0;

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
    final preferences = danmaku.preferences;
    preferences.update(() => preferences.enabled = !preferences.enabled);
  }

  Future<void> offsetSubtitle(double delta) async {
    cancelAutoplay();
    subtitleDelay += delta;
    final platform = player.platform;
    if (platform is NativePlayer) {
      await platform.setProperty('sub-delay', '$subtitleDelay');
    }
  }

  Future<void> open(PlaybackSession next) {
    if (_closed) return Future.error(StateError('播放器已关闭'));
    final operation = _openQueue.then((_) => _open(next));
    _openQueue = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _open(PlaybackSession next) async {
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
      await library.activate(next);
      session = next;
      final danmakuTarget = DanmakuTarget(
        matchKey: next.path ?? next.resumeKey,
        offsetKey: next.progressKey,
        embedded: next.danmaku,
        subjectId: next.subjectId,
        episodeId: next.episodeId,
        path: next.path,
        fileSize: next.fileSize,
        remote: next.remote || next.streamId != null,
      );
      await danmaku.begin(danmakuTarget);
      subtitleDelay = 0;
      uri = next.url;
      final playlist = next.playlist;
      final platform = player.platform;
      if (platform is NativePlayer) {
        await platform.setProperty('demuxer', playlist != null ? 'lavf' : '');
        await platform.setProperty(
          'demuxer-lavf-format',
          playlist != null
              ? next.format == StreamFormat.dash
                    ? 'dash'
                    : 'hls'
              : '',
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
      var resume = preferences.getDouble('progress:${next.progressKey}');
      if (next.subjectId case final subjectId?) {
        if (next.episodeId case final episodeId?) {
          try {
            final saved = await library.progress(subjectId, episodeId);
            if (saved != null) resume = saved.completed ? 0 : saved.position;
          } catch (_) {}
        }
      }
      if (next.startSeconds != null) resume = next.startSeconds;
      // Apply continuation while loading; open() can return before native seek is ready.
      _manifest = playlist != null
          ? await Media.memory(Uint8List.fromList(utf8.encode(playlist)))
          : null;
      await player.open(
        Media(
          _manifest?.uri ?? next.url,
          httpHeaders: next.headers,
          start: Duration(milliseconds: ((resume ?? 0) * 1000).round()),
        ),
        play: false,
      );
      if (Platform.environment['MELONBANG_MUTE_AUDIO'] == '1') {
        await player.setVolume(0);
      }
      await player.setRate(_savedRate);
      await _preferTracks(player.state.tracks);
      downloads.releaseStreamsExcept(next.streamId);
      await player.play();
      if (!_closed && !next.standalone) {
        unawaited(
          danmaku.autoMatch(
            player.state.duration.inMilliseconds / 1000,
            target: danmakuTarget,
          ),
        );
      }
    } catch (e) {
      error = e.toString();
      session = null;
      uri = null;
      await player.stop();
      downloads.releaseStreamsExcept(null);
      rethrow;
    } finally {
      opening = false;
      notifyListeners();
    }
  }

  (Object, Object?, double, double, bool)? _lastProgress;

  Future<void> saveProgress({bool ended = false}) {
    if (uri == null || session == null || opening) return _progressWrites;
    final savedUri = session!.progressKey;
    final savedSession = session!;
    ended = error == null && (ended || player.state.completed);
    final position = player.state.position.inMilliseconds / 1000;
    final duration = player.state.duration.inMilliseconds / 1000;
    final completed = ended;
    final signature = (
      savedUri,
      savedSession.id,
      position,
      duration,
      completed,
    );
    if (_lastProgress == signature) return _progressWrites;
    _lastProgress = signature;
    return _progressWrites = _progressWrites.then((_) async {
      try {
        await preferences.setDouble(
          'progress:$savedUri',
          completed ? 0 : position,
        );
        await library.save(savedSession, position, duration, completed);
      } catch (_) {
        if (_lastProgress == signature) _lastProgress = null;
        /* Playback is independent of progress storage availability. */
      }
    });
  }

  void _settingsChanged() {
    if (!settings.autoplay) cancelAutoplay();
    notifyListeners();
  }

  void _danmakuChanged() {
    danmakuRevision++;
    notifyListeners();
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
    final id = session?.id;
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
            session?.id == id &&
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
            session?.id == id &&
            !_manualAudio) {
          await player.setAudioTrack(best);
        }
      }
    }
  }

  Future<Duration> stepFrame(bool forward) {
    final id = session?.id;
    final operation = _frameQueue.then(
      (_) => session?.id == id
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
    final id = session?.id;
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
          session?.id != id) {
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
        current.subjectId == null ||
        current.episodeId == null ||
        current.standalone ||
        _completedSession == current.id ||
        resolveNext == null) {
      return;
    }
    _completedSession = current.id;
    final ticket = ++_autoplayTicket;
    try {
      final target = await resolveNext!(current);
      if (_closed || ticket != _autoplayTicket || session?.id != current.id) {
        return;
      }
      if (target == null) {
        autoplayMessage = '播放已结束';
        notifyListeners();
        return;
      }
      if (target.unavailable) {
        autoplayEndEpisode = target.episode;
        autoplayMessage = '第 ${target.episode.number} 话暂无可直接播放的资源';
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
    danmaku.removeListener(_danmakuChanged);
    settings.removeListener(_settingsChanged);
    await _openQueue;
    await _frameQueue;
    await saveProgress();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await player.dispose();
    downloads.releaseStreamsExcept(null);
  }
}

class AutoplayTarget {
  const AutoplayTarget({
    required this.episode,
    required this.sourceLabel,
    required this.play,
    this.unavailable = false,
  });
  final Episode episode;
  final String sourceLabel;
  final Future<void> Function() play;
  final bool unavailable;
}

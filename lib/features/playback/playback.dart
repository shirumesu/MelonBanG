import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/error_message.dart';
import '../../core/proxy.dart';
import '../../domain/catalog.dart';
import '../../domain/playback_session.dart';
import '../danmaku/danmaku_controller.dart';
import '../danmaku/danmaku_repository.dart';
import '../downloads/download_repository.dart';
import 'playback_library.dart';
import 'playback_preferences.dart';
import 'super_resolution.dart';

class Playback extends ChangeNotifier {
  Playback(
    this.library,
    this.downloads,
    this.danmaku,
    this.preferences, {
    this.proxy,
  }) {
    settings = PlaybackPreferences(preferences);
    danmaku.addListener(_danmakuChanged);
    settings.addListener(_settingsChanged);
    _savedRate = preferences.getDouble('player-rate') ?? 1;
    unawaited(player.setRate(_savedRate));
    _hwdec = settings.hardwareDecoding;
    video = VideoController(
      player,
      configuration: VideoControllerConfiguration(hwdec: _hwdec),
    );
    unawaited(_applyShaders());
    _subscriptions.add(
      player.stream.videoParams.listen((_) => _scheduleOutputSize()),
    );
    _subscriptions.add(player.stream.position.listen(_skipSongs));
    _subscriptions.add(
      errors.listen((value) {
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
        // A held fast-forward is temporary and never becomes the saved rate.
        if (opening || _boosting) return;
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
    // A forced demuxer must not outlive its file: setting the option back to
    // '' leaves lavf forcing a format named '', so every later file fails
    // with "Failed to recognize file format". File-local options set while
    // the file loads revert to unset when it ends.
    final platform = player.platform;
    if (platform is NativePlayer) {
      platform.onLoadHooks.add(() async {
        if (_httpProxy case final proxy?) {
          await platform.setProperty('file-local-options/http-proxy', proxy);
        }
        final format = _lavfFormat;
        if (format == null) return;
        await platform.setProperty('file-local-options/demuxer', 'lavf');
        await platform.setProperty(
          'file-local-options/demuxer-lavf-format',
          format,
        );
      });
    }
  }
  final PlaybackLibrary library;
  final DownloadRepository downloads;
  final DanmakuController danmaku;
  final SharedPreferences preferences;

  /// Online media goes through the app's proxy; local streams never do.
  final NetworkProxy? proxy;
  final player = Player(
    configuration: const PlayerConfiguration(title: 'Melonbang', libass: true),
  );
  // media_kit forwards FFmpeg's TCP EOF log as an error, including at the
  // end of an HTTP response. It does not mean playback failed.
  Stream<String> get errors => player.stream.error.where(
    (message) => message != 'tcp: ffurl_read returned 0xdfb9b0bb',
  );
  late final VideoController video;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  Timer? _timer, _volumeWrite, _rateWrite, _autoplayTimer;
  late final PlaybackPreferences settings;
  double _savedRate = 1;
  bool frameStepping = false, _boosting = false;
  bool _manualSubtitle = false;
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

  /// The lavf format the file being opened is forced to.
  String? _lavfFormat;

  /// mpv's `http-proxy` for the file being opened.
  String? _httpProxy;
  late String _hwdec;
  String _shaders = 'off';

  /// The player's size in physical pixels, for super-resolution output.
  Size? _display;
  Timer? _outputTimer;

  /// What super-resolution does at the current size: the video's own size
  /// and, when the shaders upscale it, the size they render. Null while it
  /// is off or no video is shown.
  ({Size source, Size? output})? upscale;

  /// Announces [upscale] once it is known, after the player turned
  /// super-resolution on or changed its chain.
  bool _announceUpscale = false;

  /// The OP/ED already skipped automatically in this session, so seeking
  /// back into one plays it.
  bool _skippedOpening = false, _skippedEnding = false;
  double? _lastPosition;

  /// Counts notices, so the same text shown twice appears twice.
  int noticeRevision = 0;
  void showNotice(String value) {
    notice = value;
    noticeRevision++;
    notifyListeners();
  }

  bool opening = false;
  bool _closed = false;
  bool get danmakuEnabled => danmaku.preferences.enabled;

  /// The open file's OP and ED, found in its embedded chapters.
  OpeningEnding? openingEnding;

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

  /// Plays at 3× while [on], as when → is held, then returns to the chosen
  /// rate.
  Future<void> boost(bool on) async {
    if (on == _boosting) return;
    _boosting = on;
    if (on) cancelAutoplay();
    await player.setRate(on ? 3 : _savedRate);
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
    _manualSubtitle = _scoredSubtitle = _scoredAudio = false;
    openingEnding = null;
    _skippedOpening = _skippedEnding = false;
    _lastPosition = null;
    opening = true;
    error = null;
    notifyListeners();
    try {
      await library.activate(next);
      session = next;
      final danmakuTarget = DanmakuTarget(
        matchKey: next.path ?? next.resumeKey,
        embedded: next.danmaku,
        subjectId: next.subjectId,
        episodeId: next.episodeId,
        path: next.path,
        fileSize: next.fileSize,
        remote: next.remote || next.streamId != null,
      );
      danmaku.begin(danmakuTarget);
      uri = next.url;
      final playlist = next.playlist;
      final platform = player.platform;
      if (platform is NativePlayer) {
        // media_kit's 5 s timeout breaks a transfer stream mid-response while
        // the next piece arrives; its local server ends responses itself.
        // 0 leaves FFmpeg's unbounded read.
        await platform.setProperty(
          'network-timeout',
          next.streamId != null ? '0' : '5',
        );
        _lavfFormat = playlist != null ? 'hls' : null;
        final address = Uri.tryParse(next.url);
        _httpProxy =
            next.streamId == null &&
                address != null &&
                address.isScheme('http') | address.isScheme('https')
            ? proxy?.serverFor(address)?.url
            : null;
        // A separate audio track opens as an external file so its requests
        // carry the stream headers; a local manifest's segments would not.
        await platform.command(['change-list', 'audio-files', 'clr', '']);
        if (next.audioUrl case final audio?) {
          await platform.command([
            'change-list',
            'audio-files',
            'append',
            audio,
          ]);
        }
        await platform.setProperty('sub-auto', 'fuzzy');
        await platform.setProperty('sub-ass-override', 'no');
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
      unawaited(_readChapters(next.id));
      if (!_closed && !next.standalone) {
        unawaited(
          danmaku.autoMatch(
            player.state.duration.inMilliseconds / 1000,
            target: danmakuTarget,
          ),
        );
      }
    } catch (e) {
      error = errorMessage(e);
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
    final platform = player.platform;
    if (settings.hardwareDecoding != _hwdec && platform is NativePlayer) {
      _hwdec = settings.hardwareDecoding;
      unawaited(platform.setProperty('hwdec', _hwdec));
    }
    if (settings.superResolution != _shaders) unawaited(_applyShaders());
    notifyListeners();
  }

  /// Turns super-resolution on with the last chosen chain, or off.
  Future<void> toggleSuperResolution() => setSuperResolution(
    settings.superResolution == 'off' ? settings.superResolutionChain : 'off',
  );

  /// Chooses the super-resolution chain from the player, which then says
  /// what it does to the video.
  Future<void> setSuperResolution(String mode) async {
    _announceUpscale = mode != 'off';
    await settings.setSuperResolution(mode);
    if (mode == 'off') showNotice('超分已关闭');
  }

  /// Loads the chosen super-resolution shaders, which mpv applies to the
  /// current file at once.
  Future<void> _applyShaders() async {
    final mode = settings.superResolution;
    final platform = player.platform;
    if (platform is! NativePlayer || mode == _shaders) return;
    _shaders = mode;
    try {
      final files = await superResolutionShaders(mode);
      if (_closed || _shaders != mode) return;
      // One write, so a quick toggle cannot interleave with a chain still
      // being appended.
      await platform.setProperty(
        'glsl-shaders',
        files.join(Platform.isWindows ? ';' : ':'),
      );
    } catch (e) {
      _shaders = 'off';
      _announceUpscale = false;
      showNotice('超分辨率不可用：${errorMessage(e)}');
    }
    _scheduleOutputSize();
  }

  /// Tells the player how large it is shown, in physical pixels.
  void showAt(Size display) {
    if (_display == display) return;
    _display = display;
    _scheduleOutputSize();
  }

  /// Renders at the shown size while super-resolution is on, so the shaders
  /// have room to upscale; otherwise at the video's own size, which is
  /// cheapest. Window resizes settle before the output is reallocated.
  void _scheduleOutputSize() {
    _outputTimer?.cancel();
    _outputTimer = Timer(const Duration(milliseconds: 250), () {
      if (!_closed) unawaited(_resizeOutput());
    });
  }

  Future<void> _resizeOutput() async {
    final params = player.state.videoParams;
    final rotated = params.rotate == 90 || params.rotate == 270;
    final width = ((rotated ? params.dh : params.dw) ?? 0).toDouble();
    final height = ((rotated ? params.dw : params.dh) ?? 0).toDouble();
    final display = _display;
    int? outputWidth, outputHeight;
    final on =
        settings.superResolution != 'off' &&
        display != null &&
        width > 0 &&
        height > 0;
    var scale = 1.0;
    if (on) {
      scale = math.min(display.width / width, display.height / height);
      // At most 4K's area; larger outputs only cost GPU time.
      scale = math.min(scale, math.sqrt(3840 * 2160 / (width * height)));
      if (scale > 1.05) {
        outputWidth = (width * scale).round();
        outputHeight = (height * scale).round();
      }
    }
    try {
      await video.setSize(width: outputWidth, height: outputHeight);
    } catch (_) {
      // The output keeps its previous size.
    }
    if (_closed) return;
    // Anime4K's upscaling passes run only above 1.2×; below that only its
    // restoration does.
    final next = on
        ? (
            source: Size(width, height),
            output: scale > 1.2
                ? Size(outputWidth!.toDouble(), outputHeight!.toDouble())
                : null,
          )
        : null;
    final changed = next != upscale;
    upscale = next;
    if (_announceUpscale && settings.superResolution != 'off') {
      _announceUpscale = false;
      showNotice(switch (next) {
        null => '超分已开启',
        (:final source, output: final output?) =>
          '超分 ${resolutionLabel(source)} → ${resolutionLabel(output)}',
        _ => '超分已开启 · 画面不小于窗口，只修复线条',
      });
    } else if (changed) {
      notifyListeners();
    }
  }

  /// Seeks past the file's OP or ED when playback runs into it, once per
  /// session; landing inside one by seeking or resuming plays it.
  void _skipSongs(Duration value) {
    final position = value.inMilliseconds / 1000;
    final previous = _lastPosition;
    _lastPosition = position;
    final marks = openingEnding;
    if (marks == null ||
        previous == null ||
        opening ||
        !player.state.playing ||
        frameStepping) {
      return;
    }
    bool entered(ChapterSpan? span) =>
        span != null &&
        position >= span.start &&
        position < span.end - 3 &&
        // Chapters are read a moment after the file opens.
        previous <= span.start + 5 &&
        previous <= position;
    if (settings.skipOpening && !_skippedOpening && entered(marks.opening)) {
      _skippedOpening = true;
      unawaited(_skipTo(marks.opening!.end, '已跳过片头'));
    } else if (settings.skipEnding &&
        !_skippedEnding &&
        entered(marks.ending)) {
      _skippedEnding = true;
      unawaited(_skipTo(marks.ending!.end, '已跳过片尾'));
    }
  }

  Future<void> _skipTo(double seconds, String message) async {
    await player.seek(Duration(milliseconds: (seconds * 1000).round()));
    showNotice(message);
  }

  // The layer lays comments out again by the controller's own revision,
  // which a sent comment leaves alone.
  void _danmakuChanged() => notifyListeners();

  Future<void> selectSubtitle(SubtitleTrack track) async {
    cancelAutoplay();
    _manualSubtitle = true;
    await player.setSubtitleTrack(track);
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
    if (!_scoredAudio) {
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
            session?.id == id) {
          await player.setAudioTrack(best);
        }
      }
    }
  }

  /// Reads the file's chapters once its duration is known; most BD and
  /// fansub MKVs carry them, online streams rarely do.
  Future<void> _readChapters(String sessionId) async {
    final platform = player.platform;
    if (platform is! NativePlayer) return;
    try {
      final duration = player.state.duration > Duration.zero
          ? player.state.duration
          : await player.stream.duration
                .firstWhere((value) => value > Duration.zero)
                .timeout(const Duration(seconds: 30));
      final count =
          int.tryParse(await platform.getProperty('chapter-list/count')) ?? 0;
      final chapters = <({String title, double start})>[];
      for (var i = 0; i < count; i++) {
        final start = double.tryParse(
          await platform.getProperty('chapter-list/$i/time'),
        );
        if (start == null) continue;
        chapters.add((
          title: await platform.getProperty('chapter-list/$i/title'),
          start: start,
        ));
      }
      if (_closed || session?.id != sessionId) return;
      openingEnding = OpeningEnding.find(
        chapters,
        duration.inMilliseconds / 1000,
      );
      if (openingEnding != null) notifyListeners();
    } catch (_) {
      // Without chapters there are no OP/ED marks.
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
      if (!DateTime.now().isBefore(deadline) || _closed || session?.id != id) {
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
        autoplayMessage = '${target.episode.label}暂无可直接播放的资源';
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
      autoplayMessage = '自动连播已停止：${errorMessage(e)}';
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
      autoplayMessage = '下一话打开失败：${errorMessage(e)}';
      notifyListeners();
    }
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    _timer?.cancel();
    _volumeWrite?.cancel();
    _rateWrite?.cancel();
    _outputTimer?.cancel();
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

/// A chapter's span in seconds.
typedef ChapterSpan = ({double start, double end});

/// The OP and ED chapters of a file, either of which may be missing.
class OpeningEnding {
  const OpeningEnding({this.opening, this.ending});
  final ChapterSpan? opening, ending;

  static final _openingName = RegExp(
    r'^\s*(op\b|op\d|opening|オープニング|片头|序曲)',
    caseSensitive: false,
  );
  static final _endingName = RegExp(
    r'^\s*(ed\b|ed\d|ending|エンディング|片尾)',
    caseSensitive: false,
  );

  /// Chapters named as OP/ED; without names, a chapter of the usual song
  /// length (80–95 s, or 55–65 s for 10–20 minute episodes) in the first or
  /// last part of the episode, as Animeko does.
  static OpeningEnding? find(
    List<({String title, double start})> chapters,
    double duration,
  ) {
    if (chapters.length < 2 || duration <= 0) return null;
    final sorted = [...chapters]..sort((a, b) => a.start.compareTo(b.start));
    final spans = [
      for (final (index, chapter) in sorted.indexed)
        (
          title: chapter.title,
          span: (
            start: chapter.start,
            end: index + 1 < sorted.length ? sorted[index + 1].start : duration,
          ),
        ),
    ];
    ChapterSpan? named(RegExp name) => spans
        .where((chapter) => name.hasMatch(chapter.title))
        .firstOrNull
        ?.span;
    var opening = named(_openingName), ending = named(_endingName);
    if (opening == null && ending == null) {
      final (low, high) = duration > 20 * 60
          ? (80.0, 95.0)
          : duration > 10 * 60
          ? (55.0, 65.0)
          : (0.0, 0.0);
      bool song(ChapterSpan span) =>
          span.end - span.start >= low && span.end - span.start <= high;
      final songs = [
        for (final chapter in spans)
          if (high > 0 && song(chapter.span)) chapter.span,
      ];
      opening = songs.where((span) => span.start < duration * .4).firstOrNull;
      ending = songs.where((span) => span.start > duration * .6).lastOrNull;
    }
    if (opening == null && ending == null) return null;
    return OpeningEnding(opening: opening, ending: ending);
  }
}

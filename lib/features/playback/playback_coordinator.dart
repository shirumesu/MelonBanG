import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../../core/error_message.dart';
import '../../core/network.dart';
import '../tracking/tracking_repository.dart';
import '../../domain/catalog.dart';
import '../../domain/play_candidate.dart';
import '../../domain/playback_session.dart';
import '../../domain/transfer.dart';
import '../downloads/download_repository.dart';
import 'play_selection.dart';
import 'playback.dart';
import 'playback_library.dart';

/// Window operations the coordinator drives; implemented by the app shell.
abstract interface class PlaybackShell {
  bool get showingPlayer;

  /// Switches to the player route, remembering the page being left.
  void enterPlayer();
  void showError(Object error);

  /// Lets the user pick a source for [episode]; null when dismissed.
  Future<PlayCandidate?> chooseCandidate(Subject subject, Episode episode);

  /// Opens resource search for [episode]: the player's own sheet while the
  /// player shows, else the resources page.
  Future<void> openResources(Subject subject, Episode episode);
}

/// A chosen source that could not be played; nothing else is tried for it.
class PlaybackFailure {
  const PlaybackFailure(this.reason, this.episode);
  final String reason;
  final Episode episode;
}

/// The player route opened before a session starts: an episode whose source
/// is being chosen, or a cached file being opened.
class PreparingPlayback {
  const PreparingPlayback({
    required this.title,
    this.detail,
    this.coverUrl,
    this.subject,
    this.episode,
    this.status,
    this.downloadId,
    this.failed,
  });

  PreparingPlayback.episode(Subject this.subject, Episode this.episode)
    : title = subject.title,
      detail = '${episode.label}  ${episode.title}',
      coverUrl = subject.coverUrl,
      status = null,
      downloadId = null,
      failed = null;

  final String title;
  final String? detail, coverUrl;

  /// Set for an episode; choosing another source needs both.
  final Subject? subject;
  final Episode? episode;

  /// The current step, such as resolving an address or opening the video.
  final String? status;

  /// The download being started or streamed, whose live state is shown.
  final String? downloadId;

  /// Why no playable source could be started.
  final String? failed;

  PreparingPlayback _copy({
    String? status,
    String? downloadId,
    String? failed,
  }) => PreparingPlayback(
    title: title,
    detail: detail,
    coverUrl: coverUrl,
    subject: subject,
    episode: episode,
    status: status ?? this.status,
    downloadId: downloadId ?? this.downloadId,
    failed: failed,
  );
}

/// Selects a source, opens it, checks for a first frame, refreshes a failed
/// online address once, and prepares autoplay. A source that still fails
/// stops with its reason; another one is never picked in its place. Request tickets and cancellation keep
/// superseded work from reaching the player.
class PlaybackCoordinator extends ChangeNotifier {
  PlaybackCoordinator(
    this.playback,
    this.selection,
    this.library,
    this.tracking,
    this.downloads,
  ) {
    playback.resolveNext = _prepareAutoplay;
    playback.addListener(_markWatched);
    _subscriptions.add(
      playback.player.stream.position.listen((_) {
        _markWatched();
        _considerCacheNext();
      }),
    );
    _subscriptions.add(
      playback.errors.listen((reason) {
        if (_activeCandidate != null &&
            !playback.opening &&
            shell.showingPlayer) {
          unawaited(_recover(reason));
        }
      }),
    );
    _subscriptions.add(
      playback.player.stream.buffering.listen((buffering) {
        _bufferDeadline?.cancel();
        // A transfer stream buffers while its data arrives; that is not a
        // failing source.
        if (buffering &&
            _activeCandidate?.kind == PlayKind.online &&
            !playback.opening &&
            shell.showingPlayer) {
          _bufferDeadline = Timer(const Duration(seconds: 15), () {
            final now = DateTime.now();
            if (_lastLongBuffer == null ||
                now.difference(_lastLongBuffer!) > const Duration(minutes: 2)) {
              _longBufferCount = 0;
            }
            _lastLongBuffer = now;
            if (++_longBufferCount < 2) return;
            // A fresh address often ends the stall; past that the stream
            // keeps going and the choice of another source stays the user's.
            if (_onlineRefreshed) {
              playback.showNotice('一直在缓冲，可以在侧栏换个资源');
            } else {
              unawaited(_recover('播放反复长时间缓冲'));
            }
          });
        }
      }),
    );
  }
  final Playback playback;
  final PlaySelectionRepository selection;
  final PlaybackLibrary library;
  final TrackingRepository tracking;
  final DownloadRepository downloads;
  late PlaybackShell shell;

  /// Subject of the player route, with its episode list.
  Subject? subject;
  PreparingPlayback? preparing;

  /// Why the chosen source stopped while a video is open.
  PlaybackFailure? failure;
  int _preparingTicket = 0;
  Future<void> Function()? _retryPreparing;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  Future<void> _operations = Future.value();
  (String, String)? _watchedSession;
  Future<void>? _closing;
  bool _closed = false;
  int _selectionRequest = 0, _playbackRequest = 0;
  RequestCancellation _selectionCancel = RequestCancellation();
  PlayCandidate? _activeCandidate;
  Subject? _candidateSubject;
  Episode? _candidateEpisode;
  bool _recovering = false, _onlineRefreshed = false;
  Timer? _firstFrameDeadline, _bufferDeadline;
  int _longBufferCount = 0;
  DateTime? _lastLongBuffer;

  /// The source last chosen for playback, shown beside the video.
  PlayCandidate? get activeCandidate => _activeCandidate;

  /// The source the playing subject remembers for its next episodes.
  RememberedSource? remembered;

  /// The session whose next episode was considered for caching.
  String? _cacheNextSession;
  RequestCancellation? _cacheNextCancel;

  Future<void> _loadRemembered(int subjectId) async {
    final value = await selection.remembered(subjectId);
    if (_closed || _candidateSubject?.id != subjectId) return;
    remembered = value;
    notifyListeners();
  }

  /// Stops preferring the playing subject's remembered source.
  Future<void> forgetSource() async {
    final id = _candidateSubject?.id;
    if (id == null) return;
    await selection.forget(id);
    remembered = null;
    notifyListeners();
  }

  int _nextSelection() {
    _selectionCancel.cancel();
    _selectionCancel = RequestCancellation();
    if (failure != null) {
      failure = null;
      notifyListeners();
    }
    return ++_selectionRequest;
  }

  Future<void> _perform(Future<void> Function() action) async {
    try {
      await action();
    } on RequestCancelled {
      return;
    } catch (e) {
      shell.showError(e);
    }
  }

  void _markWatched() {
    final current = playback.session;
    if (_closed ||
        current == null ||
        current.standalone ||
        playback.opening ||
        playback.error != null ||
        !playback.settings.autoMarkWatched) {
      return;
    }
    final subjectId = current.subjectId, episodeId = current.episodeId;
    final duration = playback.player.state.duration.inMilliseconds;
    final key = (current.id, tracking.account.userId);
    if (subjectId == null ||
        episodeId == null ||
        duration <= 0 ||
        playback.player.state.position.inMilliseconds < duration * .8 ||
        _watchedSession == key) {
      return;
    }
    _watchedSession = key;
    final write = _perform(
      () => _setEpisode(subjectId, episodeId, EpisodeStatus.watched),
    );
    _operations = Future.wait([_operations, write]).then((_) {});
  }

  /// Marks [episode] of the player's subject watched or unwatched.
  Future<void> markEpisode(Episode episode, bool watched) => _setEpisode(
    episode.subjectId,
    episode.id,
    watched ? EpisodeStatus.watched : EpisodeStatus.unwatched,
  );

  Future<void> _setEpisode(
    int subjectId,
    int episodeId,
    EpisodeStatus status,
  ) async {
    await tracking.setEpisode(subjectId, episodeId, status);
    final current = subject;
    if (_closed || current?.id != subjectId) return;
    subject = current!.copyWith(
      episodes: [
        for (final episode in current.episodes)
          episode.id == episodeId ? episode.withStatus(status) : episode,
      ],
    );
    notifyListeners();
  }

  /// Drops pending selection, checks and autoplay.
  void cancel() {
    playback.cancelAutoplay();
    _nextSelection();
    _firstFrameDeadline?.cancel();
    _bufferDeadline?.cancel();
    _playbackRequest++;
  }

  /// Leaves the player: [cancel]s and clears the preparing state.
  void leave() {
    cancel();
    _preparingTicket++;
    preparing = null;
  }

  /// Pauses and saves progress after queued playback work, then runs
  /// [afterwards].
  void stop(Future<void> Function() afterwards) {
    _operations = _operations.then(
      (_) => _perform(() async {
        await playback.player.pause();
        await playback.saveProgress();
        await afterwards();
      }),
    );
  }

  /// Opens a session that needs no source selection, such as a chosen file,
  /// entering the player at once in a preparing state titled [title].
  Future<void> play(
    Future<PlaybackSession> Function() load, {
    required String title,
    String? coverUrl,
    String? downloadId,
  }) async {
    final request = _nextSelection();
    _activeCandidate = null;
    // A chosen file has no source choice to show beside it.
    remembered = null;
    _firstFrameDeadline?.cancel();
    _bufferDeadline?.cancel();
    shell.enterPlayer();
    final ticket = ++_preparingTicket;
    _retryPreparing = () =>
        play(load, title: title, coverUrl: coverUrl, downloadId: downloadId);
    subject = null;
    preparing = PreparingPlayback(
      title: title,
      coverUrl: coverUrl,
      status: '正在打开视频…',
      downloadId: downloadId,
    );
    notifyListeners();
    Object? failure;
    await _queue(
      () async {
        try {
          await playback.saveProgress();
          final session = await load();
          if (_closed || request != _selectionRequest) {
            downloads.releaseStreamsExcept(playback.session?.streamId);
            return;
          }
          await playback.open(session);
          if (playback.error != null) throw StateError(playback.error!);
        } catch (e) {
          failure = e;
          rethrow;
        }
      },
      reportFailure: false,
      isCurrent: () => request == _selectionRequest,
    );
    if (failure case final error?) {
      _failPreparing(ticket, errorMessage(error));
    }
  }

  Future<void> _queue(
    Future<void> Function() open, {
    bool reportFailure = true,
    bool Function()? isCurrent,
  }) {
    final ticket = ++_playbackRequest;
    final operation = _operations.then((_) async {
      if (_closed || ticket != _playbackRequest) return;
      Future<void> action() async {
        final previousSessionId = playback.session?.id;
        await open();
        if (_closed ||
            ticket != _playbackRequest ||
            !(isCurrent?.call() ?? true)) {
          if (playback.session?.id != previousSessionId) {
            await playback.player.pause();
            await playback.saveProgress();
          }
          return;
        }
        _show(ticket);
      }

      if (reportFailure) {
        await _perform(action);
      } else {
        try {
          await action();
        } catch (_) {}
      }
    });
    _operations = operation.catchError((Object _) {});
    return operation;
  }

  /// Plays [episode] of the subject on the player route.
  void playEpisode(Episode episode) {
    final current = subject;
    if (current != null) {
      unawaited(
        _perform(() => selectEpisode(current, episode, useContinuity: true)),
      );
    }
  }

  Future<List<PlayCandidate>> _candidates(
    Subject item,
    Episode episode, {
    bool instantOnly = false,
    bool useContinuity = false,
    bool forPlayback = false,
    RequestCancellation? cancel,
  }) {
    final settings = playback.settings;
    return selection.candidates(
      item,
      episode,
      instantOnly: instantOnly,
      useContinuity: useContinuity,
      forPlayback: forPlayback,
      cancel: cancel ?? _selectionCancel,
      onlineFirst:
          (item.airing()
              ? settings.airingPriority
              : settings.completedPriority) ==
          'online',
      language: settings.subtitleLanguage,
    );
  }

  /// Plays a cached file when one exists, otherwise the best instant source.
  Future<void> selectEpisode(
    Subject item,
    Episode episode, {
    bool useContinuity = false,
  }) async {
    playback.cancelAutoplay();
    final request = _nextSelection();
    _activeCandidate = null;
    _firstFrameDeadline?.cancel();
    _bufferDeadline?.cancel();
    final available = await library.playableEpisodes(item.id);
    if (_closed || request != _selectionRequest) return;
    if (available.contains(episode.id)) {
      final local = await selection.candidates(
        item,
        episode,
        instantOnly: true,
        includeOnline: false,
        cancel: _selectionCancel,
        useContinuity: useContinuity,
        language: playback.settings.subtitleLanguage,
      );
      if (_closed || request != _selectionRequest) return;
      // A cache that cannot open is reported rather than replaced by
      // another source; an unfinished one streams from its transfer.
      if (local.isEmpty) {
        throw StateError('${episode.label}的缓存暂时无法播放');
      }
      await playCandidate(local.first, item, episode);
      return;
    }
    playback.showNotice('正在查找${episode.label}资源');
    final choices = await _candidates(
      item,
      episode,
      useContinuity: useContinuity,
      forPlayback: true,
    );
    if (_closed || request != _selectionRequest) return;
    if (choices.isEmpty) {
      if (preparing != null) {
        _failPreparing(_preparingTicket, '没有找到可以直接播放的资源');
        return;
      }
      playback.showNotice('${episode.label}没有能直接播放的资源');
      await shell.openResources(item, episode);
      return;
    }
    if (choices.first.possibleMatch) {
      await chooseSource(item, episode);
      return;
    }
    await playCandidate(choices.first, item, episode);
  }

  /// Plays [episode]'s cache when it has one, otherwise lets the user pick a
  /// source.
  Future<void> openEpisode(Subject item, Episode episode) async {
    if ((await library.playableEpisodes(item.id)).contains(episode.id)) {
      await prepare(item, episode, () => selectEpisode(item, episode));
    } else {
      await chooseSource(item, episode);
    }
  }

  /// Plays [item]'s cache from where it was left: the last played episode
  /// while unfinished, else the first cached episode after it, else the first
  /// cached one. An episode played to the automatic watched mark counts as
  /// finished.
  Future<void> continueCache(Subject item) async {
    final available = await library.playableEpisodes(item.id);
    final last = await library.lastPlayed(item.id);
    final episodes = item.episodes;
    final cached = [
      for (final (index, episode) in episodes.indexed)
        if (available.contains(episode.id)) index,
    ];
    if (cached.isEmpty) throw StateError('没有可以播放的缓存');
    var start = cached.first;
    if (last case (:final episodeId, :final progress)) {
      final played = episodes.indexWhere((e) => e.id == episodeId);
      final finished =
          progress.completed ||
          (playback.settings.autoMarkWatched &&
              progress.duration > 0 &&
              progress.position >= progress.duration * .8);
      if (played >= 0) {
        start = cached.firstWhere(
          (index) => finished ? index > played : index >= played,
          orElse: () => cached.first,
        );
      }
    }
    final episode = episodes[start];
    await prepare(item, episode, () => selectEpisode(item, episode));
  }

  /// Lets the user pick a source for [episode] and plays it; in a playing
  /// player that is its own resource sheet.
  Future<void> chooseSource(Subject item, Episode episode) async {
    cancel();
    if (shell.showingPlayer && preparing == null && playback.uri != null) {
      await shell.openResources(item, episode);
      return;
    }
    final chosen = await shell.chooseCandidate(item, episode);
    if (_closed) return;
    if (chosen != null) {
      if (shell.showingPlayer) {
        await playCandidate(chosen, item, episode);
      } else {
        await prepare(
          item,
          episode,
          () => playCandidate(chosen, item, episode),
        );
      }
    } else if (preparing != null) {
      _failPreparing(_preparingTicket, '没有选择资源');
    }
  }

  /// Enters the player at once and keeps it in a preparing state until
  /// [start] opens a session (cleared by [_show]) or fails.
  Future<void> prepare(
    Subject item,
    Episode episode,
    Future<void> Function() start,
  ) async {
    shell.enterPlayer();
    final ticket = ++_preparingTicket;
    _retryPreparing = () =>
        prepare(item, episode, () => selectEpisode(item, episode));
    subject = item;
    preparing = PreparingPlayback.episode(item, episode);
    notifyListeners();
    try {
      await start();
    } on RequestCancelled {
      return;
    } catch (e) {
      _failPreparing(ticket, errorMessage(e));
      return;
    }
    _failPreparing(ticket, '没能开始播放，可以换一个资源再试');
  }

  void retryPreparing() => unawaited(_perform(_retryPreparing!));

  /// Plays the failed source again.
  void retryFailure() {
    final candidate = _activeCandidate;
    final item = _candidateSubject, episode = _candidateEpisode;
    if (candidate == null || item == null || episode == null) return;
    unawaited(_perform(() => playCandidate(candidate, item, episode)));
  }

  void choosePreparing() {
    final PreparingPlayback(:subject, :episode) = preparing!;
    unawaited(_perform(() => chooseSource(subject!, episode!)));
  }

  void _failPreparing(int ticket, String reason) {
    final current = preparing;
    if (_closed ||
        ticket != _preparingTicket ||
        current == null ||
        current.failed != null) {
      return;
    }
    preparing = current._copy(failed: reason);
    notifyListeners();
  }

  /// Shows the step a preparing player is at, and the download it waits on.
  void _preparingStep({String? status, String? downloadId}) {
    final current = preparing;
    if (_closed || current == null || current.failed != null) return;
    preparing = current._copy(status: status, downloadId: downloadId);
    notifyListeners();
  }

  Future<void> playCandidate(
    PlayCandidate candidate,
    Subject item,
    Episode episode, {
    bool recovery = false,
    Duration? recoveryPosition,
  }) async {
    final request = recovery ? _selectionRequest : _nextSelection();
    final cancellation = _selectionCancel;
    if (!recovery) {
      playback.cancelAutoplay();
      if (_candidateSubject?.id != item.id) {
        remembered = null;
        unawaited(_loadRemembered(item.id));
      }
      _candidateSubject = item;
      _candidateEpisode = episode;
      _onlineRefreshed = false;
      _longBufferCount = 0;
      _lastLongBuffer = null;
      _activeCandidate = null;
    }
    _firstFrameDeadline?.cancel();
    _bufferDeadline?.cancel();
    Object? failure;
    await _queue(
      () async {
        try {
          _preparingStep(
            status: switch (candidate.target) {
              OnlineTarget() => '正在解析播放地址…',
              DownloadTarget() => '正在打开缓存…',
              ReleaseTarget() when candidate.kind == PlayKind.pikpak =>
                '正在提交到 PikPak…',
              ReleaseTarget() => '正在添加 BT 任务…',
            },
            downloadId: switch (candidate.target) {
              DownloadTarget(:final downloadId) => downloadId,
              _ => null,
            },
          );
          var session = await selection.load(
            candidate,
            item.id,
            episode.id,
            cancel: cancellation,
            onTask: (id) => _preparingStep(downloadId: id),
          );
          _preparingStep(status: '正在打开视频…');
          if (_closed || request != _selectionRequest) {
            downloads.releaseStreamsExcept(playback.session?.streamId);
            return;
          }
          if (recoveryPosition != null) {
            session = session.startingAt(
              recoveryPosition.inMilliseconds / 1000,
            );
          }
          _activeCandidate = candidate;
          await playback.open(session);
          if (playback.error != null) throw StateError(playback.error!);
          // A failed write only loses the preference, not the playback.
          unawaited(
            selection
                .played(item.id, candidate)
                .then((_) => _loadRemembered(item.id))
                .catchError((Object _) {}),
          );
          final sessionId = session.id;
          _firstFrameDeadline?.cancel();
          if (candidate.kind == PlayKind.online) {
            _firstFrameDeadline = Timer(const Duration(seconds: 15), () {
              unawaited(_checkFirstFrame(sessionId, request));
            });
          }
        } catch (e) {
          if (request == _selectionRequest) _activeCandidate = candidate;
          failure = e;
          rethrow;
        }
      },
      reportFailure: false,
      isCurrent: () => request == _selectionRequest,
    );
    if (failure != null && !_closed && request == _selectionRequest) {
      if (recovery) throw failure!;
      await _recover(errorMessage(failure!));
    }
  }

  Future<void> _checkFirstFrame(String sessionId, int request) async {
    bool current() =>
        !_closed &&
        request == _selectionRequest &&
        playback.session?.id == sessionId;
    if (!current()) return;
    final platform = playback.player.platform;
    if (platform is! NativePlayer) return;
    final fps = double.tryParse(await platform.getProperty('estimated-vf-fps'));
    if (!current() || (fps != null && fps.isFinite && fps > 0)) return;
    final seeking = await platform.getProperty('seeking') == 'yes';
    if (!current()) return;
    if (seeking ||
        (!playback.player.state.playing && !playback.player.state.buffering)) {
      _firstFrameDeadline = Timer(const Duration(seconds: 5), () {
        unawaited(_checkFirstFrame(sessionId, request));
      });
      return;
    }
    await _recover('15 秒内未产生视频画面');
  }

  /// Re-resolves a failed online address once, then stops with [reason].
  /// Another source is never picked on the user's behalf: it may be one they
  /// did not want.
  Future<void> _recover(String reason) async {
    final failed = _activeCandidate;
    final item = _candidateSubject, episode = _candidateEpisode;
    if (_recovering ||
        failed == null ||
        item == null ||
        episode == null ||
        _closed) {
      return;
    }
    _recovering = true;
    final request = _selectionRequest;
    _firstFrameDeadline?.cancel();
    _bufferDeadline?.cancel();
    try {
      selection.failed(failed);
      if (failed.kind == PlayKind.online && !_onlineRefreshed) {
        _onlineRefreshed = true;
        final saved = await library.progress(item.id, episode.id);
        final position =
            playback.session?.subjectId == item.id &&
                playback.session?.episodeId == episode.id
            ? playback.player.state.position
            : Duration(milliseconds: ((saved?.position ?? 0) * 1000).round());
        playback.showNotice('正在刷新播放地址');
        try {
          await playCandidate(
            failed,
            item,
            episode,
            recovery: true,
            recoveryPosition: position,
          );
          if (playback.error == null) return;
        } catch (error) {
          reason = errorMessage(error);
        }
      }
      if (!_closed && request == _selectionRequest) {
        _fail(item, episode, failed, reason);
      }
    } catch (e) {
      if (!_closed && request == _selectionRequest) shell.showError(e);
    } finally {
      _recovering = false;
    }
  }

  /// Stops on [candidate]'s failure: a preparing or empty player shows it
  /// with retry and source choice, an open video pauses under it.
  void _fail(
    Subject item,
    Episode episode,
    PlayCandidate candidate,
    String reason,
  ) {
    _retryPreparing = () =>
        prepare(item, episode, () => playCandidate(candidate, item, episode));
    if (preparing == null && playback.uri == null) {
      _preparingTicket++;
      subject = item;
      preparing = PreparingPlayback.episode(item, episode);
    }
    if (preparing != null) {
      _failPreparing(_preparingTicket, reason);
      return;
    }
    unawaited(playback.player.pause());
    failure = PlaybackFailure(reason, episode);
    notifyListeners();
  }

  /// The episode broadcast after [currentId] once it has aired, specials
  /// included, passing over recaps when the settings say so.
  Episode? _nextAired(Subject item, int currentId) {
    final next = item.after(
      currentId,
      skipRecaps: playback.settings.skipRecaps,
    );
    final date = next?.aired;
    if (date != null && date.isAfter(DateTime.now())) return null;
    return next;
  }

  /// Starts caching the next episode once the current one has played for a
  /// while (two minutes, or 30% of a shorter one), so trying out sources
  /// does not start downloads.
  void _considerCacheNext() {
    final current = playback.session;
    final playing = _activeCandidate;
    final item = _candidateSubject, episode = _candidateEpisode;
    if (_closed ||
        current == null ||
        current.standalone ||
        playback.opening ||
        playback.error != null ||
        !playback.settings.cacheNext ||
        playing == null ||
        item == null ||
        episode == null ||
        current.subjectId != item.id ||
        current.episodeId != episode.id ||
        _cacheNextSession == current.id) {
      return;
    }
    final position = playback.player.state.position.inMilliseconds / 1000;
    final duration = playback.player.state.duration.inMilliseconds / 1000;
    if (position < math.min(120, duration > 0 ? duration * .3 : 120)) return;
    _cacheNextSession = current.id;
    unawaited(_cacheNext(item, episode, playing));
  }

  /// Adds the next aired episode from the playing source's family (BT,
  /// PikPak or online): its release group or line when that has the
  /// episode, else the best match of the family. Nothing is added when the
  /// episode is cached, being cached, or has no such source.
  Future<void> _cacheNext(
    Subject item,
    Episode episode,
    PlayCandidate playing,
  ) async {
    _cacheNextCancel?.cancel();
    final cancel = _cacheNextCancel = RequestCancellation();
    String family(PlayCandidate c) =>
        c.continuityKey.substring(0, c.continuityKey.indexOf(':'));
    try {
      final detail = item.episodes.isNotEmpty
          ? item
          : await tracking.subject(item.id, forPlayback: true);
      final next = _nextAired(detail, episode.id);
      if (next == null || _closed) return;
      if ((await library.playableEpisodes(item.id)).contains(next.id)) return;
      if (downloads
          .snapshot()
          .forSubject(item.id)
          .any(
            (task) =>
                task.episodeId == next.id &&
                task.status != DownloadStatus.failed,
          )) {
        return;
      }
      final wanted = family(playing);
      final choices =
          (await selection.candidates(
            detail,
            next,
            includeDownloads: false,
            useContinuity: true,
            onlineFirst: wanted == 'online',
            language: playback.settings.subtitleLanguage,
            cancel: cancel,
          )).where(
            (c) =>
                !c.possibleMatch &&
                c.kind != PlayKind.local &&
                family(c) == wanted &&
                !(describeCandidate(c).episodeLabel?.contains('–') ?? false) &&
                switch (c.target) {
                  ReleaseTarget() => true,
                  OnlineTarget(:final ref) => ref != null,
                  DownloadTarget() => false,
                },
          );
      if (_closed || cancel.isCancelled) return;
      final chosen =
          choices
              .where((c) => c.continuityKey == playing.continuityKey)
              .firstOrNull ??
          choices
              .where((c) => playing.line.isNotEmpty && c.line == playing.line)
              .firstOrNull ??
          choices.firstOrNull;
      if (chosen == null) {
        playback.showNotice('没有找到${next.label}的同类资源，未自动缓存');
        return;
      }
      switch (chosen.target) {
        case ReleaseTarget(candidate: final release):
          await selection.releases.enqueue(
            release,
            method: wanted == 'pikpak' ? CacheMethod.pikpak : CacheMethod.bt,
            episodeId: next.id,
          );
        case OnlineTarget(:final ref?):
          await downloads.addOnline(
            ref,
            title: chosen.title,
            source: chosen.sourceLabel,
            subjectId: item.id,
            episodeId: next.id,
            coverUrl: item.coverUrl,
          );
        default:
          return;
      }
      if (!_closed) playback.showNotice('已开始缓存${next.label}');
    } on RequestCancelled {
      return;
    } catch (e) {
      if (!_closed) {
        playback.showNotice('自动缓存下一话失败：${errorMessage(e)}');
      }
    }
  }

  /// The next aired main episode and how it would play; never starts a new
  /// BT task.
  Future<AutoplayTarget?> _prepareAutoplay(PlaybackSession session) async {
    final cancellation = _selectionCancel;
    final id = session.subjectId, currentId = session.episodeId;
    if (id == null || currentId == null) return null;
    final item = subject?.id == id
        ? subject!
        : await tracking.subject(id, forPlayback: true);
    final next = _nextAired(item, currentId);
    if (next == null) return null;
    if ((await library.playableEpisodes(id)).contains(next.id)) {
      final local = await selection.candidates(
        item,
        next,
        instantOnly: true,
        includeOnline: false,
        cancel: cancellation,
        useContinuity: true,
        language: playback.settings.subtitleLanguage,
      );
      if (local.isNotEmpty) {
        return AutoplayTarget(
          episode: next,
          sourceLabel: local.first.sourceLabel,
          play: () => playCandidate(local.first, item, next),
        );
      }
    }
    final choices = (await _candidates(
      item,
      next,
      instantOnly: true,
      cancel: cancellation,
      useContinuity: true,
    )).where((c) => c.instant && !c.possibleMatch).toList();
    if (choices.isEmpty) {
      return AutoplayTarget(
        episode: next,
        sourceLabel: '',
        unavailable: true,
        play: () async {},
      );
    }
    return AutoplayTarget(
      episode: next,
      sourceLabel: choices.first.sourceLabel,
      play: () => playCandidate(choices.first, item, next),
    );
  }

  void _show(int ticket) {
    if (_closed || ticket != _playbackRequest) return;
    final sessionId = playback.session?.id;
    final subjectId = playback.session?.subjectId;
    shell.enterPlayer();
    _preparingTicket++;
    subject = null;
    preparing = null;
    failure = null;
    notifyListeners();
    if (subjectId == null) return;
    unawaited(
      _perform(() async {
        final detail = await tracking.subject(subjectId, forPlayback: true);
        if (!_closed && sessionId == playback.session?.id) {
          subject = detail;
          notifyListeners();
        }
      }),
    );
  }

  /// Lets queued playback work finish, then closes the player.
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    playback.removeListener(_markWatched);
    _firstFrameDeadline?.cancel();
    _bufferDeadline?.cancel();
    _selectionCancel.cancel();
    _cacheNextCancel?.cancel();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _operations;
    await playback.close();
  }
}

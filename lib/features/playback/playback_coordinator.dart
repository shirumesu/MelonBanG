import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../../core/network.dart';
import '../tracking/tracking_repository.dart';
import '../../domain/catalog.dart';
import '../../domain/play_candidate.dart';
import '../../domain/playback_session.dart';
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

  /// Opens the full resource search for [episode].
  Future<void> openResources(Subject subject, Episode episode);
}

/// The player route opened before a source is chosen.
class PreparingPlayback {
  const PreparingPlayback(this.subject, this.episode, {this.failed});
  final Subject subject;
  final Episode episode;

  /// Why no playable source could be started.
  final String? failed;
}

/// Selects a source, opens it, checks for a first frame, recovers or switches
/// sources, and prepares autoplay. Request tickets and cancellation keep
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
      playback.player.stream.position.listen((_) => _markWatched()),
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
        if (buffering &&
            _activeCandidate != null &&
            !playback.opening &&
            shell.showingPlayer) {
          _bufferDeadline = Timer(const Duration(seconds: 15), () {
            final now = DateTime.now();
            if (_lastLongBuffer == null ||
                now.difference(_lastLongBuffer!) > const Duration(minutes: 2)) {
              _longBufferCount = 0;
            }
            _lastLongBuffer = now;
            if (++_longBufferCount >= 2) {
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
  int _preparingTicket = 0;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  Future<void> _operations = Future.value();
  (String, String)? _watchedSession;
  Future<void>? _closing;
  bool _closed = false;
  int _selectionRequest = 0, _playbackRequest = 0, _fallbackCount = 0;
  RequestCancellation _selectionCancel = RequestCancellation();
  PlayCandidate? _activeCandidate;
  Subject? _candidateSubject;
  Episode? _candidateEpisode;
  List<PlayCandidate> _choices = [];
  bool _recovering = false, _onlineRefreshed = false;
  Timer? _firstFrameDeadline, _bufferDeadline;
  int _longBufferCount = 0;
  DateTime? _lastLongBuffer;

  int _nextSelection() {
    _selectionCancel.cancel();
    _selectionCancel = RequestCancellation();
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
      () => tracking.setEpisode(subjectId, episodeId, EpisodeStatus.watched),
    );
    _operations = Future.wait([_operations, write]).then((_) {});
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

  /// Opens a session that needs no source selection, such as a chosen file.
  Future<void> play(Future<PlaybackSession> Function() load) async {
    final request = _nextSelection();
    _activeCandidate = null;
    _firstFrameDeadline?.cancel();
    _bufferDeadline?.cancel();
    await _queue(() async {
      await playback.saveProgress();
      final session = await load();
      if (_closed || request != _selectionRequest) {
        downloads.releaseStreamsExcept(playback.session?.streamId);
        return;
      }
      await playback.open(session);
    }, isCurrent: () => request == _selectionRequest);
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
      final cached = local.where(
        (candidate) => candidate.kind == PlayKind.local,
      );
      if (cached.isNotEmpty) {
        await playCandidate(cached.first, item, episode);
        return;
      }
    }
    playback.showNotice('正在查找第 ${episode.number} 话资源');
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
      await shell.openResources(item, episode);
      return;
    }
    if (choices.first.possibleMatch) {
      await chooseSource(item, episode);
      return;
    }
    await playCandidate(choices.first, item, episode, choices: choices);
  }

  /// Lets the user pick a source for [episode] and plays it.
  Future<void> chooseSource(Subject item, Episode episode) async {
    cancel();
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
    subject = item;
    preparing = PreparingPlayback(item, episode);
    notifyListeners();
    try {
      await start();
    } on RequestCancelled {
      return;
    } catch (e) {
      _failPreparing(ticket, e.toString().replaceFirst('Bad state: ', ''));
      return;
    }
    _failPreparing(ticket, '没能开始播放，可以换一个资源再试');
  }

  void retryPreparing() {
    final PreparingPlayback(subject: item, :episode) = preparing!;
    unawaited(prepare(item, episode, () => selectEpisode(item, episode)));
  }

  void choosePreparing() {
    final current = preparing!;
    unawaited(_perform(() => chooseSource(current.subject, current.episode)));
  }

  void _failPreparing(int ticket, String reason) {
    final current = preparing;
    if (_closed ||
        ticket != _preparingTicket ||
        current == null ||
        current.failed != null) {
      return;
    }
    preparing = PreparingPlayback(
      current.subject,
      current.episode,
      failed: reason,
    );
    notifyListeners();
  }

  Future<void> playCandidate(
    PlayCandidate candidate,
    Subject item,
    Episode episode, {
    List<PlayCandidate>? choices,
    bool recovery = false,
    Duration? recoveryPosition,
  }) async {
    final request = recovery ? _selectionRequest : _nextSelection();
    final cancellation = _selectionCancel;
    if (!recovery) {
      playback.cancelAutoplay();
      _candidateSubject = item;
      _candidateEpisode = episode;
      _choices = choices ?? [];
      _fallbackCount = 0;
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
          var session = await selection.load(
            candidate,
            item.id,
            episode.id,
            cancel: cancellation,
          );
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
          selection.played(item.id, candidate);
          if (recovery) playback.showNotice('已切换到 ${candidate.sourceLabel}');
          final sessionId = session.id;
          _firstFrameDeadline?.cancel();
          _firstFrameDeadline = Timer(const Duration(seconds: 15), () {
            unawaited(_checkFirstFrame(sessionId, request));
          });
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
      await _recover('$failure');
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

  /// Re-resolves a failed online address once, then tries up to three
  /// instant alternatives, preferring the same provider.
  Future<void> _recover(String reason) async {
    var failed = _activeCandidate;
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
    final cancellation = _selectionCancel;
    var searchedAlternatives = false;
    _firstFrameDeadline?.cancel();
    _bufferDeadline?.cancel();
    try {
      final saved = await library.progress(item.id, episode.id);
      final position =
          playback.session?.subjectId == item.id &&
              playback.session?.episodeId == episode.id
          ? playback.player.state.position
          : Duration(milliseconds: ((saved?.position ?? 0) * 1000).round());
      while (!_closed && request == _selectionRequest) {
        selection.failed(failed!);
        if (failed.kind == PlayKind.online && !_onlineRefreshed) {
          _onlineRefreshed = true;
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
            reason = '$error';
          }
        }
        if (_fallbackCount >= 3) break;
        List<PlayCandidate> healthyChoices() => _choices
            .where(
              (candidate) =>
                  candidate.instant &&
                  !candidate.possibleMatch &&
                  candidate.id != failed!.id &&
                  candidate.health >= 0,
            )
            .toList();
        var alternatives = healthyChoices();
        if (alternatives.isEmpty && !searchedAlternatives) {
          searchedAlternatives = true;
          _choices = await _candidates(
            item,
            episode,
            instantOnly: true,
            useContinuity: true,
            cancel: cancellation,
          );
          alternatives = healthyChoices();
        }
        final alternative =
            alternatives
                .where((candidate) => candidate.provider == failed!.provider)
                .firstOrNull ??
            alternatives.firstOrNull;
        if (_closed || request != _selectionRequest) return;
        if (alternative == null) break;
        _choices.removeWhere((candidate) => candidate.id == failed!.id);
        failed = alternative;
        _fallbackCount++;
        _onlineRefreshed = false;
        try {
          await playCandidate(
            alternative,
            item,
            episode,
            recovery: true,
            recoveryPosition: position,
          );
          if (playback.error == null) return;
        } catch (error) {
          reason = '$error';
        }
      }
      if (!_closed && request == _selectionRequest) {
        await playback.player.pause();
        playback.showNotice('没有其他能直接播放的资源，请手动选择');
        playback.showResourceFailure(episode);
        shell.showError(reason);
        if (!shell.showingPlayer) await chooseSource(item, episode);
      }
    } catch (e) {
      if (!_closed && request == _selectionRequest) shell.showError(e);
    } finally {
      _recovering = false;
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
    final episodes = item.episodes.where((e) => e.main).toList()
      ..sort((a, b) => a.sort.compareTo(b.sort));
    final current = episodes.where((e) => e.id == currentId).firstOrNull;
    if (current == null) return null;
    final next = episodes.where((e) => e.sort > current.sort).firstOrNull;
    if (next == null) return null;
    final date = next.aired;
    if (date != null && date.isAfter(DateTime.now())) return null;
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
      play: () => playCandidate(choices.first, item, next, choices: choices),
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
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _operations;
    await playback.close();
  }
}

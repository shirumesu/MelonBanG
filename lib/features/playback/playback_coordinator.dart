import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../../data/json.dart';
import '../../data/network.dart';
import '../../data/tracking.dart';
import '../../domain/play_candidate.dart';
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
  Future<PlayCandidate?> chooseCandidate(Json subject, Json episode);

  /// Opens the full resource search for [episode].
  Future<void> openResources(Json subject, Json episode);
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
    _subscriptions.add(
      playback.player.stream.error.listen((reason) {
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
  Json? subject;

  /// Player route opened before a source is chosen: `subject`, `episode`,
  /// and `failed` once no playable source could be started.
  Json? preparing;
  int _preparingTicket = 0;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  Future<void> _operations = Future.value();
  Future<void>? _closing;
  bool _closed = false;
  int _selectionRequest = 0, _playbackRequest = 0, _fallbackCount = 0;
  RequestCancellation _selectionCancel = RequestCancellation();
  PlayCandidate? _activeCandidate;
  Json? _candidateSubject, _candidateEpisode;
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
  Future<void> play(Future<Json> Function() load) async {
    final request = _nextSelection();
    _activeCandidate = null;
    _firstFrameDeadline?.cancel();
    _bufferDeadline?.cancel();
    await _queue(() async {
      await playback.saveProgress();
      final session = await load();
      if (_closed || request != _selectionRequest) {
        downloads.releaseStreamsExcept(playback.session?['streamId'] as int?);
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
        final previousSessionId = playback.session?['id'];
        await open();
        if (_closed ||
            ticket != _playbackRequest ||
            !(isCurrent?.call() ?? true)) {
          if (playback.session?['id'] != previousSessionId) {
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
  void playEpisode(Json episode) {
    final current = subject;
    if (current != null) {
      unawaited(
        _perform(() => selectEpisode(current, episode, useContinuity: true)),
      );
    }
  }

  /// Continues a recently watched episode.
  Future<void> resume(Json item) async {
    final request = _nextSelection();
    final detail = await tracking.subject(
      item['subjectId'] as int,
      forPlayback: true,
    );
    if (_closed || request != _selectionRequest) return;
    final episode = objects(detail['episodes'])
        .where((e) => e['episodeId'] == item['episodeId'])
        .firstOrNull;
    if (episode != null) await selectEpisode(detail, episode);
  }

  Future<List<PlayCandidate>> _candidates(
    Json item,
    Json episode, {
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
          (subjectIsAiring(item)
              ? settings.airingPriority
              : settings.completedPriority) ==
          'online',
      language: settings.subtitleLanguage,
    );
  }

  /// Plays a cached file when one exists, otherwise the best instant source.
  Future<void> selectEpisode(
    Json item,
    Json episode, {
    bool useContinuity = false,
  }) async {
    playback.cancelAutoplay();
    final request = _nextSelection();
    _activeCandidate = null;
    _firstFrameDeadline?.cancel();
    _bufferDeadline?.cancel();
    final id = item['subjectId'] as int;
    final episodeId = episode['episodeId'] as int;
    final available = await library.playableEpisodes(id);
    if (_closed || request != _selectionRequest) return;
    if (available.contains(episodeId)) {
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
    playback.showNotice('正在查找第 ${episode['sort']} 话资源');
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
  Future<void> chooseSource(Json item, Json episode) async {
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
    Json item,
    Json episode,
    Future<void> Function() start,
  ) async {
    shell.enterPlayer();
    final ticket = ++_preparingTicket;
    subject = item;
    preparing = {'subject': item, 'episode': episode};
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
    final current = preparing!;
    final item = object(current['subject']);
    final episode = object(current['episode']);
    unawaited(prepare(item, episode, () => selectEpisode(item, episode)));
  }

  void choosePreparing() {
    final current = preparing!;
    unawaited(
      _perform(
        () => chooseSource(
          object(current['subject']),
          object(current['episode']),
        ),
      ),
    );
  }

  void _failPreparing(int ticket, String reason) {
    final current = preparing;
    if (_closed ||
        ticket != _preparingTicket ||
        current == null ||
        current['failed'] != null) {
      return;
    }
    preparing = {...current, 'failed': reason};
    notifyListeners();
  }

  Future<void> playCandidate(
    PlayCandidate candidate,
    Json item,
    Json episode, {
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
          final session = await selection.load(
            candidate,
            item['subjectId'] as int,
            episode['episodeId'] as int,
            cancel: cancellation,
          );
          if (_closed || request != _selectionRequest) {
            downloads.releaseStreamsExcept(
              playback.session?['streamId'] as int?,
            );
            return;
          }
          if (recoveryPosition != null) {
            session['startSeconds'] = recoveryPosition.inMilliseconds / 1000;
          }
          _activeCandidate = candidate;
          await playback.open(session);
          if (playback.error != null) throw StateError(playback.error!);
          selection.played(item['subjectId'] as int, candidate);
          if (recovery) playback.showNotice('已切换到 ${candidate.sourceLabel}');
          final sessionId = session['id'];
          _firstFrameDeadline?.cancel();
          _firstFrameDeadline = Timer(const Duration(seconds: 15), () {
            unawaited(_checkFirstFrame('$sessionId', request));
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
        playback.session?['id'] == sessionId;
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
      final saved = await library.progress(
        item['subjectId'] as int,
        episode['episodeId'] as int,
      );
      final position =
          playback.session?['subjectId'] == item['subjectId'] &&
              playback.session?['episodeId'] == episode['episodeId']
          ? playback.player.state.position
          : Duration(
              milliseconds: (number(saved?['positionSeconds']) * 1000).round(),
            );
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
        playback.showNotice('暂无可立即播放的其他资源，请打开“资源”或改用 BT');
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
  Future<AutoplayTarget?> _prepareAutoplay(Json session) async {
    final cancellation = _selectionCancel;
    final id = session['subjectId'] as int?,
        currentId = session['episodeId'] as int?;
    if (id == null || currentId == null) return null;
    final item = subject?['subjectId'] == id
        ? subject!
        : await tracking.subject(id, forPlayback: true);
    final episodes =
        objects(item['episodes'])
            .where(
              (e) => e['type'] == 0 || e['type'] == 'main' || e['type'] == null,
            )
            .toList()
          ..sort((a, b) => number(a['sort']).compareTo(number(b['sort'])));
    final current = episodes
        .where((e) => e['episodeId'] == currentId)
        .firstOrNull;
    if (current == null) return null;
    final next = episodes
        .where((e) => number(e['sort']) > number(current['sort']))
        .firstOrNull;
    if (next == null) return null;
    final date = DateTime.tryParse(
      '${next['airdate'] ?? next['airDate'] ?? ''}',
    );
    if (date != null && date.isAfter(DateTime.now())) return null;
    if ((await library.playableEpisodes(id)).contains(next['episodeId'])) {
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
    final sessionId = playback.session?['id'];
    final subjectId = playback.session?['subjectId'] as int?;
    shell.enterPlayer();
    _preparingTicket++;
    subject = null;
    preparing = null;
    notifyListeners();
    if (subjectId == null) return;
    unawaited(
      _perform(() async {
        final detail = await tracking.subject(subjectId, forPlayback: true);
        if (!_closed && sessionId == playback.session?['id']) {
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

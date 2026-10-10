import 'torrent_identity.dart';
import 'sources.dart';
import 'transfer.dart';

enum PlayKind {
  local('本地'),
  online('在线'),
  bt('BT'),
  pikpak('PikPak');

  const PlayKind(this.label);
  final String label;
}

/// What playing a candidate opens.
sealed class PlayTarget {
  const PlayTarget();
}

/// A file of an existing BT or PikPak cache task.
final class DownloadTarget extends PlayTarget {
  const DownloadTarget(this.downloadId, this.fileId, this.task);
  final String downloadId;
  final String? fileId;
  final DownloadTask task;
}

/// An online entry, or an upload whose part still has to be chosen.
final class OnlineTarget extends PlayTarget {
  const OnlineTarget({
    required this.candidateId,
    this.ref,
    this.chooseFrom,
    this.description,
  });
  final String candidateId;
  final StreamRef? ref;
  final SourceSubject? chooseFrom;
  final String? description;
}

/// A torrent that is enqueued before playback starts.
final class ReleaseTarget extends PlayTarget {
  const ReleaseTarget(this.candidate);
  final ReleaseCandidate candidate;
}

class PlayCandidate {
  PlayCandidate({
    required this.kind,
    required this.provider,
    required this.title,
    required this.target,
    required this.instant,
    this.line = '',
    this.providerLabel,
    this.quality,
    this.languages = const {},
    this.existing = false,
    this.possibleMatch = false,
    this.health = 0,
    this.order = 0,
  });

  final PlayKind kind;
  final String provider, title, line;
  final String? quality, providerLabel;
  final Set<String> languages;
  final PlayTarget target;
  final bool instant, existing, possibleMatch;
  final int order;
  int health;

  /// A torrent is one candidate per site however its groups are enriched.
  String get id => switch (target) {
    DownloadTarget(:final downloadId, :final fileId) =>
      '${kind.name}:$provider:$line:$downloadId:${fileId ?? ''}',
    OnlineTarget(:final candidateId) =>
      '${kind.name}:$provider:$line:$candidateId',
    ReleaseTarget(:final candidate) =>
      '${kind.name}:$provider:${torrentIdentity(candidate.release.locator)}',
  };

  String get continuityKey {
    final family = switch (target) {
      DownloadTarget(:final task) => task.method.name,
      _ => kind.name,
    };
    return kind == PlayKind.online
        ? 'online:$provider:$line'
        : '$family:$line:${quality ?? ''}';
  }

  String get sourceLabel {
    final label = providerLabel ?? provider;
    return line.isEmpty ? label : '$label · $line';
  }
}

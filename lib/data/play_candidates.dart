import 'json.dart';
import 'resource_metadata.dart';
import 'resource_title.dart';

enum PlayKind {
  local('本地'),
  online('在线'),
  bt('BT'),
  pikpak('PikPak');

  const PlayKind(this.label);
  final String label;
}

class PlayCandidate {
  PlayCandidate({
    required this.kind,
    required this.provider,
    required this.title,
    required this.ref,
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
  final Json ref;
  final bool instant, existing, possibleMatch;
  final int order;
  int health;

  String get id {
    final identity = ref['downloadId'] != null
        ? '${ref['downloadId']}:${ref['fileId'] ?? ''}'
        : ref['path'] ??
              (kind == PlayKind.bt
                  ? resourceIdentity(ref)
                  : ref['candidateId'] ?? ref['ref'] ?? title);
    return '${kind.name}:$provider:$line:$identity';
  }

  String get continuityKey {
    final family = ref['downloadId'] != null
        ? '${ref['provider'] ?? 'bt'}'
        : kind.name;
    return kind == PlayKind.online
        ? 'online:$provider:$line'
        : '$family:$line:${quality ?? ''}';
  }

  String get sourceLabel {
    final label = providerLabel ?? provider;
    return line.isEmpty ? label : '$label · $line';
  }

  factory PlayCandidate.online(Json row, int order) => PlayCandidate(
    kind: PlayKind.online,
    provider: '${row['sourceId'] ?? row['providerId'] ?? row['provider']}',
    providerLabel: row['providerName'] as String?,
    title: '${row['title'] ?? '在线视频'}',
    line: '${row['line'] ?? ''}',
    quality: row['quality'] as String?,
    languages: (row['languages'] is List ? row['languages'] as List : [])
        .whereType<String>()
        .toSet(),
    ref: row,
    instant: true,
    possibleMatch: row['possibleMatch'] == true,
    order: order,
  );

  factory PlayCandidate.release(Json row, int order) {
    final info = describeResource(row);
    return PlayCandidate(
      kind: PlayKind.bt,
      provider: '${row['providerId'] ?? 'bt'}',
      providerLabel: '${row['providerName'] ?? 'BT'}',
      title: info.title,
      line: info.sourceGroups.join(' & '),
      quality: info.quality,
      languages: info.languages,
      ref: row,
      instant: false,
      order: order,
    );
  }
}

bool isMainEpisode(Json episode) =>
    episode['type'] == null ||
    episode['type'] == 0 ||
    episode['type'] == 'main';

bool subjectIsAiring(Json subject, {DateTime? now}) {
  final today = now ?? DateTime.now();
  for (final episode in objects(subject['episodes'])) {
    if (!isMainEpisode(episode)) continue;
    final date = DateTime.tryParse(
      '${episode['airdate'] ?? episode['airDate'] ?? ''}',
    );
    if (date != null &&
        date.isAfter(today.subtract(const Duration(days: 90)))) {
      return true;
    }
  }
  return false;
}

List<PlayCandidate> rankPlayCandidates(
  Iterable<PlayCandidate> candidates, {
  required bool onlineFirst,
  String? continuity,
  String language = 'auto',
}) {
  int tier(PlayCandidate c) => c.kind == PlayKind.local
      ? 0
      : switch (c.kind) {
          PlayKind.online => onlineFirst ? 1 : 2,
          PlayKind.bt => onlineFirst ? 2 : 1,
          PlayKind.pikpak => 3,
          PlayKind.local => 0,
        };
  int languageMatch(PlayCandidate c) =>
      c.languages.contains(switch (language) {
        'simplified' || 'chs' => '简体',
        'traditional' || 'cht' => '繁体',
        'japanese' || 'ja' => '日文',
        _ => '',
      })
      ? 1
      : 0;
  int quality(PlayCandidate c) => switch (c.quality) {
    '4K' || '2160p' => 3,
    '1080p' => 2,
    '720p' => 1,
    _ => 0,
  };
  final result = candidates.toList();
  result.sort((a, b) {
    for (final comparison in [
      tier(a).compareTo(tier(b)),
      (b.continuityKey == continuity ? 1 : 0).compareTo(
        a.continuityKey == continuity ? 1 : 0,
      ),
      languageMatch(b).compareTo(languageMatch(a)),
      quality(b).compareTo(quality(a)),
      b.health.compareTo(a.health),
      a.order.compareTo(b.order),
      a.provider.compareTo(b.provider),
      a.title.compareTo(b.title),
      a.id.compareTo(b.id),
    ]) {
      if (comparison != 0) return comparison;
    }
    return 0;
  });
  return result;
}

import 'dart:convert';

import '../../core/json.dart';
import '../../core/labeled.dart';
import '../../domain/resource_title.dart';

/// What a subscription does with a corrected release (`v2`) of an episode
/// it already cached.
enum RevisionPolicy implements Labeled {
  skip('跳过'),
  replaceUnwatched('替换没看的');

  const RevisionPolicy(this.label);
  @override
  final String label;
}

/// Which releases a subscription caches, in the terms of the resource
/// search's filters: each non-empty selection must be met.
class SubscriptionFilter {
  const SubscriptionFilter({
    this.groups = const {},
    this.preferred = false,
    this.smart = false,
    this.qualities = const {},
    this.languages = const {},
    this.forms = const {},
    this.online = false,
  });

  factory SubscriptionFilter.fromJson(Json value) => SubscriptionFilter(
    groups: _strings(value['groups']),
    preferred: value['preferred'] == true,
    smart: value['smart'] == true,
    qualities: _strings(value['qualities']),
    languages: resourceSubtitleSelection(_strings(value['languages']))
        .difference(resourceSubtitleForms.toSet()),
    forms: resourceSubtitleSelection(_strings(value['forms']))
        .intersection(resourceSubtitleForms.toSet()),
    online: value['online'] == true,
  );

  /// Groups chosen by name.
  final Set<String> groups;

  /// Also the preferred groups of the settings, as they stand at each check.
  final bool preferred;

  /// Groups picked from the show's releases at each check, by how soon and
  /// how fully they release it, instead of named or preferred ones.
  final bool smart;

  /// Of [resourceQualities]; of [resourceLanguages] and [resourceBilingual];
  /// and of [resourceSubtitleForms]. 简体 also takes 简繁 and 简日 releases,
  /// which state 简体 among others.
  final Set<String> qualities, languages, forms;

  /// Online sources fill in an episode no group has a release of yet that
  /// meets the filter, the first listing it at a quality [qualities] takes.
  /// Their entries state neither group nor subtitles.
  final bool online;

  /// Releases of every group count.
  bool get anyGroup => groups.isEmpty && !preferred && !smart;

  /// The groups whose releases count, with [preferredGroups] for [preferred].
  List<String> groupNames(List<String> preferredGroups) => [
    if (preferred) ...preferredGroups,
    ...groups,
  ];

  /// What [info] leaves unstated of the quality and subtitles, as
  /// [resourceSelectionGaps] tells, its subtitles read across its series by
  /// [subtitlesOf] as the resource search reads them; null when it fails one.
  List<String>? gaps(
    ResourceTitleInfo info,
    ResourceTitleInfo Function(ResourceTitleInfo) subtitlesOf,
  ) => switch ((
    resourceSelectionGaps(info, qualities: qualities),
    resourceSelectionGaps(
      subtitlesOf(info),
      languages: languages,
      subtitleForms: forms,
    ),
  )) {
    (final quality?, final subtitles?) => [...quality, ...subtitles],
    _ => null,
  };

  /// Which of the quality and subtitles [info] fails, as `画质` or
  /// `画质和字幕`, for a release [gaps] turns down.
  String failing(
    ResourceTitleInfo info,
    ResourceTitleInfo Function(ResourceTitleInfo) subtitlesOf,
  ) => [
    if (resourceSelectionGaps(info, qualities: qualities) == null) '画质',
    if (resourceSelectionGaps(
          subtitlesOf(info),
          languages: languages,
          subtitleForms: forms,
        ) ==
        null)
      '字幕',
  ].join('和');

  SubscriptionFilter copyWith({
    Set<String>? groups,
    bool? preferred,
    bool? smart,
    Set<String>? qualities,
    Set<String>? languages,
    Set<String>? forms,
    bool? online,
  }) => SubscriptionFilter(
    groups: groups ?? this.groups,
    preferred: preferred ?? this.preferred,
    smart: smart ?? this.smart,
    qualities: qualities ?? this.qualities,
    languages: languages ?? this.languages,
    forms: forms ?? this.forms,
    online: online ?? this.online,
  );

  Json toJson() => {
    'groups': groups.toList(),
    'preferred': preferred,
    'smart': smart,
    'qualities': _ordered(qualities, resourceQualities),
    'languages': _ordered(languages, resourceSubtitleChoices),
    'forms': _ordered(forms, resourceSubtitleForms),
    'online': online,
  };

  /// `偏好字幕组  1080p  简体  含在线源`.
  String get label => [
    switch ((groups.length, preferred)) {
      _ when smart => '智能选择字幕组',
      (0, false) => '不限字幕组',
      (0, true) => '偏好字幕组',
      (1, false) => groups.single,
      (final count, final preferred) =>
        '${preferred ? '偏好和其他 ' : ''}$count 个字幕组',
    },
    if (qualities.isNotEmpty) _ordered(qualities, resourceQualities).join('、'),
    if (languages.isNotEmpty || forms.isNotEmpty)
      _ordered({...languages, ...forms}, resourceSubtitleChoices).join('、'),
    if (online) '含在线源',
  ].join('  ');

  @override
  bool operator ==(Object other) =>
      other is SubscriptionFilter &&
      jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

/// One show followed as it airs: the releases it caches as each episode
/// comes out, and the book of what it cached.
class Subscription {
  Subscription({
    required this.subjectId,
    required this.title,
    required this.filter,
    required this.createdAt,
    this.coverUrl,
    this.finishedAt,
    this.checkedAt,
    this.failures = 0,
    this.issue,
    this.paused = false,
    this.adopted = false,
    Map<int, LedgerEntry>? ledger,
    List<SubscriptionEvent>? events,
    Set<String>? seen,
    Map<int, DateTime>? waiting,
    Set<int>? earlier,
  }) : ledger = ledger ?? {},
       events = events ?? [],
       seen = seen ?? {},
       waiting = waiting ?? {},
       earlier = earlier ?? {};

  factory Subscription.fromJson(Json value) => Subscription(
    subjectId: (value['subjectId'] as num).toInt(),
    title: value['title'] as String? ?? '',
    coverUrl: value['coverUrl'] as String?,
    filter: SubscriptionFilter.fromJson(object(value['filter'])),
    createdAt: _time(value['createdAt']) ?? DateTime.now(),
    finishedAt: _time(value['finishedAt']),
    checkedAt: _time(value['checkedAt']),
    failures: number(value['failures']).toInt(),
    issue: value['issue'] as String?,
    paused: value['paused'] == true,
    // Subscriptions saved without the flag were paused only when synced
    // from another device.
    adopted: value['adopted'] as bool? ?? value['paused'] == true,
    ledger: {
      for (final entry in object(value['ledger']).entries)
        ?int.tryParse(entry.key): LedgerEntry.fromJson(object(entry.value)),
    },
    events: objects(value['events']).map(SubscriptionEvent.fromJson).toList(),
    seen: {
      for (final identity in value['seen'] is List ? value['seen'] : [])
        if (identity is String) identity,
    },
    waiting: {
      for (final entry in object(value['waiting']).entries)
        if ((int.tryParse(entry.key), _time(entry.value)) case (
          final id?,
          final until?,
        ))
          id: until,
    },
    earlier: {
      for (final id in value['earlier'] is List ? value['earlier'] : [])
        if (id is num) id.toInt(),
    },
  );

  final int subjectId;
  String title;
  String? coverUrl;
  SubscriptionFilter filter;
  final DateTime createdAt;

  /// When every episode had aired and was cached; nothing is checked after.
  DateTime? finishedAt;
  DateTime? checkedAt;

  /// Checks failed in a row.
  int failures;

  /// Why the last check or download failed, until one succeeds.
  String? issue;

  /// Kept without caching on this device: a subscription another device
  /// synced here while this one only syncs them, or one the user stopped
  /// caching here.
  bool paused;

  /// Made on another device and synced here: what this device does with it
  /// follows the subscription sync setting.
  final bool adopted;

  /// The release cached for each episode, by Bangumi episode id.
  final Map<int, LedgerEntry> ledger;

  /// What the subscription did, the latest first.
  final List<SubscriptionEvent> events;

  /// Releases already judged, by torrent identity, so each is noted once.
  final Set<String> seen;

  /// Episodes whose late release the user chose to keep waiting for, until
  /// when the wait lasts.
  final Map<int, DateTime> waiting;

  /// Episodes aired before the subscription that it caches too, by
  /// Bangumi episode id.
  final Set<int> earlier;

  Json toJson() => {
    'subjectId': subjectId,
    'title': title,
    'coverUrl': coverUrl,
    'filter': filter.toJson(),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'finishedAt': finishedAt?.toUtc().toIso8601String(),
    'checkedAt': checkedAt?.toUtc().toIso8601String(),
    'failures': failures,
    'issue': issue,
    'paused': paused,
    'adopted': adopted,
    'ledger': {
      for (final entry in ledger.entries) '${entry.key}': entry.value.toJson(),
    },
    'events': [for (final event in events) event.toJson()],
    'seen': seen.toList(),
    'waiting': {
      for (final entry in waiting.entries)
        '${entry.key}': entry.value.toUtc().toIso8601String(),
    },
    'earlier': earlier.toList(),
  };

  /// What other devices learn of this subscription: the show and the filter.
  /// The book, the events, [paused] and [adopted] belong to this device.
  Json get synced => {
    'title': title,
    'coverUrl': coverUrl,
    'filter': filter.toJson(),
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  /// Notes [text] as the latest event, keeping the last 60.
  void note(
    String text, {
    SubscriptionEventKind kind = SubscriptionEventKind.info,
  }) {
    events.insert(0, SubscriptionEvent(DateTime.now(), text, kind));
    if (events.length > 60) events.removeRange(60, events.length);
  }

  /// Remembers [identity] as judged; false when it already was.
  bool judged(String identity) {
    if (!seen.add(identity)) return false;
    if (seen.length > 800) seen.remove(seen.first);
    return true;
  }
}

/// The release a subscription cached for one episode.
class LedgerEntry {
  LedgerEntry({
    required this.identity,
    required this.title,
    required this.at,
    this.taskId,
    this.replaces,
    this.revision = false,
    this.online = false,
    this.notified = false,
  });

  factory LedgerEntry.fromJson(Json value) => LedgerEntry(
    identity: value['identity'] as String? ?? '',
    title: value['title'] as String? ?? '',
    at: _time(value['at']) ?? DateTime.now(),
    taskId: value['taskId'] as String?,
    replaces: value['replaces'] as String?,
    revision: value['revision'] == true,
    online: value['online'] == true,
    notified: value['notified'] == true,
  );

  final String identity, title;
  final DateTime at;
  final String? taskId;

  /// The task of the earlier release a corrected one replaces once cached.
  final String? replaces;
  final bool revision;

  /// An online site's entry, not a torrent: no group's corrected release
  /// replaces it.
  final bool online;

  /// Whether its finished cache has been announced.
  bool notified;

  Json toJson() => {
    'identity': identity,
    'title': title,
    'at': at.toUtc().toIso8601String(),
    'taskId': taskId,
    'replaces': replaces,
    'revision': revision,
    'online': online,
    'notified': notified,
  };
}

enum SubscriptionEventKind { cached, started, skipped, failed, info }

class SubscriptionEvent {
  const SubscriptionEvent(this.at, this.text, this.kind);

  factory SubscriptionEvent.fromJson(Json value) => SubscriptionEvent(
    _time(value['at']) ?? DateTime.now(),
    value['text'] as String? ?? '',
    SubscriptionEventKind.values
            .where((kind) => kind.name == value['kind'])
            .firstOrNull ??
        SubscriptionEventKind.info,
  );

  final DateTime at;
  final String text;
  final SubscriptionEventKind kind;

  Json toJson() => {
    'at': at.toUtc().toIso8601String(),
    'text': text,
    'kind': kind.name,
  };
}

DateTime? _time(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;

Set<String> _strings(Object? value) =>
    value is List ? value.whereType<String>().toSet() : {};

List<String> _ordered(Set<String> values, List<String> order) => [
  for (final value in order)
    if (values.contains(value)) value,
  ...values.where((value) => !order.contains(value)).toList()..sort(),
];

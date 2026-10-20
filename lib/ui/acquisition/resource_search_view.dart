import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/catalog.dart';
import '../../domain/play_candidate.dart';
import '../../domain/resource_title.dart';
import '../../domain/sources.dart';
import '../../domain/transfer.dart';
import '../../features/acquisition/online_candidates.dart';
import '../../features/acquisition/resource_metadata.dart';
import '../../features/acquisition/title_matching.dart';
import '../../features/playback/play_selection.dart';
import '../../features/playback/resource_search.dart';
import '../core/page_widgets.dart';
import '../core/selection_controls.dart';
import '../core/subject_posters.dart';
import '../core/theme.dart';
import 'resource_batch_dialog.dart';
import 'resource_widgets.dart';

/// The kind segment, like the Sources page groups: online entries, torrents
/// over BT and torrents PikPak's index holds.
enum _Family {
  all('全部'),
  online('在线'),
  torrent('BT'),
  pikpak('PikPak');

  const _Family(this.label);
  final String label;

  static _Family of(PlayCandidate candidate) => switch (candidate.kind) {
    PlayKind.online => online,
    PlayKind.pikpak => pikpak,
    _ => torrent,
  };
}

/// A result, with the episode a whole-subject search matched it to.
typedef _Member = (
  PlayCandidate candidate,
  ResourceTitleInfo info,
  Episode? episode,
);

/// One row of the list: a result, or a series of single-episode releases
/// shown as one expandable entry.
class _Entry {
  _Entry(this.key, this.members);
  final String key;
  final List<_Member> members;
  bool get series => members.length > 1;
  String get id => series ? key : members.single.$1.id;
}

/// The display title of a series, without the episode of its release.
String _seriesTitle(ResourceTitleInfo info) => info.displayTitle
    .replaceFirst(
      RegExp(
        r'\s-\s?\d{1,3}(?:\.5)?(?:\(\d{1,4}\))?(?:\s*(?:v\d|END|完))?(?=\s|$)|(?<![a-z])EP\s?\d{1,3}(?:\s*END)?|\bS\d{1,2}E\d{1,3}\b|(?<=^|\s)\d{1,3}\(\d{1,4}\)(?=\s|$)',
        caseSensitive: false,
      ),
      ' ',
    )
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// The resource search shared by the resources page, the player's resource
/// sheet and the source picker: a search form, pinned local filters and one
/// table of online, BT and PikPak candidates. Hosts key it by subject and
/// chapter.
class ResourceSearchView extends StatefulWidget {
  static String formStorageId(int? subjectId, int? episodeId) =>
      'resource-form:$subjectId:$episodeId';

  const ResourceSearchView({
    super.key,
    required this.search,
    required this.onPlay,
    this.active = true,
    this.actions = const [],
  });
  final ResourceSearchController search;

  /// Plays [candidate] as [episode].
  final Future<void> Function(PlayCandidate candidate, Episode episode) onPlay;

  /// While active, a context that was never searched is searched with the
  /// form.
  final bool active;

  /// Trailing actions of the heading row, such as open-in-page and close.
  final List<Widget> actions;
  @override
  State<ResourceSearchView> createState() => _ResourceSearchViewState();
}

class _ResourceSearchViewState extends State<ResourceSearchView> {
  final keyword = TextEditingController(),
      episodeQuery = TextEditingController();
  final queryFocus = FocusNode(), episodeFocus = FocusNode();
  final excluded = <String>{}, expandedTitles = <String>{};
  final excludedProviders = <String>{};
  final qualities = <String>{}, groups = <String>{};
  final languages = <String>{}, subtitleForms = <String>{};
  // Downloads started here, by candidate id.
  final adding = <String>{};
  final downloadErrors = <String, String>{};
  final downloadTasks = <String, String>{};
  StreamSubscription<TransferSnapshot>? downloadChanges;
  final annotations = <String, ResourceTitleInfo>{};
  final entries = <String, Future<List<SourceEpisode>>>{};

  _Family kind = _Family.all;
  bool includeUnknown = false, searching = false;
  String? opening;
  PageStorageBucket? storage;
  bool formRestored = false, restoringForm = false;
  late final String storageId;
  ResourceSearchController get controller => widget.search;
  ResourceSearchState get state => controller.state;
  Subject? get subject => state.subject;
  Episode? get episode => state.episode;
  bool get searchBusy => controller.busy || searching;

  @override
  void initState() {
    super.initState();
    storageId = ResourceSearchView.formStorageId(subject?.id, episode?.id);
    keyword.addListener(saveForm);
    episodeQuery.addListener(saveForm);
    downloadChanges = controller.downloads.changes.stream.listen((_) {
      if (downloadTasks.isNotEmpty && mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    storage = PageStorage.maybeOf(context);
    if (!formRestored) {
      restoreForm();
      if (widget.active) searchIfNew();
    }
  }

  @override
  void didUpdateWidget(ResourceSearchView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) searchIfNew();
  }

  void searchIfNew() {
    if (state.terms != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && state.terms == null) unawaited(search());
    });
  }

  void restoreForm() {
    formRestored = true;
    final saved = storage?.readState(context, identifier: storageId);
    final form = saved is Map ? saved : const {};
    final terms = state.terms;
    restoringForm = true;
    keyword.text =
        form['keyword'] as String? ?? terms?.keyword ?? subject?.title ?? '';
    episodeQuery.text =
        form['episode'] as String? ??
        terms?.episodeKeyword ??
        resourceEpisodeKeyword(episode);
    Iterable<String> strings(Object? value) =>
        value is List ? value.whereType<String>() : const [];
    kind = _Family.values.asNameMap()[form['kind']] ?? _Family.all;
    qualities.addAll(strings(form['qualities']));
    groups.addAll(strings(form['sourceGroups']));
    languages.addAll(strings(form['languages']));
    subtitleForms.addAll(strings(form['subtitleForms']));
    includeUnknown = form['includeUnknown'] as bool? ?? false;
    excluded.addAll(strings(form['excluded']));
    excludedProviders.addAll(strings(form['excludedProviders']));
    expandedTitles.addAll(strings(form['expandedTitles']));
    restoringForm = false;
  }

  void saveForm() {
    if (restoringForm || !mounted) return;
    storage?.writeState(context, {
      'keyword': keyword.text,
      'episode': episodeQuery.text,
      'kind': kind.name,
      'qualities': qualities.toList(),
      'sourceGroups': groups.toList(),
      'languages': languages.toList(),
      'subtitleForms': subtitleForms.toList(),
      'includeUnknown': includeUnknown,
      'excluded': excluded.toList(),
      'excludedProviders': excludedProviders.toList(),
      'expandedTitles': expandedTitles.toList(),
    }, identifier: storageId);
  }

  void changeForm(VoidCallback update) {
    setState(update);
    saveForm();
  }

  @override
  void dispose() {
    downloadChanges?.cancel();
    keyword.dispose();
    episodeQuery.dispose();
    queryFocus.dispose();
    episodeFocus.dispose();
    super.dispose();
  }

  Future<void> search() async {
    if (searchBusy) return;
    setState(() {
      searching = true;
      entries.clear();
    });
    try {
      await controller.search(
        ResourceTerms(
          keyword: keyword.text,
          names: [
            if (subject != null)
              for (final name in resourceNames(subject!))
                if (!excluded.contains(name)) name,
          ],
          episodeKeyword: episodeQuery.text,
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('搜索失败，请重试。')));
      }
    } finally {
      if (mounted) setState(() => searching = false);
    }
  }

  void clearFilters() => changeForm(() {
    for (final set in [qualities, groups, languages, subtitleForms]) {
      set.clear();
    }
    includeUnknown = false;
    excludedProviders.clear();
    kind = _Family.all;
  });

  void toggle(Set<String> set, String value, bool selected) =>
      changeForm(() => selected ? set.add(value) : set.remove(value));

  static String summary(Set<String> selected, List<String> order) {
    if (selected.length == 1) return selected.single;
    final ordered = order.where(selected.contains).toList();
    return ordered.length == selected.length && selected.length <= 2
        ? ordered.join(' / ')
        : '${selected.length} 项';
  }

  /// The task a download from this view created, while it exists.
  DownloadTask? taskOf(PlayCandidate candidate) =>
      switch (downloadTasks[candidate.id]) {
        final id? => controller.downloads.snapshot().task(id),
        null => null,
      };

  /// Downloads [candidate] as [episode], by default the shown chapter.
  Future<void> download(PlayCandidate candidate, {Episode? episode}) async {
    final id = candidate.id;
    if (adding.contains(id) || taskOf(candidate) != null) return;
    final method = candidate.kind == PlayKind.pikpak
        ? CacheMethod.pikpak
        : CacheMethod.bt;
    setState(() {
      adding.add(id);
      downloadErrors.remove(id);
    });
    try {
      final task = await switch (candidate.target) {
        ReleaseTarget(candidate: final release) => controller.enqueue(
          release,
          method: method,
          episode: episode,
        ),
        _ => controller.saveOnline(candidate, episode: episode),
      };
      if (mounted) setState(() => downloadTasks[id] = task.id);
    } catch (error) {
      if (mounted) {
        setState(
          () => downloadErrors[id] =
              '添加失败：${error.toString().replaceFirst('Bad state: ', '')}',
        );
      }
    } finally {
      if (mounted) setState(() => adding.remove(id));
    }
  }

  bool playable(PlayCandidate candidate, Episode? target) =>
      target != null &&
      switch (candidate.target) {
        DownloadTarget() => false,
        OnlineTarget(:final chooseFrom) => chooseFrom == null,
        ReleaseTarget() => true,
      };

  Future<void> play(PlayCandidate candidate, Episode target) async {
    if (opening != null) return;
    if (candidate.possibleMatch) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('确认条目匹配'),
          content: Text('请确认所选资源对应第 ${target.number} 话：\n${candidate.title}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('播放'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() => opening = candidate.id);
    try {
      await widget.onPlay(candidate, target);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Bad state: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => opening = null);
    }
  }

  /// Lets the user choose a range of [options], episode ids of the subject
  /// with the result that holds each, and downloads them in order.
  Future<void> downloadRange(
    Map<int, PlayCandidate> options, {
    required String title,
    required String source,
  }) async {
    final subject = this.subject!;
    final chosen = await showResourceBatchDialog(
      context,
      title: title,
      source: source,
      episodes: subject.episodes,
      available: options.keys.toSet(),
      added: {
        for (final MapEntry(key: id, value: candidate) in options.entries)
          if (adding.contains(candidate.id) || taskOf(candidate) != null) id,
      },
      cached: {
        for (final task in controller.downloads.snapshot().forSubject(
          subject.id,
        ))
          ?task.episodeId,
      },
    );
    if (chosen == null || !mounted) return;
    for (final episode in chosen) {
      await download(options[episode.id]!, episode: episode);
      if (!mounted) return;
    }
  }

  /// Cached annotations, renewed when site metadata adds release groups.
  ResourceTitleInfo annotate(PlayCandidate candidate) {
    final previous = annotations[candidate.id];
    final releaseGroups = switch (candidate.target) {
      ReleaseTarget(candidate: ReleaseCandidate(:final release)) =>
        release.releaseGroups,
      DownloadTarget(:final task) => task.releaseGroups,
      OnlineTarget() => const <String>[],
    };
    if (previous != null && listEquals(previous.sourceGroups, releaseGroups)) {
      return previous;
    }
    return annotations[candidate.id] = describeCandidate(candidate);
  }

  List<String> notesOf(PlayCandidate candidate) => [
    if (candidate.target case OnlineTarget(:final description?)) description,
  ];

  List<String> warningsOf(PlayCandidate candidate) => [
    if (candidate.kind == PlayKind.online)
      ?switch (controller.sources.status(candidate.provider)) {
        SourceHealth.error => '站点失效',
        SourceHealth.verification => '站点需要验证',
        _ => null,
      },
    if (candidate.possibleMatch) '可能匹配',
    if (candidate.health < 0) '最近播放失败',
  ];

  /// Entries of an upload or site subject, grouped by line; each plays as
  /// the shown chapter or, for a whole-subject search, the matching one.
  Widget entryPicker(PlayCandidate parent) {
    final upload = (parent.target as OnlineTarget).chooseFrom!;
    final small = Theme.of(context).textTheme.bodySmall;
    return FutureBuilder<List<SourceEpisode>>(
      future: entries[parent.id] ??= controller.entries(parent),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Row(
            children: [
              Text(
                '读取失败：${snapshot.error}',
                style: small?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
              TextButton(
                onPressed: () => setState(() => entries.remove(parent.id)),
                child: const Text('重试'),
              ),
            ],
          );
        }
        final rows = snapshot.data;
        if (rows == null) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: Gap.sm),
            child: SizedBox(
              width: 160,
              child: LinearProgressIndicator(minHeight: 2),
            ),
          );
        }
        if (rows.isEmpty) return Text('没有可播放的条目', style: small);
        final lines =
            <String, List<(PlayCandidate, SourceEpisode, Episode?)>>{};
        for (final row in rows) {
          (lines[row.line] ??= []).add((
            onlinePartCandidate(parent, upload, row),
            row,
            episode ??
                subject?.episodes
                    .where((e) => sourceEpisodeMatches(row.label, e))
                    .firstOrNull,
          ));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final MapEntry(key: line, value: items) in lines.entries) ...[
              entryLineHeader(
                lines.length > 1 && line.isNotEmpty ? line : null,
                items,
              ),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final (candidate, item, target) in items)
                    entryButton(candidate, item, target),
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  /// A line's name, when there are several, and an action downloading every
  /// entry of it that matches a chapter.
  Widget entryLineHeader(
    String? line,
    List<(PlayCandidate, SourceEpisode, Episode?)> items,
  ) {
    // Matched by label even under a chapter, where every entry plays as it.
    final options = <int, PlayCandidate>{
      for (final (candidate, item, _) in items)
        if (subject?.episodes
                .where((e) => sourceEpisodeMatches(item.label, e))
                .firstOrNull
            case final episode?)
          episode.id: candidate,
    };
    return Padding(
      padding: const EdgeInsets.only(top: Gap.xs, bottom: Gap.xs),
      child: Row(
        children: [
          if (line != null)
            Flexible(
              child: Text(
                line,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (line != null) const SizedBox(width: Gap.sm),
          if (options.length > 1)
            TextButton.icon(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: () => downloadRange(
                options,
                title: line ?? items.first.$1.title,
                source: items.first.$1.sourceLabel,
              ),
              icon: const Icon(Icons.download_rounded, size: 16),
              label: const Text('批量下载'),
            ),
        ],
      ),
    );
  }

  /// Plays the entry as its chapter; the trailing action downloads it.
  Widget entryButton(
    PlayCandidate candidate,
    SourceEpisode item,
    Episode? target,
  ) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Tooltip(
        message: target == null
            ? '没有对应的集数'
            : ['作为第 ${target.number} 话播放', ?item.description].join('  '),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(44, 32),
            ),
            onPressed: target == null || opening != null
                ? null
                : () => play(candidate, target),
            child: opening == candidate.id
                ? const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
        ),
      ),
      if (target != null) ...[
        const SizedBox(width: 2),
        ResourceDownloadButton(
          adding: adding.contains(candidate.id),
          task: taskOf(candidate),
          failed: downloadErrors.containsKey(candidate.id),
          onPressed: () => download(candidate, episode: target),
        ),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([controller, controller.sources]),
    builder: _page,
  );

  Widget _page(BuildContext context, Widget? _) {
    final names = subject == null ? const <String>[] : resourceNames(subject!);
    final aliases = names.where((name) => name != keyword.text.trim()).toList();
    final candidates = state.candidates;
    final sources = state.sources;
    bool providerShown(PlayCandidate candidate) =>
        !excludedProviders.contains(candidate.provider);
    bool kindShown(PlayCandidate candidate) =>
        kind == _Family.all || _Family.of(candidate) == kind;
    final annotated = candidates
        .map((candidate) => (candidate, annotate(candidate)))
        .toList();
    final fromShownProviders = annotated
        .where((entry) => providerShown(entry.$1))
        .toList();
    final matching = fromShownProviders
        .where(
          (entry) => matchesResourceSelection(
            entry.$2,
            qualities: qualities,
            groups: groups,
            languages: languages,
            subtitleForms: subtitleForms,
            includeUnknown: includeUnknown,
          ),
        )
        .toList();
    final visible = matching.where((entry) => kindShown(entry.$1)).toList();
    // Option counts cover results of the shown sites and kind, before other
    // filters; kind counts cover every other filter.
    Map<String, int> tally(Iterable<String> Function(ResourceTitleInfo) of) {
      final counts = <String, int>{};
      for (final entry in fromShownProviders.where((e) => kindShown(e.$1))) {
        for (final value in of(entry.$2)) {
          counts[value] = (counts[value] ?? 0) + 1;
        }
      }
      return counts;
    }

    final qualityCounts = tally(
      (info) => info.quality == null ? const [] : [info.quality!],
    );
    final groupCounts = tally((info) => info.sourceGroups);
    final languageCounts = tally((info) => info.languages);
    final formCounts = tally((info) => info.subtitleForms);
    final groupNames = {...groupCounts.keys, ...groups}.toList()
      ..sort((a, b) {
        final byCount = (groupCounts[b] ?? 0).compareTo(groupCounts[a] ?? 0);
        return byCount != 0 ? byCount : a.compareTo(b);
      });
    MelonFilterOption<String> counted(String value, Map<String, int> counts) =>
        MelonFilterOption(
          value,
          value,
          detail: '${counts[value] ?? 0}',
          enabled: (counts[value] ?? 0) > 0,
        );
    final kindCounts = {
      for (final value in _Family.values)
        value: value == _Family.all
            ? matching.length
            : matching.where((e) => _Family.of(e.$1) == value).length,
    };
    // Results are ranked, so the first shown confident match is the best of
    // what the filters leave.
    final recommended = visible.firstOrNull?.$1;
    final recommendedId = recommended == null || recommended.possibleMatch
        ? null
        : recommended.id;
    // Without an episode term, one group's single-episode releases of a
    // series on one site form an entry; releases holding none of the
    // subject's episodes, such as an earlier season's, follow the rest.
    final grouping = state.terms?.episodeKeyword.trim().isEmpty ?? false;
    final entries = <_Entry>[], unmatched = <_Entry>[];
    final bySeries = <String, _Entry>{};
    for (final (candidate, info) in visible) {
      final release = grouping && candidate.target is ReleaseTarget;
      final target = release ? releaseEpisode(subject!, info) : null;
      final member = (candidate, info, target);
      final rest = release && info.episode != null && target == null
          ? unmatched
          : entries;
      final key = switch (info.series) {
        final series? when release =>
          'series:${candidate.kind.name}:${candidate.provider}:'
              '${target != null}:$series',
        _ => null,
      };
      if (bySeries[key] case final entry?) {
        entry.members.add(member);
      } else {
        final entry = _Entry(key ?? candidate.id, [member]);
        rest.add(entry);
        if (key != null) bySeries[key] = entry;
      }
    }
    entries.addAll(unmatched);
    bool belongs(_Member member) =>
        !grouping ||
        member.$3 != null ||
        member.$2.episode == null ||
        member.$1.target is! ReleaseTarget;
    Widget resultRow(_Member member) {
      final (candidate, info, target) = member;
      final expanded = expandedTitles.contains(candidate.id);
      final chapter = target ?? episode;
      return ResourceArrival(
        child: ResourceResultRow(
          candidate: candidate,
          info: info,
          expanded: expanded,
          onExpand: () => changeForm(() {
            if (!expandedTitles.remove(candidate.id)) {
              expandedTitles.add(candidate.id);
            }
          }),
          notes: [
            ...notesOf(candidate),
            if (target != null && target.sort != info.episode)
              '对应第 ${target.number} 话',
          ],
          warnings: [...warningsOf(candidate), if (!belongs(member)) '未对应本作剧集'],
          recommended: candidate.id == recommendedId,
          playing: opening == candidate.id,
          onPlay: playable(candidate, chapter) && opening == null
              ? () => play(candidate, chapter!)
              : null,
          error: downloadErrors[candidate.id],
          details: switch (candidate.target) {
            OnlineTarget(chooseFrom: _?) when expanded => entryPicker(
              candidate,
            ),
            _ => null,
          },
          download: switch (candidate.target) {
            ReleaseTarget() ||
            OnlineTarget(ref: _?) => (wide) => ResourceDownloadButton(
              adding: adding.contains(candidate.id),
              task: taskOf(candidate),
              failed: downloadErrors.containsKey(candidate.id),
              showLabel: wide,
              onPressed: () => download(candidate, episode: target),
            ),
            _ => null,
          },
        ),
      );
    }

    Widget seriesRow(_Entry entry) {
      final (best, info, _) = entry.members.first;
      final members = [...entry.members]
        ..sort(
          (a, b) => (a.$3?.sort ?? a.$2.episode!).compareTo(
            b.$3?.sort ?? b.$2.episode!,
          ),
        );
      // The best-ranked release of each episode.
      final options = <int, PlayCandidate>{
        for (final (candidate, _, target) in entry.members.reversed)
          if (target != null) target.id: candidate,
      };
      final each = <double, PlayCandidate>{
        for (final (candidate, info, target) in entry.members.reversed)
          target?.sort ?? info.episode!: candidate,
      };
      final bytes = [
        for (final candidate in each.values)
          if (candidate.target case ReleaseTarget(
            candidate: ReleaseCandidate(:final release),
          ))
            releaseBytes(release),
      ].nonNulls;
      final dates = [
        for (final (candidate, _, _) in entry.members)
          if (candidate.target case ReleaseTarget(
            candidate: ReleaseCandidate(:final release),
          ))
            resourceDateLabel(release),
      ].where((date) => date != '—').toList()..sort();
      final expanded = expandedTitles.contains(entry.key);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ResourceArrival(
            child: ResourceSeriesRow(
              candidate: best,
              info: info,
              title: _seriesTitle(info),
              coverage: '第 ${episodeSpans(each.keys)} 话',
              size: bytes.isEmpty
                  ? '—'
                  : resourceBytesLabel(bytes.reduce((a, b) => a + b)),
              date: dates.lastOrNull ?? '—',
              expanded: expanded,
              onExpand: () => changeForm(() {
                if (!expandedTitles.remove(entry.key)) {
                  expandedTitles.add(entry.key);
                }
              }),
              recommended: best.id == recommendedId,
              warnings: [if (options.isEmpty) '未对应本作剧集'],
              added:
                  options.isNotEmpty &&
                  options.values.every(
                    (candidate) => taskOf(candidate) != null,
                  ),
              onBatch: options.isEmpty
                  ? null
                  : () => downloadRange(
                      options,
                      title: [
                        resourceGroupLabel(info),
                        _seriesTitle(info),
                      ].where((e) => e.isNotEmpty).join('  '),
                      source: [
                        best.providerLabel ?? best.provider,
                        ?info.quality,
                        ...info.languages,
                        ...info.subtitleForms,
                      ].join(' · '),
                    ),
            ),
          ),
          if (expanded)
            ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final member in members) ...[
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    resultRow(member),
                  ],
                ],
              ),
            ),
        ],
      );
    }

    final providersFailed =
        sources.isNotEmpty &&
        sources.every((e) => e.status == SearchStatus.error) &&
        candidates.isEmpty;
    final allProvidersExcluded =
        sources.isNotEmpty &&
        sources.every(
          (provider) => excludedProviders.contains(provider.sourceId),
        );
    final filtered =
        [
          qualities,
          groups,
          languages,
          subtitleForms,
        ].any((e) => e.isNotEmpty) ||
        includeUnknown ||
        excludedProviders.isNotEmpty;
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    final background = Material.of(context).color!;
    final includedAliases = aliases.where((name) => !excluded.contains(name));
    final aliasMenu = MelonFilterMenu<String>(
      key: const ValueKey('resource-aliases-toggle'),
      compact: true,
      label: '别名',
      active: includedAliases.isNotEmpty,
      summary: '${includedAliases.length}',
      tooltip: '同时搜索勾选的别名',
      sections: [
        MelonFilterSection([
          for (final name in aliases) MelonFilterOption(name, name),
        ], title: aliases.isEmpty ? '没有其他名称' : '同时搜索这些名称'),
      ],
      selected: includedAliases.toSet(),
      onToggle: (name, selected) => changeForm(
        () => selected ? excluded.remove(name) : excluded.add(name),
      ),
      actions: [
        if (aliases.isNotEmpty)
          includedAliases.isEmpty
              ? ('全部勾选', () => changeForm(() => excluded.removeAll(aliases)))
              : ('全部取消', () => changeForm(() => excluded.addAll(aliases))),
      ],
    );
    final sourceRegistry = controller.sources;
    final failingSites = [
      if (state.terms != null &&
          (kind == _Family.all || kind == _Family.online))
        for (final rule in sourceRegistry.instancesOf(SourceKind.online))
          if (sourceRegistry.isEnabled(rule.id) &&
              (sourceRegistry.errors.containsKey(rule.id) ||
                  sourceRegistry.status(rule.id) == SourceHealth.update))
            rule,
    ];
    final form = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(7)),
              child: SizedBox(
                width: 34,
                height: 46,
                child: SubjectCover(
                  url: subject?.coverUrl,
                  title: subject?.title ?? '未命名',
                  id: subject?.id ?? 0,
                ),
              ),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subject?.title ?? '未命名',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (episode != null) ...[
                    const SizedBox(height: 2),
                    Text('第 ${episode!.number} 话', style: small),
                  ],
                ],
              ),
            ),
            ...widget.actions,
          ],
        ),
        const SizedBox(height: Gap.md),
        LayoutBuilder(
          builder: (context, constraints) {
            final keywordField = TextField(
              controller: keyword,
              focusNode: queryFocus,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => search(),
              decoration: InputDecoration(
                hintText: '资源关键词',
                prefixIcon: const Icon(Icons.search, size: 19),
                suffixIcon: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: aliasMenu,
                ),
              ),
            );
            final episodeField = TextField(
              controller: episodeQuery,
              focusNode: episodeFocus,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => search(),
              decoration: const InputDecoration(
                hintText: '如 01 / S01E01',
                prefixText: '集数  ',
              ),
            );
            final button = Tooltip(
              message: searchBusy ? '正在搜索资源…' : '搜索资源',
              child: FilledButton(
                onPressed: searchBusy ? null : search,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Opacity(
                      opacity: searchBusy ? 0 : 1,
                      child: const Text('搜索'),
                    ),
                    if (searchBusy)
                      const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
              ),
            );
            if (constraints.maxWidth < 490) {
              return Column(
                children: [
                  keywordField,
                  const SizedBox(height: Gap.md),
                  Row(
                    children: [
                      Expanded(child: episodeField),
                      const SizedBox(width: 10),
                      button,
                    ],
                  ),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: keywordField),
                const SizedBox(width: 10),
                SizedBox(width: 168, child: episodeField),
                const SizedBox(width: 10),
                button,
              ],
            );
          },
        ),
        if (searchBusy) ...[
          const SizedBox(height: Gap.md),
          ResourceSearchStatus(providers: sources),
        ],
        for (final rule in failingSites)
          Padding(
            padding: const EdgeInsets.only(top: Gap.sm),
            child: Row(
              children: [
                const Icon(Icons.error_outline, size: 18, color: coral),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text(
                    '${rule.name}：${sourceRegistry.errors[rule.id] ?? '需要更新应用'}',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: small?.copyWith(color: scheme.error),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse(
                      rule.website ?? sourceRegistry.currentDomain(rule.id),
                    ),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.open_in_new, size: 15),
                  label: const Text('打开站点'),
                ),
              ],
            ),
          ),
      ],
    );
    final providerWarning = sources.any(
      (provider) => const [
        SearchStatus.error,
        SearchStatus.partial,
      ].contains(provider.status),
    );
    final shownProviders = sources
        .where((provider) => !excludedProviders.contains(provider.sourceId))
        .length;
    final filterBar = ColoredBox(
      color: background,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: pageGutter),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 4 * 96,
                  child: MelonSegmentedControl<_Family>(
                    key: const ValueKey('resource-filter-kind'),
                    semanticLabel: '资源类型',
                    options: {
                      for (final value in _Family.values)
                        value: '${value.label} ${kindCounts[value]}',
                    },
                    value: kind,
                    onChanged: (value) => changeForm(() => kind = value),
                  ),
                ),
                const Spacer(),
                if (filtered)
                  Text(
                    '筛选后 ${visible.length} 条',
                    style: small?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                if (state.terms != null && !grouping) ...[
                  const SizedBox(width: Gap.sm),
                  Tooltip(
                    message: '清空集数重新搜索，按字幕组归类后选择集数下载',
                    child: TextButton.icon(
                      onPressed: searchBusy
                          ? null
                          : () {
                              episodeQuery.clear();
                              search();
                            },
                      icon: const Icon(Icons.download_rounded, size: 17),
                      label: const Text('批量下载'),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: Gap.sm),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final menu in <Widget>[
                    MelonFilterMenu<String>(
                      key: const ValueKey('resource-filter-providers'),
                      label: '资源站',
                      icon: Icons.public_rounded,
                      active: excludedProviders.isNotEmpty,
                      summary: '$shownProviders / ${sources.length}',
                      warning: providerWarning,
                      tooltip: providerWarning
                          ? '有资源站搜索失败，打开查看'
                          : '显示或隐藏资源站的结果',
                      sections: [
                        MelonFilterSection([
                          for (final provider in sources)
                            MelonFilterOption(
                              provider.sourceId,
                              provider.sourceName,
                              detail: resourceProviderStatus(provider),
                              detailColor:
                                  const [
                                    SearchStatus.error,
                                    SearchStatus.partial,
                                  ].contains(provider.status)
                                  ? scheme.tertiary
                                  : null,
                            ),
                        ], title: sources.isEmpty ? '搜索后显示资源站' : null),
                      ],
                      selected: {
                        for (final provider in sources)
                          if (!excludedProviders.contains(provider.sourceId))
                            provider.sourceId,
                      },
                      onToggle: (id, selected) => changeForm(
                        () => selected
                            ? excludedProviders.remove(id)
                            : excludedProviders.add(id),
                      ),
                      actions: [
                        if (excludedProviders.isNotEmpty)
                          ('全部显示', () => changeForm(excludedProviders.clear)),
                      ],
                    ),
                    MelonFilterMenu<String>(
                      key: const ValueKey('resource-filter-quality'),
                      label: '画质',
                      icon: Icons.high_quality_outlined,
                      summary: summary(qualities, resourceQualities),
                      tooltip: '按画质筛选',
                      sections: [
                        MelonFilterSection([
                          for (final value in resourceQualities)
                            counted(value, qualityCounts),
                        ]),
                      ],
                      selected: qualities,
                      onToggle: (value, on) => toggle(qualities, value, on),
                      actions: [
                        if (qualities.isNotEmpty)
                          ('清除', () => changeForm(qualities.clear)),
                      ],
                    ),
                    MelonFilterMenu<String>(
                      key: const ValueKey('resource-filter-groups'),
                      label: '字幕组',
                      icon: Icons.groups_outlined,
                      summary: summary(groups, groupNames),
                      tooltip: '按字幕组筛选',
                      sections: [
                        MelonFilterSection([
                          for (final name in groupNames)
                            counted(name, groupCounts),
                        ], title: groupNames.isEmpty ? '暂无字幕组信息' : null),
                      ],
                      selected: groups,
                      onToggle: (value, on) => toggle(groups, value, on),
                      actions: [
                        if (groups.isNotEmpty)
                          ('清除', () => changeForm(groups.clear)),
                      ],
                    ),
                    MelonFilterMenu<String>(
                      key: const ValueKey('resource-filter-language'),
                      label: '字幕',
                      icon: Icons.subtitles_outlined,
                      active: languages.isNotEmpty || subtitleForms.isNotEmpty,
                      summary: summary(
                        {...languages, ...subtitleForms},
                        [...resourceLanguages, ...resourceSubtitleForms],
                      ),
                      tooltip: '勾选“简体”也包含简繁、简日双语',
                      sections: [
                        MelonFilterSection([
                          for (final value in resourceLanguages)
                            counted(value, languageCounts),
                        ], title: '字幕语言'),
                        MelonFilterSection([
                          for (final value in resourceSubtitleForms)
                            counted(value, formCounts),
                        ], title: '字幕形式'),
                      ],
                      selected: {...languages, ...subtitleForms},
                      onToggle: (value, on) => toggle(
                        resourceLanguages.contains(value)
                            ? languages
                            : subtitleForms,
                        value,
                        on,
                      ),
                      actions: [
                        if (languages.isNotEmpty || subtitleForms.isNotEmpty)
                          (
                            '清除',
                            () => changeForm(() {
                              languages.clear();
                              subtitleForms.clear();
                            }),
                          ),
                      ],
                    ),
                  ]) ...[menu, const SizedBox(width: Gap.sm)],
                  Tooltip(
                    message: '同时显示没有标明画质、字幕组或字幕的资源',
                    child: FilterChip(
                      label: const Text('含未标明'),
                      selected: includeUnknown,
                      backgroundColor: scheme.surfaceContainerHigh,
                      showCheckmark: true,
                      checkmarkColor: scheme.primary,
                      onSelected: (value) =>
                          changeForm(() => includeUnknown = value),
                    ),
                  ),
                  if (filtered) ...[
                    const SizedBox(width: Gap.xs),
                    TextButton(
                      onPressed: clearFilters,
                      child: const Text('清除筛选'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return CustomScrollView(
      key: const PageStorageKey('page-scroll'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            pageGutter,
            Gap.lg,
            pageGutter,
            Gap.md,
          ),
          sliver: SliverToBoxAdapter(child: form),
        ),
        SliverPersistentHeader(
          pinned: true,
          delegate: _PinnedBar(height: 104, child: filterBar),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(pageGutter, 0, pageGutter, 40),
          sliver: SliverList.builder(
            itemCount: entries.length + 2,
            // Rows keep their state when new results reorder the list.
            findChildIndexCallback: (key) {
              final index = entries.indexWhere(
                (entry) => key == ValueKey(entry.id),
              );
              return index < 0 ? null : index + 1;
            },
            itemBuilder: (context, index) {
              if (index == 0) {
                return visible.isEmpty
                    ? const SizedBox.shrink()
                    : LayoutBuilder(
                        builder: (context, constraints) =>
                            constraints.maxWidth < resourceTableWidth
                            ? const SizedBox.shrink()
                            : Material(
                                color: scheme.surface,
                                borderRadius: BorderRadius.vertical(
                                  top: panelBorderRadius.topLeft,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    11,
                                    16,
                                    9,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '资源',
                                          style: small?.copyWith(fontSize: 11),
                                        ),
                                      ),
                                      for (final (label, width) in [
                                        ('来源', resourceGroupColumnWidth),
                                        ('大小', resourceSizeColumnWidth),
                                        ('发布', resourceDateColumnWidth),
                                      ]) ...[
                                        const SizedBox(width: Gap.md),
                                        SizedBox(
                                          width: width,
                                          child: Text(
                                            label,
                                            style: small?.copyWith(
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                      ],
                                      SizedBox(
                                        width:
                                            Gap.sm +
                                            resourceActionsWidth(wide: true),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                      );
              }
              if (index == entries.length + 1) {
                final emptyKind = matching.isNotEmpty;
                return (visible.isEmpty &&
                        (allProvidersExcluded ||
                            !searchBusy ||
                            candidates.isNotEmpty))
                    ? EmptyState(
                        text: allProvidersExcluded
                            ? '已隐藏全部资源站的结果'
                            : emptyKind
                            ? '此分类暂无资源'
                            : candidates.isNotEmpty
                            ? '没有符合筛选条件的资源'
                            : providersFailed
                            ? '资源站暂时无法连接'
                            : '没有找到资源，试试其他名称或清空集数关键词',
                        action: allProvidersExcluded
                            ? () => changeForm(excludedProviders.clear)
                            : emptyKind
                            ? () => changeForm(() => kind = _Family.all)
                            : candidates.isNotEmpty
                            ? clearFilters
                            : () {
                                if (!providersFailed) episodeQuery.clear();
                                search();
                              },
                        actionLabel: allProvidersExcluded
                            ? '显示全部资源站'
                            : emptyKind
                            ? '查看全部'
                            : candidates.isNotEmpty
                            ? '清除筛选'
                            : !providersFailed && episodeQuery.text.isNotEmpty
                            ? '清空集数并搜索'
                            : '重新搜索',
                      )
                    : const SizedBox.shrink();
              }
              final i = index - 1;
              final entry = entries[i];
              return LayoutBuilder(
                key: ValueKey(entry.id),
                builder: (context, constraints) => Material(
                  color: scheme.surface,
                  borderRadius: BorderRadius.vertical(
                    top: i == 0 && constraints.maxWidth < resourceTableWidth
                        ? panelBorderRadius.topLeft
                        : Radius.zero,
                    bottom: i == entries.length - 1
                        ? panelBorderRadius.bottomLeft
                        : Radius.zero,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (i > 0)
                        const Divider(height: 1, indent: 16, endIndent: 16),
                      entry.series
                          ? seriesRow(entry)
                          : resultRow(entry.members.single),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PinnedBar extends SliverPersistentHeaderDelegate {
  const _PinnedBar({required this.height, required this.child});
  final double height;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      SizedBox.expand(child: child);

  @override
  bool shouldRebuild(_PinnedBar oldDelegate) => true;
}

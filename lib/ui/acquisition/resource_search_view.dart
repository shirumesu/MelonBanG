import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/error_message.dart';
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
import '../core/external_link.dart';
import '../core/byte_units.dart';
import '../core/motion.dart';
import '../core/page_widgets.dart';
import '../core/selection_controls.dart';
import '../core/subject_posters.dart';
import '../core/theme.dart';
import 'resource_batch_dialog.dart';
import 'group_filter.dart';
import 'resource_results.dart';
import 'resource_widgets.dart';

/// An entry of an upload or site subject, with the episode it plays as.
typedef _Part = (
  PlayCandidate candidate,
  SourceEpisode entry,
  Episode? episode,
);

final _episodeSuffix = RegExp(
  r'\s-\s?\d{1,3}(?:\.5)?(?:\(\d{1,4}\))?(?:\s*(?:v\d|END|完))?(?=\s|$)|(?<![a-z])EP\s?\d{1,3}(?:\s*END)?|\bS\d{1,2}E\d{1,3}\b|(?<=^|\s)\d{1,3}\(\d{1,4}\)(?=\s|$)',
  caseSensitive: false,
);
final _spaces = RegExp(r'\s+');

/// The display title of a series, without the episode of its release.
String _seriesTitle(ResourceTitleInfo info) => info.displayTitle
    .replaceFirst(_episodeSuffix, ' ')
    .replaceAll(_spaces, ' ')
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
    this.onOpenDownloads,
  });
  final ResourceSearchController search;

  /// Plays [candidate] as [episode].
  final Future<void> Function(PlayCandidate candidate, Episode episode) onPlay;

  /// While active, a context that was never searched is searched with the
  /// form.
  final bool active;

  /// Trailing actions of the heading row, such as open-in-page and close.
  final List<Widget> actions;

  /// Opens the cache page; given, a download added here offers it.
  final VoidCallback? onOpenDownloads;
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
  late final StreamSubscription<TransferSnapshot> downloadChanges;
  final annotations = <String, ResourceTitleInfo>{};
  // Entries of online subjects, by candidate id.
  final parts = <String, Future<List<SourceEpisode>>>{};

  ResourceFamily kind = ResourceFamily.all;
  bool searching = false;
  String? opening;
  PageStorageBucket? storage;
  bool formRestored = false, restoringForm = false;
  late final String storageId;
  ResourceSearchController get controller => widget.search;
  ResourceSearchState get state => controller.state;
  Subject? get subject => state.subject;
  Episode? get episode => state.episode;
  Episode? get searched => state.searched;
  bool get searchBusy => controller.busy || searching;

  @override
  void initState() {
    super.initState();
    storageId = ResourceSearchView.formStorageId(subject?.id, episode?.id);
    keyword.addListener(saveForm);
    episodeQuery.addListener(saveForm);
    downloadChanges = controller.downloads.changes.stream.listen((_) {
      if (downloadTasks.isNotEmpty) setState(() {});
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
    kind =
        ResourceFamily.values.asNameMap()[form['kind']] ?? ResourceFamily.all;
    qualities.addAll(strings(form['qualities']));
    groups.addAll(strings(form['sourceGroups']));
    languages.addAll(strings(form['languages']));
    subtitleForms.addAll(strings(form['subtitleForms']));
    excluded.addAll(strings(form['excluded']));
    excludedProviders.addAll(strings(form['excludedProviders']));
    expandedTitles.addAll(strings(form['expandedTitles']));
    restoringForm = false;
  }

  void saveForm() {
    if (restoringForm) return;
    storage?.writeState(context, {
      'keyword': keyword.text,
      'episode': episodeQuery.text,
      'kind': kind.name,
      'qualities': qualities.toList(),
      'sourceGroups': groups.toList(),
      'languages': languages.toList(),
      'subtitleForms': subtitleForms.toList(),
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
    downloadChanges.cancel();
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
      parts.clear();
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
            .showSnackBar(const SnackBar(content: Text('搜索失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => searching = false);
    }
  }

  void clearFilters() => changeForm(() {
    for (final set in [qualities, groups, languages, subtitleForms]) {
      set.clear();
    }
    excludedProviders.clear();
    kind = ResourceFamily.all;
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

  /// Downloads [candidate] as [episode], by default the searched one;
  /// whether a task was added.
  Future<bool> download(PlayCandidate candidate, {Episode? episode}) async {
    final id = candidate.id;
    if (adding.contains(id) || taskOf(candidate) != null) return false;
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
      return true;
    } catch (error) {
      if (mounted) {
        setState(() => downloadErrors[id] = '添加失败：${errorMessage(error)}');
      }
      return false;
    } finally {
      if (mounted) setState(() => adding.remove(id));
    }
  }

  Future<void> downloadOne(PlayCandidate candidate, {Episode? episode}) async {
    if (await download(candidate, episode: episode)) offerDownloads(1);
  }

  /// Confirms [count] added downloads, with the way to the cache page.
  void offerDownloads(int count) {
    final open = widget.onOpenDownloads;
    if (open == null || count == 0 || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(count == 1 ? '已加入缓存' : '已将 $count 话加入缓存'),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(label: '查看缓存', onPressed: open),
      ),
    );
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
      final confirmed = await showMelonDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('确认条目匹配'),
          content: Text('请确认所选资源对应${target.label}：\n${candidate.title}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('观看'),
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(errorMessage(error))));
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
        )) ...{?task.episodeId, ...episodeFiles(subject, task).keys},
      },
    );
    if (chosen == null || !mounted) return;
    var added = 0;
    for (final episode in chosen) {
      if (await download(options[episode.id]!, episode: episode)) added++;
      if (!mounted) return;
    }
    offerDownloads(added);
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
    if (controller.state.remembered?.affinity(candidate) == 2) '上次选择',
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

  /// Entries of an upload or site subject by line; each plays as the
  /// searched episode or, for a whole-subject search, the one its label
  /// names.
  Map<String, List<_Part>> linesOf(
    PlayCandidate parent,
    List<SourceEpisode> rows,
  ) {
    final upload = (parent.target as OnlineTarget).chooseFrom!;
    final lines = <String, List<_Part>>{};
    for (final row in rows) {
      (lines[row.line] ??= []).add((
        onlinePartCandidate(parent, upload, row),
        row,
        searched ??
            subject?.episodes
                .where((e) => sourceEpisodeMatches(row.label, e))
                .firstOrNull,
      ));
    }
    return lines;
  }

  /// Episode ids of a line with the first entry holding each.
  static Map<int, PlayCandidate> lineOptions(List<_Part> items) => {
    for (final (candidate, _, target) in items.reversed)
      if (target != null) target.id: candidate,
  };

  /// Reads an online subject's entries and downloads a range of the line
  /// holding the most episodes; a failed read shows in its expanded row.
  Future<void> downloadOnline(PlayCandidate parent) async {
    final id = parent.id;
    final future = parts[id] ??= controller.entries(parent);
    setState(() {});
    final List<SourceEpisode> rows;
    try {
      rows = await future;
    } catch (_) {
      if (mounted) changeForm(() => expandedTitles.add(id));
      return;
    }
    if (!mounted) return;
    final lines = linesOf(parent, rows).entries.toList()
      ..sort(
        (a, b) => lineOptions(b.value).length - lineOptions(a.value).length,
      );
    final options = lines.isEmpty
        ? const <int, PlayCandidate>{}
        : lineOptions(lines.first.value);
    if (options.isEmpty) {
      changeForm(() => expandedTitles.add(id));
      return;
    }
    await downloadRange(
      options,
      title: parent.title,
      source: [
        parent.sourceLabel,
        if (lines.length > 1) lines.first.key,
      ].join('  '),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      controller,
      controller.sources,
      controller.playback.settings,
    ]),
    builder: _page,
  );

  Widget _page(BuildContext context, Widget? _) {
    final results = ResourceResults(
      [
        for (final candidate in state.candidates)
          (candidate, annotate(candidate)),
      ],
      excludedProviders: excludedProviders,
      qualities: qualities,
      groups: groups,
      languages: languages,
      subtitleForms: subtitleForms,
      kind: kind,
      subject: subject,
      grouping: state.terms != null && searched == null,
      onlyGroups: controller.playback.settings.onlyPreferredGroups
          ? controller.playback.settings.preferredGroups
          : const [],
    );
    final entries = results.entries;
    final scheme = Theme.of(context).colorScheme;
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
          sliver: SliverToBoxAdapter(child: _form(context)),
        ),
        SliverPersistentHeader(
          pinned: true,
          delegate: _PinnedBar(
            height: 104,
            child: _filterBar(context, results),
          ),
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
                return results.visible.isEmpty
                    ? const SizedBox.shrink()
                    : _tableHeader(context);
              }
              if (index == entries.length + 1) {
                return _emptyResults(results);
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
                          ? _seriesRow(results, entry)
                          : switch (entry.members.single) {
                              final member &&
                                  (
                                    PlayCandidate(
                                      target: OnlineTarget(chooseFrom: _?),
                                    ),
                                    _,
                                    _,
                                  ) =>
                                _onlineRow(results, member),
                              final member => _resultRow(results, member),
                            },
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

  Widget _form(BuildContext context) {
    final names = subject == null ? const <String>[] : resourceNames(subject!);
    final aliases = names.where((name) => name != keyword.text.trim()).toList();
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    final shownEpisode = state.terms == null ? episode : searched;
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
          (kind == ResourceFamily.all || kind == ResourceFamily.online))
        for (final rule in sourceRegistry.instancesOf(SourceKind.online))
          if (sourceRegistry.isEnabled(rule.id) &&
              (sourceRegistry.errors.containsKey(rule.id) ||
                  sourceRegistry.status(rule.id) == SourceHealth.update))
            rule,
    ];
    return Column(
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
                  if (shownEpisode != null) ...[
                    const SizedBox(height: 2),
                    Text(shownEpisode.label, style: small),
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
                    // Keeps the button as wide as its label.
                    const Opacity(opacity: 0, child: Text('搜索')),
                    MotionSwap(
                      value: searchBusy,
                      child: searchBusy
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('搜索'),
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
                      const SizedBox(width: Gap.md),
                      button,
                    ],
                  ),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: keywordField),
                const SizedBox(width: Gap.md),
                SizedBox(width: 168, child: episodeField),
                const SizedBox(width: Gap.md),
                button,
              ],
            );
          },
        ),
        MotionReveal(
          visible: searchBusy,
          child: Padding(
            padding: const EdgeInsets.only(top: Gap.md),
            child: ResourceSearchStatus(
              providers: state.sites,
              cloud: state.cloud,
            ),
          ),
        ),
        for (final rule in failingSites)
          Padding(
            padding: const EdgeInsets.only(top: Gap.sm),
            child: Row(
              children: [
                Icon(Icons.error_outline, size: 18, color: scheme.error),
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
                  onPressed: () => openExternal(
                    context,
                    rule.website ?? sourceRegistry.currentDomain(rule.id),
                  ),
                  icon: const Icon(Icons.open_in_new, size: 15),
                  label: const Text('打开站点'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _filterBar(BuildContext context, ResourceResults results) {
    final sources = state.sites;
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    final background = Material.of(context).color!;
    MelonFilterOption<String> counted(String value, Map<String, int> counts) =>
        MelonFilterOption(
          value,
          value,
          detail: '${counts[value] ?? 0}',
          enabled: (counts[value] ?? 0) > 0,
        );
    final filtered =
        [
          qualities,
          groups,
          languages,
          subtitleForms,
        ].any((e) => e.isNotEmpty) ||
        excludedProviders.isNotEmpty;
    final providerWarning = sources.any(
      (provider) => const [
        SearchStatus.error,
        SearchStatus.partial,
      ].contains(provider.status),
    );
    final shownProviders = sources
        .where((provider) => !excludedProviders.contains(provider.sourceId))
        .length;
    return ColoredBox(
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
                  child: MelonSegmentedControl<ResourceFamily>(
                    key: const ValueKey('resource-filter-kind'),
                    semanticLabel: '资源类型',
                    options: {
                      for (final value in ResourceFamily.values)
                        value: '${value.label} ${results.kindCounts[value]}',
                    },
                    value: kind,
                    onChanged: (value) => changeForm(() => kind = value),
                  ),
                ),
                const Spacer(),
                if (filtered)
                  Text(
                    '筛选后 ${results.visible.length} 条',
                    style: small?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                if (state.terms != null && !results.grouping) ...[
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
                            counted(value, results.qualityCounts),
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
                      summary: summary(groups, results.groupNames),
                      tooltip: '按字幕组筛选，拖动设置偏好字幕组',
                      sections: const [],
                      panel: GroupFilterPanel(
                        prefs: controller.playback.settings,
                        names: results.groupNames,
                        counts: results.groupCounts,
                        selected: groups,
                        onToggle: (value, on) => toggle(groups, value, on),
                      ),
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
                            counted(value, results.languageCounts),
                        ], title: '字幕语言'),
                        MelonFilterSection([
                          for (final value in resourceSubtitleForms)
                            counted(value, results.formCounts),
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
  }

  /// The column headings of the result table, shown when it is wide.
  Widget _tableHeader(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    return LayoutBuilder(
      builder: (context, constraints) =>
          constraints.maxWidth < resourceTableWidth
          ? const SizedBox.shrink()
          : Material(
              color: scheme.surface,
              borderRadius: BorderRadius.vertical(
                top: panelBorderRadius.topLeft,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('资源', style: small?.copyWith(fontSize: 11)),
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
                          style: small?.copyWith(fontSize: 11),
                        ),
                      ),
                    ],
                    SizedBox(width: Gap.sm + resourceActionsWidth(wide: true)),
                  ],
                ),
              ),
            ),
    );
  }

  /// Why no result shows, with the action that brings some back.
  Widget _emptyResults(ResourceResults results) {
    final candidates = state.candidates, sources = state.sites;
    final providersFailed =
        sources.isNotEmpty &&
        sources.every((e) => e.status == SearchStatus.error) &&
        candidates.isEmpty;
    final allProvidersExcluded =
        sources.isNotEmpty &&
        sources.every(
          (provider) => excludedProviders.contains(provider.sourceId),
        );
    final emptyKind = results.matching.isNotEmpty;
    return (results.visible.isEmpty &&
            (allProvidersExcluded || !searchBusy || candidates.isNotEmpty))
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
                ? () => changeForm(() => kind = ResourceFamily.all)
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

  Widget _resultRow(ResourceResults results, ResourceMember member) {
    final (candidate, info, target) = member;
    final expanded = expandedTitles.contains(candidate.id);
    final chapter = target ?? searched;
    return MotionAppear(
      milliseconds: 240,
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
          ...results.unstated(candidate),
          if (target != null && target.sort != info.episode)
            '对应${target.label}',
        ],
        warnings: [
          ...warningsOf(candidate),
          if (!results.belongs(member)) '未对应本作剧集',
        ],
        recommended: candidate.id == results.recommendedId,
        playing: opening == candidate.id,
        onPlay: playable(candidate, chapter) && opening == null
            ? () => play(candidate, chapter!)
            : null,
        error: downloadErrors[candidate.id],
        download: switch (candidate.target) {
          ReleaseTarget() ||
          OnlineTarget(ref: _?) => (wide) => ResourceDownloadButton(
            adding: adding.contains(candidate.id),
            task: taskOf(candidate),
            failed: downloadErrors.containsKey(candidate.id),
            showLabel: wide,
            onPressed: () => downloadOne(candidate, episode: target),
          ),
          _ => null,
        },
      ),
    );
  }

  /// A release of an expanded series, showing what sets it apart.
  Widget _memberRow(ResourceMember member, bool wide) {
    final (candidate, info, target) = member;
    final release = (candidate.target as ReleaseTarget).candidate.release;
    final expanded = expandedTitles.contains(candidate.id);
    return ResourceEpisodeRow(
      label: target == null
          ? info.episodeLabel!
          : target.numberedApart
          ? target.label
          : '第 ${target.number.padLeft(2, '0')} 话',
      wide: wide,
      title: info.title,
      detailUrl: release.detailUrl,
      expanded: expanded,
      onExpand: () => changeForm(() {
        if (!expandedTitles.remove(candidate.id)) {
          expandedTitles.add(candidate.id);
        }
      }),
      notes: [
        if (target != null && target.sort != info.episode)
          '标题为${info.episodeLabel}',
      ],
      warnings: [...info.warnings, ...warningsOf(candidate)],
      size: resourceSizeLabel(release, ByteUnitsScope.of(context)),
      date: resourceDateLabel(release),
      error: downloadErrors[candidate.id],
      download: ResourceDownloadButton(
        adding: adding.contains(candidate.id),
        task: taskOf(candidate),
        failed: downloadErrors.containsKey(candidate.id),
        showLabel: wide,
        onPressed: () => downloadOne(candidate, episode: target),
      ),
      play: playable(candidate, target)
          ? ResourcePlayButton(
              onPressed: opening == null
                  ? () => play(candidate, target!)
                  : null,
              instant: candidate.instant,
              playing: opening == candidate.id,
              showLabel: wide,
            )
          : null,
    );
  }

  Widget _seriesRow(ResourceResults results, ResourceEntry entry) {
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
        MotionAppear(
          milliseconds: 240,
          child: ResourceSeriesRow(
            candidate: best,
            info: info,
            title: _seriesTitle(info),
            group: resourceGroupLabel(info),
            coverage: '第 ${episodeSpans(each.keys)} 话',
            size: bytes.isEmpty
                ? '—'
                : resourceBytesLabel(
                    bytes.reduce((a, b) => a + b),
                    ByteUnitsScope.of(context),
                  ),
            date: dates.lastOrNull ?? '—',
            expanded: expanded,
            onExpand: () => changeForm(() {
              if (!expandedTitles.remove(entry.key)) {
                expandedTitles.add(entry.key);
              }
            }),
            recommended: best.id == results.recommendedId,
            notes: [
              if (controller.state.remembered?.affinity(best) == 2) '上次选择',
              ...results.unstated(best),
            ],
            warnings: [if (options.isEmpty) '未对应本作剧集'],
            action: (wide) => ResourceBatchButton(
              showLabel: wide,
              added:
                  options.isNotEmpty &&
                  options.values.every(
                    (candidate) => taskOf(candidate) != null,
                  ),
              onPressed: options.isEmpty
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
                      ].join('  '),
                    ),
            ),
          ),
        ),
        MotionReveal(
          visible: expanded,
          child: ResourceEpisodePanel(
            rows: (wide) => [
              for (final member in members) _memberRow(member, wide),
            ],
          ),
        ),
      ],
    );
  }

  /// An online subject: its entries, read when first needed, are its
  /// episodes, by line.
  Widget _onlineRow(ResourceResults results, ResourceMember member) {
    final (candidate, info, _) = member;
    final id = candidate.id;
    final expanded = expandedTitles.contains(id);
    final future = expanded
        ? parts[id] ??= controller.entries(candidate)
        : parts[id];
    final small = Theme.of(context).textTheme.bodySmall;
    return FutureBuilder<List<SourceEpisode>>(
      future: future,
      builder: (context, snapshot) {
        final rows = snapshot.data;
        final lines = rows == null ? null : linesOf(candidate, rows);
        final matched = {
          for (final items in lines?.values ?? const <List<_Part>>[])
            for (final (_, _, target) in items) ?target?.sort,
        };
        final options = lines?.values
            .map(lineOptions)
            .fold(
              <int, PlayCandidate>{},
              (a, b) => b.length > a.length ? b : a,
            );
        Widget line(String name, List<_Part> items) {
          final options = lineOptions(items);
          return Padding(
            padding: const EdgeInsets.fromLTRB(26, 4, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    name.isEmpty ? '默认线路' : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: small?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                if (searched == null && options.length > 1)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => downloadRange(
                      options,
                      title: candidate.title,
                      source: [candidate.sourceLabel, name].join('  '),
                    ),
                    icon: const Icon(Icons.download_rounded, size: 16),
                    label: const Text('批量下载'),
                  ),
              ],
            ),
          );
        }

        Widget part(_Part part, bool wide) {
          final (entry, item, target) = part;
          return ResourceEpisodeRow(
            label: item.label,
            wide: wide,
            notes: [
              if (searched != null) '作为${searched!.label}',
              ?item.description,
            ],
            warnings: [if (target == null) '未对应本作剧集'],
            error: downloadErrors[entry.id],
            download: target == null
                ? null
                : ResourceDownloadButton(
                    adding: adding.contains(entry.id),
                    task: taskOf(entry),
                    failed: downloadErrors.containsKey(entry.id),
                    showLabel: wide,
                    onPressed: () => downloadOne(entry, episode: target),
                  ),
            play: target == null
                ? null
                : ResourcePlayButton(
                    onPressed: opening == null
                        ? () => play(entry, target)
                        : null,
                    instant: true,
                    playing: opening == entry.id,
                    showLabel: wide,
                  ),
          );
        }

        Widget notice(Widget child) => Padding(
          padding: const EdgeInsets.fromLTRB(26, 8, 8, 8),
          child: child,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MotionAppear(
              milliseconds: 240,
              child: ResourceSeriesRow(
                candidate: candidate,
                info: info,
                title: info.displayTitle,
                group: candidate.line,
                coverage: rows == null
                    ? null
                    : searched == null && matched.isNotEmpty
                    ? '第 ${episodeSpans(matched)} 话'
                    : '${rows.length} 个条目',
                notes: [...notesOf(candidate), ...results.unstated(candidate)],
                warnings: warningsOf(candidate),
                recommended: id == results.recommendedId,
                expanded: expanded,
                onExpand: () => changeForm(() {
                  if (!expandedTitles.remove(id)) expandedTitles.add(id);
                }),
                action: searched != null
                    ? null
                    : (wide) => ResourceBatchButton(
                        showLabel: wide,
                        loading:
                            future != null &&
                            snapshot.connectionState != ConnectionState.done,
                        added:
                            options != null &&
                            options.isNotEmpty &&
                            options.values.every(
                              (part) => taskOf(part) != null,
                            ),
                        onPressed: options != null && options.isEmpty
                            ? null
                            : () => downloadOnline(candidate),
                      ),
              ),
            ),
            MotionReveal(
              visible: expanded,
              child: ResourceEpisodePanel(
                rows: (wide) => [
                  if (snapshot.hasError)
                    notice(
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              '读取失败：${errorMessage(snapshot.error!)}',
                              style: small?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => setState(() => parts.remove(id)),
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    )
                  else if (rows == null)
                    notice(
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: 160,
                          child: LinearProgressIndicator(minHeight: 2),
                        ),
                      ),
                    )
                  else if (rows.isEmpty)
                    notice(Text('没有可播放的条目', style: small))
                  else
                    for (final MapEntry(key: name, value: items)
                        in lines!.entries) ...[
                      if (lines.length > 1) line(name, items),
                      for (final item in items) part(item, wide),
                    ],
                ],
              ),
            ),
          ],
        );
      },
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

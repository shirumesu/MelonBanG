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
import '../../features/playback/resource_search.dart';
import '../core/page_widgets.dart';
import '../core/selection_controls.dart';
import '../core/subject_posters.dart';
import '../core/theme.dart';
import 'resource_widgets.dart';

/// The resource search shared by the resources page, the player's resource
/// sheet and the source picker: a search form, pinned local filters and one
/// table of cached, online and torrent candidates. Hosts key it by subject
/// and chapter.
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

  /// Plays [candidate] as [episode]; the episode is null only for a cached
  /// file without a chapter.
  final Future<void> Function(PlayCandidate candidate, Episode? episode) onPlay;

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
  final downloadPhases = <String, ResourceDownloadPhase>{};
  final downloadErrors = <String, String>{};
  final annotations = <String, ResourceTitleInfo>{};
  final entries = <String, Future<List<SourceEpisode>>>{};

  /// 'all' or a [PlayKind] name.
  String kind = 'all';
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
    kind = form['kind'] as String? ?? 'all';
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
      'kind': kind,
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
    kind = 'all';
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

  String downloadKey(PlayCandidate candidate, CacheMethod method) =>
      '${candidate.id}:${method.name}';

  ResourceDownloadPhase phaseFor(PlayCandidate candidate, CacheMethod method) =>
      downloadPhases[downloadKey(candidate, method)] ??
      ResourceDownloadPhase.idle;

  String? errorFor(PlayCandidate candidate) {
    final method = controller.defaultMethod();
    for (final value in [method, method.other]) {
      final error = downloadErrors[downloadKey(candidate, value)];
      if (error != null) return '添加失败：${value.label}：$error';
    }
    return null;
  }

  Future<void> download(
    PlayCandidate candidate,
    ReleaseCandidate release,
    CacheMethod method,
  ) async {
    final id = downloadKey(candidate, method);
    if (CacheMethod.values.any(
          (value) => phaseFor(candidate, value) == ResourceDownloadPhase.adding,
        ) ||
        [
          ResourceDownloadPhase.adding,
          ResourceDownloadPhase.added,
        ].contains(downloadPhases[id])) {
      return;
    }
    setState(() {
      downloadPhases[id] = ResourceDownloadPhase.adding;
      downloadErrors.remove(id);
    });
    try {
      await controller.enqueue(release, method: method);
      if (mounted) {
        setState(() => downloadPhases[id] = ResourceDownloadPhase.added);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          downloadPhases[id] = ResourceDownloadPhase.failed;
          downloadErrors[id] = error.toString().replaceFirst('Bad state: ', '');
        });
      }
    }
  }

  /// The chapter a candidate plays as; null when it has none.
  Episode? episodeOf(PlayCandidate candidate) =>
      episode ??
      switch (candidate.target) {
        DownloadTarget(task: DownloadTask(:final episodeId?)) =>
          subject?.episode(episodeId),
        _ => null,
      };

  bool playable(PlayCandidate candidate) => switch (candidate.target) {
    DownloadTarget() => true,
    OnlineTarget(:final chooseFrom) => chooseFrom == null,
    ReleaseTarget() => episode != null,
  };

  Future<void> play(PlayCandidate candidate, Episode? target) async {
    if (opening != null) return;
    if (candidate.possibleMatch) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('确认条目匹配'),
          content: Text(
            '请确认所选资源对应${target == null ? '本作' : '第 ${target.number} 话'}：\n${candidate.title}',
          ),
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

  ResourceTitleInfo annotate(PlayCandidate candidate) {
    final (title, releaseGroups) = switch (candidate.target) {
      ReleaseTarget(candidate: ReleaseCandidate(:final release)) => (
        release.title,
        release.releaseGroups,
      ),
      DownloadTarget(:final task) => (task.title, task.releaseGroups),
      OnlineTarget() => (candidate.title, const <String>[]),
    };
    final previous = annotations[candidate.id];
    if (previous != null &&
        previous.title == title &&
        listEquals(previous.sourceGroups, releaseGroups)) {
      return previous;
    }
    return annotations[candidate.id] = describeResource(
      title,
      releaseGroups: releaseGroups,
    );
  }

  List<String> notesOf(PlayCandidate candidate) => [
    if (candidate.kind == PlayKind.online)
      ?switch (controller.sources.status(candidate.provider)) {
        SourceHealth.partial => '站点部分失败',
        SourceHealth.error => '站点失效',
        SourceHealth.verification => '站点需要验证',
        _ => null,
      },
    if (candidate.target case OnlineTarget(:final description?)) description,
    if (candidate.possibleMatch) '可能匹配',
    if (candidate.health < 0) '近期播放失败',
    if (!candidate.instant && episode != null) '边下边播',
    if (candidate.target case DownloadTarget(:final task) when !task.complete)
      '已下载 ${(task.progress * 100).floor()}%',
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
        final lines = <String, List<SourceEpisode>>{};
        for (final row in rows) {
          (lines[row.line] ??= []).add(row);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final MapEntry(key: line, value: items) in lines.entries) ...[
              if (lines.length > 1 && line.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: Gap.sm),
                  child: Text(line, style: small),
                ),
              const SizedBox(height: Gap.xs),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final item in items)
                    entryButton(
                      onlinePartCandidate(parent, upload, item),
                      item,
                      episode ??
                          subject?.episodes
                              .where((e) => sourceEpisodeMatches(item.label, e))
                              .firstOrNull,
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  Widget entryButton(
    PlayCandidate candidate,
    SourceEpisode item,
    Episode? target,
  ) => Tooltip(
    message: target == null
        ? '没有对应的本作集数'
        : item.description ?? '作为第 ${target.number} 话播放',
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
            : Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    ),
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
        candidate.target is DownloadTarget ||
        !excludedProviders.contains(candidate.provider);
    bool kindShown(PlayCandidate candidate) =>
        kind == 'all' || candidate.kind.name == kind;
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
      for (final value in PlayKind.values)
        value.name: matching.where((e) => e.$1.kind == value).length,
    };
    final recommended = episode != null && candidates.isNotEmpty
        ? candidates.first.id
        : null;
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
      tooltip: '同时用勾选的别名搜索，结果合并显示',
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
          (kind == 'all' || kind == PlayKind.online.name))
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
                  const SizedBox(height: 2),
                  Text(
                    episode == null
                        ? '本地缓存、在线源与 BT 资源 · 集数留空可查找合集'
                        : '第 ${episode!.number} 话 · 播放和下载都会关联到这一话',
                    style: small,
                  ),
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
                TextButton(
                  onPressed: () => launchUrl(
                    Uri.parse(
                      rule.website ?? sourceRegistry.currentDomain(rule.id),
                    ),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: const Text('打开站点'),
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
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final menu in <Widget>[
                      MelonSegmentedControl<String>(
                        key: const ValueKey('resource-filter-kind'),
                        semanticLabel: '资源类型',
                        options: {
                          'all': '全部 · ${matching.length}',
                          for (final value in PlayKind.values)
                            if (value != PlayKind.pikpak ||
                                kindCounts[value.name]! > 0 ||
                                kind == value.name)
                              value.name:
                                  '${value.label} · ${kindCounts[value.name]}',
                        },
                        value: kind,
                        onChanged: (value) => changeForm(() => kind = value),
                      ),
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
                        tooltip: '按标题标注的输出画质筛选',
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
                        tooltip: '资源站标注的发布分组；标题中的联合署名单独展示',
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
                        active:
                            languages.isNotEmpty || subtitleForms.isNotEmpty,
                        summary: summary(
                          {...languages, ...subtitleForms},
                          [...resourceLanguages, ...resourceSubtitleForms],
                        ),
                        tooltip: '同一组内满足任一项即可，例如勾选“简体”也包含简繁、简日双语',
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
                      message: '筛选时保留标题没有标明画质、字幕组或字幕的资源',
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
            ),
            const SizedBox(width: Gap.md),
            Text(
              filtered || kind != 'all'
                  ? '${visible.length} / ${candidates.length} 条'
                  : '${candidates.length} 条',
              style: small?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
    final method = controller.defaultMethod();
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
          delegate: _PinnedBar(height: 56, child: filterBar),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(pageGutter, 0, pageGutter, 40),
          sliver: SliverList.builder(
            itemCount: visible.length + 2,
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
                                          '资源 · 标题标注',
                                          style: small?.copyWith(fontSize: 11),
                                        ),
                                      ),
                                      for (final (label, width) in [
                                        ('来源分组', resourceGroupColumnWidth),
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
              if (index == visible.length + 1) {
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
                            ? () => changeForm(() => kind = 'all')
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
              final (candidate, info) = visible[i];
              final expanded = expandedTitles.contains(candidate.id);
              final target = episodeOf(candidate);
              return LayoutBuilder(
                key: ValueKey(candidate.id),
                builder: (context, constraints) => Material(
                  color: scheme.surface,
                  borderRadius: BorderRadius.vertical(
                    top: i == 0 && constraints.maxWidth < resourceTableWidth
                        ? panelBorderRadius.topLeft
                        : Radius.zero,
                    bottom: i == visible.length - 1
                        ? panelBorderRadius.bottomLeft
                        : Radius.zero,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      if (i > 0)
                        const Divider(height: 1, indent: 16, endIndent: 16),
                      ResourceArrival(
                        child: ResourceResultRow(
                          candidate: candidate,
                          info: info,
                          expanded: expanded,
                          onExpand: () => changeForm(() {
                            if (!expandedTitles.remove(candidate.id)) {
                              expandedTitles.add(candidate.id);
                            }
                          }),
                          notes: notesOf(candidate),
                          recommended: candidate.id == recommended,
                          playing: opening == candidate.id,
                          onPlay: playable(candidate) && opening == null
                              ? () => play(candidate, target)
                              : null,
                          error: errorFor(candidate),
                          details: switch (candidate.target) {
                            OnlineTarget(chooseFrom: _?) when expanded =>
                              entryPicker(candidate),
                            _ => null,
                          },
                          download: switch (candidate.target) {
                            ReleaseTarget(candidate: final release) =>
                              (wide) => ResourceDownloadButton(
                                phase: phaseFor(candidate, method),
                                showLabel: wide,
                                onPressed: () =>
                                    download(candidate, release, method),
                                defaultMethod: method,
                                alternativePhase: phaseFor(
                                  candidate,
                                  method.other,
                                ),
                                onAlternative: () =>
                                    download(candidate, release, method.other),
                              ),
                            _ => null,
                          },
                        ),
                      ),
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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/cache_method.dart';
import '../../data/json.dart';
import '../../data/resource_metadata.dart';
import '../../data/resource_title.dart';
import '../core/page_widgets.dart';
import '../core/selection_controls.dart';
import '../core/subject_posters.dart';
import '../core/theme.dart';
import 'resource_widgets.dart';

class ResourcesPage extends StatefulWidget {
  static String formStorageId(int? subjectId, int? episodeId) =>
      'resource-form:$subjectId:$episodeId';

  const ResourcesPage({
    super.key,
    required this.subject,
    required this.resourceSearch,
    required this.resourceEpisode,
    required this.providers,
    required this.candidates,
    required this.busy,
    required this.onSearch,
    required this.onDownload,
    this.defaultMethod = CacheMethod.bt,
    this.onDownloadWithMethod,
  });
  final Json? subject;
  final TextEditingController resourceSearch;
  final int? resourceEpisode;
  final List<Json> providers, candidates;
  final bool busy;
  final Future<void> Function(List<String>, String) onSearch;
  final Future<void> Function(Json) onDownload;
  final CacheMethod defaultMethod;
  final Future<void> Function(Json, CacheMethod)? onDownloadWithMethod;
  @override
  State<ResourcesPage> createState() => _ResourcesPageState();
}

class _ResourcesPageState extends State<ResourcesPage> {
  final episodeQuery = TextEditingController();
  final queryFocus = FocusNode(), episodeFocus = FocusNode();
  final excluded = <String>{}, expandedTitles = <String>{};
  final excludedProviders = <String>{};
  final qualities = <String>{}, groups = <String>{};
  final languages = <String>{}, subtitleForms = <String>{};
  final downloadPhases = <String, ResourceDownloadPhase>{};
  final downloadErrors = <String, String>{};
  final annotations = <String, ResourceTitleInfo>{};
  bool includeUnknown = false, searching = false;
  PageStorageBucket? storage;
  bool formRestored = false, restoringForm = false;
  late String activeStorageId;
  bool get searchBusy => widget.busy || searching;

  String get storageId => ResourcesPage.formStorageId(
    widget.subject?['subjectId'] as int?,
    widget.resourceEpisode,
  );
  Json? get selectedEpisode =>
      objects(widget.subject?['episodes'])
          .where((episode) => episode['episodeId'] == widget.resourceEpisode)
          .firstOrNull;

  @override
  void initState() {
    super.initState();
    activeStorageId = storageId;
    episodeQuery.text = resourceEpisodeKeyword(selectedEpisode);
    episodeQuery.addListener(saveForm);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    storage = PageStorage.maybeOf(context);
    if (!formRestored) restoreForm();
  }

  @override
  void didUpdateWidget(ResourcesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (activeStorageId != storageId) {
      activeStorageId = storageId;
      restoringForm = true;
      episodeQuery.text = resourceEpisodeKeyword(selectedEpisode);
      includeUnknown = false;
      for (final set in [qualities, groups, languages, subtitleForms]) {
        set.clear();
      }
      excluded.clear();
      excludedProviders.clear();
      expandedTitles.clear();
      annotations.clear();
      restoringForm = false;
      restoreForm();
    }
  }

  void restoreForm() {
    formRestored = true;
    final saved = storage?.readState(context, identifier: activeStorageId);
    if (saved is! Map) return;
    restoringForm = true;
    episodeQuery.text =
        saved['episode'] as String? ?? resourceEpisodeKeyword(selectedEpisode);
    Iterable<String> strings(Object? value) =>
        value is List ? value.whereType<String>() : const [];
    qualities.addAll(strings(saved['qualities']));
    groups.addAll(strings(saved['sourceGroups']));
    languages.addAll(strings(saved['languages']));
    subtitleForms.addAll(strings(saved['subtitleForms']));
    includeUnknown = saved['includeUnknown'] as bool? ?? false;
    excluded.addAll(strings(saved['excluded']));
    excludedProviders.addAll(
      (saved['excludedProviders'] as List? ?? []).whereType<String>(),
    );
    expandedTitles.addAll(
      (saved['expandedTitles'] as List? ?? []).whereType<String>(),
    );
    restoringForm = false;
  }

  void saveForm() {
    if (restoringForm || !mounted) return;
    storage?.writeState(context, {
      'episode': episodeQuery.text,
      'qualities': qualities.toList(),
      'sourceGroups': groups.toList(),
      'languages': languages.toList(),
      'subtitleForms': subtitleForms.toList(),
      'includeUnknown': includeUnknown,
      'excluded': excluded.toList(),
      'excludedProviders': excludedProviders.toList(),
      'expandedTitles': expandedTitles.toList(),
    }, identifier: activeStorageId);
  }

  void changeForm(VoidCallback update) {
    setState(update);
    saveForm();
  }

  @override
  void dispose() {
    episodeQuery.dispose();
    queryFocus.dispose();
    episodeFocus.dispose();
    super.dispose();
  }

  Future<void> search() async {
    if (searchBusy) return;
    setState(() => searching = true);
    try {
      await widget.onSearch(
        resourceNames(widget.subject ?? {})
            .where((e) => !excluded.contains(e))
            .toList(),
        episodeQuery.text,
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

  String downloadKey(Json candidate, CacheMethod method) =>
      '${candidate['candidateId']}:${method.name}';

  ResourceDownloadPhase phaseFor(Json candidate, CacheMethod method) =>
      downloadPhases[downloadKey(candidate, method)] ??
      ResourceDownloadPhase.idle;

  String? errorFor(Json candidate) {
    for (final method in [widget.defaultMethod, widget.defaultMethod.other]) {
      final error = downloadErrors[downloadKey(candidate, method)];
      if (error != null) {
        return widget.onDownloadWithMethod == null
            ? error
            : '${method.label}：$error';
      }
    }
    return null;
  }

  Future<void> download(Json candidate, CacheMethod method) async {
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
      if (widget.onDownloadWithMethod case final callback?) {
        await callback(candidate, method);
      } else {
        await widget.onDownload(candidate);
      }
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

  ResourceTitleInfo annotate(Json candidate) {
    final id = '${candidate['candidateId']}';
    final previous = annotations[id];
    final groups = (candidate['releaseGroups'] as List? ?? [])
        .whereType<String>()
        .toList();
    if (previous != null &&
        previous.title == candidate['title'] &&
        listEquals(previous.sourceGroups, groups)) {
      return previous;
    }
    return annotations[id] = describeResource(candidate);
  }

  @override
  Widget build(BuildContext context) {
    final names = resourceNames(widget.subject ?? {});
    final aliases = names
        .where((name) => name != widget.resourceSearch.text.trim())
        .toList();
    final annotated = widget.candidates
        .map((candidate) => (candidate, annotate(candidate)))
        .toList();
    final fromShownProviders = annotated
        .where(
          (entry) => !excludedProviders.contains(resourceProviderKey(entry.$1)),
        )
        .toList();
    final visible = fromShownProviders
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
    // Option counts cover results from the shown sites, before other filters.
    Map<String, int> tally(Iterable<String> Function(ResourceTitleInfo) of) {
      final counts = <String, int>{};
      for (final entry in fromShownProviders) {
        for (final value in of(entry.$2)) {
          counts[value] = (counts[value] ?? 0) + 1;
        }
      }
      return counts;
    }

    final qualityCounts = tally((info) => info.qualities);
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
    final episode = selectedEpisode;
    final providersFailed =
        widget.providers.isNotEmpty &&
        widget.providers.every((e) => e['status'] == 'error');
    final allProvidersExcluded =
        widget.providers.isNotEmpty &&
        widget.providers.every(
          (provider) =>
              excludedProviders.contains(resourceProviderKey(provider)),
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
                  url: widget.subject?['coverUrl'],
                  title: titleOf(widget.subject ?? {}),
                  id: number(widget.subject?['subjectId']).toInt(),
                ),
              ),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titleOf(widget.subject ?? {}),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    episode == null
                        ? '查找字幕组与视频版本 · 集数留空可查找合集'
                        : '下载将关联到第 ${episode['sort']} 话',
                    style: small,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.md),
        LayoutBuilder(
          builder: (context, constraints) {
            final keyword = TextField(
              key: const PageStorageKey('resource-query'),
              controller: widget.resourceSearch,
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
              key: const PageStorageKey('resource-episode'),
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
                  keyword,
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
                Expanded(child: keyword),
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
          ResourceSearchStatus(providers: widget.providers),
        ],
      ],
    );
    final providerWarning = widget.providers.any(
      (provider) => ['error', 'partial'].contains(provider['status']),
    );
    final shownProviders = widget.providers
        .where(
          (provider) =>
              !excludedProviders.contains(resourceProviderKey(provider)),
        )
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
                      MelonFilterMenu<String>(
                        key: const ValueKey('resource-filter-providers'),
                        label: '资源站',
                        icon: Icons.public_rounded,
                        active: excludedProviders.isNotEmpty,
                        summary: '$shownProviders / ${widget.providers.length}',
                        warning: providerWarning,
                        tooltip: providerWarning
                            ? '有资源站搜索失败，打开查看'
                            : '显示或隐藏资源站的结果',
                        sections: [
                          MelonFilterSection(
                            [
                              for (final provider in widget.providers)
                                MelonFilterOption(
                                  resourceProviderKey(provider),
                                  '${provider['providerName']}',
                                  detail: resourceProviderStatus(provider),
                                  detailColor:
                                      [
                                        'error',
                                        'partial',
                                      ].contains(provider['status'])
                                      ? Theme.of(context).colorScheme.tertiary
                                      : null,
                                ),
                            ],
                            title: widget.providers.isEmpty ? '搜索后显示资源站' : null,
                          ),
                        ],
                        selected: {
                          for (final provider in widget.providers)
                            if (!excludedProviders.contains(
                              resourceProviderKey(provider),
                            ))
                              resourceProviderKey(provider),
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
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHigh,
                        showCheckmark: true,
                        checkmarkColor: Theme.of(context).colorScheme.primary,
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
              filtered
                  ? '${visible.length} / ${widget.candidates.length} 条'
                  : '${widget.candidates.length} 条',
              style: small?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
    final downloadWidth = resourceDownloadWidth(
      labelled: true,
      split: widget.onDownloadWithMethod != null,
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
          delegate: _PinnedBar(height: 56, child: filterBar),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(pageGutter, 0, pageGutter, 40),
          sliver: SliverList.list(
            children: [
              if (visible.isNotEmpty)
                LayoutBuilder(
                  builder: (context, constraints) =>
                      constraints.maxWidth < resourceTableWidth
                      ? const SizedBox.shrink()
                      : Material(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.vertical(
                            top: panelBorderRadius.topLeft,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 11, 16, 9),
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
                                      style: small?.copyWith(fontSize: 11),
                                    ),
                                  ),
                                ],
                                SizedBox(width: Gap.sm + downloadWidth),
                              ],
                            ),
                          ),
                        ),
                ),
              for (var i = 0; i < visible.length; i++)
                LayoutBuilder(
                  key: ValueKey(visible[i].$1['candidateId']),
                  builder: (context, constraints) => Material(
                    color: Theme.of(context).colorScheme.surface,
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
                            candidate: visible[i].$1,
                            info: visible[i].$2,
                            expanded: expandedTitles.contains(
                              '${visible[i].$1['candidateId']}',
                            ),
                            onExpand: () => changeForm(() {
                              final id = '${visible[i].$1['candidateId']}';
                              if (!expandedTitles.remove(id)) {
                                expandedTitles.add(id);
                              }
                            }),
                            phase: phaseFor(
                              visible[i].$1,
                              widget.defaultMethod,
                            ),
                            error: errorFor(visible[i].$1),
                            onDownload: () =>
                                download(visible[i].$1, widget.defaultMethod),
                            defaultMethod: widget.defaultMethod,
                            alternativePhase: phaseFor(
                              visible[i].$1,
                              widget.defaultMethod.other,
                            ),
                            onAlternative: widget.onDownloadWithMethod == null
                                ? null
                                : () => download(
                                    visible[i].$1,
                                    widget.defaultMethod.other,
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (visible.isEmpty &&
                  (allProvidersExcluded ||
                      !searchBusy ||
                      widget.candidates.isNotEmpty))
                EmptyState(
                  text: allProvidersExcluded
                      ? '已隐藏全部资源站的结果'
                      : widget.candidates.isNotEmpty
                      ? '没有符合筛选条件的资源'
                      : providersFailed
                      ? '资源站暂时无法连接'
                      : '没有找到资源，试试其他名称或清空集数关键词',
                  action: allProvidersExcluded
                      ? () => changeForm(excludedProviders.clear)
                      : widget.candidates.isNotEmpty
                      ? clearFilters
                      : () {
                          if (!providersFailed) episodeQuery.clear();
                          search();
                        },
                  actionLabel: allProvidersExcluded
                      ? '显示全部资源站'
                      : widget.candidates.isNotEmpty
                      ? '清除筛选'
                      : !providersFailed && episodeQuery.text.isNotEmpty
                      ? '清空集数并搜索'
                      : '重新搜索',
                ),
            ],
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

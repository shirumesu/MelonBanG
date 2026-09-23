import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/json.dart';
import '../../data/resource_metadata.dart';
import '../../data/resource_title.dart';
import '../core/motion.dart';
import '../core/page_widgets.dart';
import '../core/selection_controls.dart';
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
  });
  final Json? subject;
  final TextEditingController resourceSearch;
  final int? resourceEpisode;
  final List<Json> providers, candidates;
  final bool busy;
  final Future<void> Function(List<String>, String) onSearch;
  final Future<void> Function(Json) onDownload;
  @override
  State<ResourcesPage> createState() => _ResourcesPageState();
}

class _ResourcesPageState extends State<ResourcesPage> {
  final episodeQuery = TextEditingController();
  final queryFocus = FocusNode(), episodeFocus = FocusNode();
  final excluded = <String>{}, expandedTitles = <String>{};
  final excludedProviders = <String>{};
  final downloadPhases = <String, ResourceDownloadPhase>{};
  final downloadErrors = <String, String>{};
  final annotations = <String, ResourceTitleInfo>{};
  String quality = 'all', group = '';
  bool includeUnknown = false;
  bool multipleNames = true, aliasesExpanded = false, searching = false;
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
      quality = 'all';
      group = '';
      includeUnknown = false;
      multipleNames = true;
      aliasesExpanded = false;
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
    quality = saved['quality'] as String? ?? 'all';
    group = saved['sourceGroup'] as String? ?? '';
    includeUnknown = saved['includeUnknown'] as bool? ?? false;
    multipleNames = saved['multipleNames'] as bool? ?? true;
    aliasesExpanded = saved['aliasesExpanded'] as bool? ?? false;
    excluded.addAll((saved['excluded'] as List? ?? []).whereType<String>());
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
      'quality': quality,
      'sourceGroup': group,
      'includeUnknown': includeUnknown,
      'multipleNames': multipleNames,
      'aliasesExpanded': aliasesExpanded,
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
        multipleNames
            ? resourceNames(widget.subject ?? {})
                  .where((e) => !excluded.contains(e))
                  .toList()
            : [],
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
    quality = 'all';
    group = '';
    includeUnknown = false;
    excludedProviders.clear();
  });

  Future<void> download(Json candidate) async {
    final id = '${candidate['candidateId']}';
    if ([
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
      await widget.onDownload(candidate);
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
    final annotated = widget.candidates
        .map((candidate) => (candidate, annotate(candidate)))
        .toList();
    final visible = annotated
        .where(
          (entry) =>
              !excludedProviders.contains(resourceProviderKey(entry.$1)) &&
              matchesResourceSelection(
                entry.$2,
                quality: quality,
                group: group,
                includeUnknown: includeUnknown,
              ),
        )
        .toList();
    final groups = {
      ...annotated.expand((entry) => entry.$2.sourceGroups),
      if (group.isNotEmpty) group,
    }.toList()..sort();
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
    final small = Theme.of(context).textTheme.bodySmall;
    return PageScroll(
      children: [
        const SizedBox(height: 10),
        MelonPanel(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titleOf(widget.subject ?? {}),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                episode == null ? '查找字幕组与视频版本' : '下载将关联到第 ${episode['sort']} 话',
                style: small,
              ),
              const SizedBox(height: 17),
              LayoutBuilder(
                builder: (context, constraints) {
                  final keyword = TextField(
                    key: const PageStorageKey('resource-query'),
                    controller: widget.resourceSearch,
                    focusNode: queryFocus,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => search(),
                    decoration: const InputDecoration(
                      labelText: '资源关键词',
                      prefixIcon: Icon(Icons.search, size: 19),
                    ),
                  );
                  final episodeField = TextField(
                    key: const PageStorageKey('resource-episode'),
                    controller: episodeQuery,
                    focusNode: episodeFocus,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => search(),
                    decoration: const InputDecoration(
                      labelText: '集数关键词',
                      hintText: '01 / S01E01',
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
                        const SizedBox(height: 12),
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
                      SizedBox(width: 145, child: episodeField),
                      const SizedBox(width: 10),
                      button,
                    ],
                  );
                },
              ),
              const SizedBox(height: 7),
              Wrap(
                spacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton.icon(
                    key: const ValueKey('resource-aliases-toggle'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 0),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    onPressed: () =>
                        changeForm(() => aliasesExpanded = !aliasesExpanded),
                    icon: AnimatedRotation(
                      turns: aliasesExpanded ? .25 : 0,
                      duration: motionDuration(context, 150),
                      child: const Icon(Icons.chevron_right, size: 17),
                    ),
                    label: Text(
                      multipleNames
                          ? '别名搜索 · ${names.where((name) => !excluded.contains(name)).length} 个名称'
                          : '别名搜索 · 已关闭',
                    ),
                  ),
                  Text('集数留空可查找合集', style: small?.copyWith(fontSize: 11)),
                ],
              ),
              AnimatedSize(
                duration: motionDuration(context),
                alignment: Alignment.topLeft,
                curve: Curves.easeOutCubic,
                child: aliasesExpanded
                    ? Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Wrap(
                          spacing: 7,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            FilterChip(
                              label: const Text('多个名称一起搜'),
                              selected: multipleNames,
                              onSelected: (value) =>
                                  changeForm(() => multipleNames = value),
                            ),
                            if (multipleNames)
                              for (final name in names.where(
                                (name) =>
                                    name != widget.resourceSearch.text.trim(),
                              ))
                                FilterChip(
                                  label: Text(name),
                                  selected: !excluded.contains(name),
                                  onSelected: (value) => changeForm(
                                    () => value
                                        ? excluded.remove(name)
                                        : excluded.add(name),
                                  ),
                                ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              if (widget.providers.isNotEmpty || searchBusy) ...[
                const SizedBox(height: 8),
                ResourceProgress(
                  providers: widget.providers,
                  busy: searchBusy,
                  excludedProviders: excludedProviders,
                  onProviderSelected: (id, selected) => changeForm(
                    () => selected
                        ? excludedProviders.remove(id)
                        : excludedProviders.add(id),
                  ),
                ),
              ],
            ],
          ),
        ),
        SectionTitle(
          title: '资源结果',
          subtitle: '${visible.length} / ${widget.candidates.length} 条',
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('画质', style: small),
              SizedBox(
                width: 278,
                child: MelonSegmentedControl<String>(
                  options: const {
                    'all': '全部',
                    '1080p': '1080p',
                    '720p': '720p',
                    '4K': '4K',
                  },
                  value: quality,
                  semanticLabel: '按标题标注的画质筛选',
                  onChanged: (value) => changeForm(() => quality = value),
                ),
              ),
              MelonChoiceMenu<String>(
                options: {'': '全部来源分组', for (final name in groups) name: name},
                value: group,
                icon: Icons.groups_outlined,
                label: group.isEmpty ? '来源分组' : group,
                tooltip: '资源站标注的发布分组；标题中的联合署名单独展示',
                onSelected: (value) => changeForm(() => group = value),
              ),
              Tooltip(
                message: '筛选时保留未标明画质或来源分组的资源',
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () =>
                      changeForm(() => includeUnknown = !includeUnknown),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ExcludeFocus(
                        child: Switch(
                          value: includeUnknown,
                          onChanged: (value) =>
                              changeForm(() => includeUnknown = value),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: Text('含未确认', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ),
              ),
              if (quality != 'all' ||
                  group.isNotEmpty ||
                  includeUnknown ||
                  excludedProviders.isNotEmpty)
                TextButton(onPressed: clearFilters, child: const Text('清除')),
            ],
          ),
        ),
        if (visible.isNotEmpty) ...[
          LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth < 760
                ? const SizedBox.shrink()
                : Material(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.vertical(
                      top: panelBorderRadius.topLeft,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 13, 16, 11),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '资源 / 标题标注',
                              style: small?.copyWith(fontSize: 11),
                            ),
                          ),
                          const SizedBox(width: 18),
                          SizedBox(
                            width: 106,
                            child: Text(
                              '来源分组',
                              style: small?.copyWith(fontSize: 11),
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 72,
                            child: Text(
                              '大小',
                              style: small?.copyWith(fontSize: 11),
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 80,
                            child: Text(
                              '发布',
                              style: small?.copyWith(fontSize: 11),
                            ),
                          ),
                          const SizedBox(width: 100),
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
                  top: i == 0 && constraints.maxWidth < 760
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
                        phase:
                            downloadPhases['${visible[i].$1['candidateId']}'] ??
                            ResourceDownloadPhase.idle,
                        error:
                            downloadErrors['${visible[i].$1['candidateId']}'],
                        onDownload: () => download(visible[i].$1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
        if (visible.isEmpty &&
            (allProvidersExcluded ||
                !searchBusy ||
                widget.candidates.isNotEmpty))
          EmptyState(
            text: allProvidersExcluded
                ? '已取消选择全部资源站'
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
                ? '显示全部来源'
                : widget.candidates.isNotEmpty
                ? '清除筛选'
                : !providersFailed && episodeQuery.text.isNotEmpty
                ? '清空集数并搜索'
                : '重新搜索',
          ),
      ],
    );
  }
}

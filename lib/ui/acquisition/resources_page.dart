import 'package:flutter/material.dart';

import '../../data/json.dart';
import '../../data/resource_metadata.dart';
import '../core/page_widgets.dart';
import '../core/subject_posters.dart';
import '../core/theme.dart';
import 'resource_widgets.dart';

class ResourcesPage extends StatefulWidget {
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
  final titleFilter = TextEditingController(),
      groupFilter = TextEditingController();
  final excluded = <String>{};
  final downloadPhases = <String, ResourceDownloadPhase>{};
  final downloadErrors = <String, String>{};
  bool multipleNames = true, searching = false;
  PageStorageBucket? storage;
  bool formRestored = false, restoringForm = false;
  bool get searchBusy => widget.busy || searching;

  String get storageId =>
      'resource-form:${widget.subject?['subjectId']}:${widget.resourceEpisode}';

  @override
  void initState() {
    super.initState();
    for (final controller in [episodeQuery, titleFilter, groupFilter]) {
      controller.addListener(saveForm);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    storage = PageStorage.maybeOf(context);
    if (formRestored) return;
    formRestored = true;
    final saved = storage?.readState(
      context,
      identifier: storageId,
    ) as Map<String, dynamic>?;
    if (saved == null) return;
    restoringForm = true;
    episodeQuery.text = saved['episode'] as String;
    titleFilter.text = saved['title'] as String;
    groupFilter.text = saved['group'] as String;
    multipleNames = saved['multipleNames'] as bool;
    excluded.addAll((saved['excluded'] as List).cast<String>());
    restoringForm = false;
  }

  void saveForm() {
    if (restoringForm) return;
    storage?.writeState(context, {
      'episode': episodeQuery.text,
      'title': titleFilter.text,
      'group': groupFilter.text,
      'multipleNames': multipleNames,
      'excluded': excluded.toList(),
    }, identifier: storageId);
  }

  @override
  void dispose() {
    episodeQuery.dispose();
    titleFilter.dispose();
    groupFilter.dispose();
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

  void clearFilters() => setState(() {
    titleFilter.clear();
    groupFilter.clear();
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

  @override
  Widget build(BuildContext context) {
    final names = resourceNames(widget.subject ?? {});
    final visible = widget.candidates
        .where((e) => matchesResource(e, titleFilter.text, groupFilter.text))
        .toList();
    final groups =
        widget.candidates
            .expand((e) => (e['releaseGroups'] as List? ?? []).cast<String>())
            .toSet()
            .toList()
          ..sort();
    final episode = objects(widget.subject?['episodes'])
        .where((e) => e['episodeId'] == widget.resourceEpisode)
        .firstOrNull;
    final providersFailed =
        widget.providers.isNotEmpty &&
        widget.providers.every((e) => e['status'] == 'error');
    return PageScroll(
      children: [
        const SizedBox(height: 10),
        MelonPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 54,
                    height: 72,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SubjectCover(
                        url: widget.subject?['coverUrl'],
                        title: titleOf(widget.subject ?? {}),
                        id: number(widget.subject?['subjectId']).toInt(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titleOf(widget.subject ?? {}),
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          episode == null
                              ? '选择喜欢的字幕组与视频版本'
                              : '下载将关联到第 ${episode['sort']} 话',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      key: const PageStorageKey('resource-query'),
                      controller: widget.resourceSearch,
                      onSubmitted: (_) => search(),
                      decoration: const InputDecoration(
                        labelText: '资源关键词',
                        prefixIcon: Icon(Icons.search, size: 19),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      key: const PageStorageKey('resource-episode'),
                      controller: episodeQuery,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => search(),
                      decoration: const InputDecoration(
                        labelText: '集数关键词',
                        hintText: '01 / S01E01',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Tooltip(
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
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilterChip(
                    label: const Text('多个名称一起搜'),
                    selected: multipleNames,
                    onSelected: (value) {
                      setState(() => multipleNames = value);
                      saveForm();
                    },
                  ),
                  if (multipleNames)
                    for (final name in names.where(
                      (e) => e != widget.resourceSearch.text.trim(),
                    ))
                      FilterChip(
                        label: Text(name),
                        selected: !excluded.contains(name),
                        onSelected: (value) => setState(() {
                          if (value) {
                            excluded.remove(name);
                          } else {
                            excluded.add(name);
                          }
                          saveForm();
                        }),
                      ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '集数关键词交给资源站搜索；留空可查看合集及其他命名。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (widget.providers.isNotEmpty || searchBusy) ...[
                const SizedBox(height: 16),
                ResourceProgress(providers: widget.providers, busy: searchBusy),
              ],
            ],
          ),
        ),
        SectionTitle(
          title: '资源结果',
          subtitle: '${visible.length} / ${widget.candidates.length} 条',
          icon: Icons.download_outlined,
          color: mint,
        ),
        MelonPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const PageStorageKey('resource-title-filter'),
                      controller: titleFilter,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: '筛选结果标题',
                        hintText: '画质、语言、格式…',
                        prefixIcon: Icon(Icons.filter_list, size: 19),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      key: const PageStorageKey('resource-group-filter'),
                      controller: groupFilter,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: '字幕组 / 联合发布',
                        hintText: '输入字幕组名称',
                        prefixIcon: Icon(Icons.groups_outlined, size: 19),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(onPressed: clearFilters, child: const Text('清除')),
                ],
              ),
              if (groups.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final group in groups)
                      FilterChip(
                        label: Text(group),
                        selected: groupFilter.text == group,
                        onSelected: (value) => setState(
                          () => groupFilter.text = value ? group : '',
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        for (final candidate in visible)
          ResourceArrival(
            key: ValueKey(candidate['candidateId']),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: MelonPanel(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 17,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.video_file_outlined,
                      color: mint,
                      size: 24,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${candidate['title']}',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            resourceDetails(candidate),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    ResourceDownloadButton(
                      phase:
                          downloadPhases['${candidate['candidateId']}'] ??
                          ResourceDownloadPhase.idle,
                      error: downloadErrors['${candidate['candidateId']}'],
                      onPressed: () => download(candidate),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (visible.isEmpty && (!searchBusy || widget.candidates.isNotEmpty))
          EmptyState(
            text: widget.candidates.isNotEmpty
                ? '没有符合筛选条件的资源'
                : providersFailed
                ? '资源站暂时无法连接'
                : '没有找到资源，试试其他名称或清空集数关键词',
            action: widget.candidates.isNotEmpty
                ? clearFilters
                : () {
                    if (!providersFailed) episodeQuery.clear();
                    search();
                  },
            actionLabel: widget.candidates.isNotEmpty
                ? '清除筛选'
                : !providersFailed && episodeQuery.text.isNotEmpty
                ? '清空集数并搜索'
                : '重新搜索',
          ),
      ],
    );
  }
}

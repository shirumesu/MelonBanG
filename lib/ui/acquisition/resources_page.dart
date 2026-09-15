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
  final void Function(List<String>, String) onSearch;
  final ValueChanged<Json> onDownload;
  @override
  State<ResourcesPage> createState() => _ResourcesPageState();
}

class _ResourcesPageState extends State<ResourcesPage> {
  final episodeQuery = TextEditingController();
  final titleFilter = TextEditingController(),
      groupFilter = TextEditingController();
  final excluded = <String>{};
  bool multipleNames = true;
  @override
  void dispose() {
    episodeQuery.dispose();
    titleFilter.dispose();
    groupFilter.dispose();
    super.dispose();
  }

  void search() => widget.onSearch(
    multipleNames
        ? resourceNames(widget.subject ?? {})
              .where((e) => !excluded.contains(e))
              .toList()
        : [],
    episodeQuery.text,
  );

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
                      controller: episodeQuery,
                      onSubmitted: (_) => search(),
                      decoration: const InputDecoration(
                        labelText: '集数关键词',
                        hintText: '01 / S01E01',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(onPressed: search, child: const Text('搜索')),
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
                    onSelected: (value) =>
                        setState(() => multipleNames = value),
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
                        }),
                      ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '集数关键词交给资源站搜索；留空可查看合集及其他命名。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (widget.providers.isNotEmpty || widget.busy) ...[
                const SizedBox(height: 16),
                ResourceProgress(
                  providers: widget.providers,
                  busy: widget.busy,
                ),
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
                  TextButton(
                    onPressed: () => setState(() {
                      titleFilter.clear();
                      groupFilter.clear();
                    }),
                    child: const Text('清除'),
                  ),
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
                    IconButton(
                      tooltip: '下载',
                      onPressed: () => widget.onDownload(candidate),
                      icon: const Icon(Icons.download_outlined, color: mint),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (visible.isEmpty && (!widget.busy || widget.candidates.isNotEmpty))
          EmptyState(
            text: widget.candidates.isEmpty
                ? '没有找到资源，试试其他名称或清空集数关键词'
                : '没有符合筛选条件的资源，试试清除筛选',
          ),
      ],
    );
  }
}

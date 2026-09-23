import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/json.dart';
import '../core/page_widgets.dart';
import '../core/selection_controls.dart';
import '../core/subject_posters.dart';
import '../core/theme.dart';
import 'collection_labels.dart';

class SubjectPage extends StatefulWidget {
  const SubjectPage({
    super.key,
    required this.subject,
    required this.onUpdateTracking,
    required this.onFindResources,
    required this.onOpenEpisode,
    required this.onPlayEpisode,
    required this.onOpenSubject,
    this.onSaveTracking,
    this.resume,
    this.cachedEpisodeIds,
    this.loading = false,
  });
  final Json? subject;
  final bool loading;
  final Json? resume;
  final Set<int>? cachedEpisodeIds;
  final ValueChanged<Json> onUpdateTracking;
  final Future<void> Function(Json)? onSaveTracking;
  final ValueChanged<Json?> onFindResources;
  final ValueChanged<Json> onOpenEpisode, onPlayEpisode, onOpenSubject;
  @override
  State<SubjectPage> createState() => _SubjectPageState();
}

class _SubjectPageState extends State<SubjectPage> {
  late final current = ValueNotifier<Json?>(widget.subject);
  String? _selectedStatus, _undoStatus, _collectionFeedback, _collectionError;
  bool _savingCollection = false;
  Timer? _feedbackTimer;
  final _savingEpisodes = <int>{};
  final _episodeErrors = <int, String>{};

  String? get _collectionStatus =>
      _selectedStatus ??
      object(widget.subject?['collection'])['status'] as String?;

  @override
  void didUpdateWidget(covariant SubjectPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.subject?['subjectId'] != widget.subject?['subjectId']) {
      _feedbackTimer?.cancel();
      _selectedStatus = _undoStatus = _collectionFeedback = _collectionError =
          null;
      _savingCollection = false;
      _savingEpisodes.clear();
      _episodeErrors.clear();
    } else if (!_savingCollection &&
        object(oldWidget.subject?['collection'])['status'] !=
            object(widget.subject?['collection'])['status']) {
      _selectedStatus = null;
    }
    // The episode picker is a separate route and follows refreshed chapter data.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) current.value = widget.subject;
    });
  }

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    current.dispose();
    super.dispose();
  }

  Future<void> _save(Json mutation) async {
    if (widget.onSaveTracking case final save?) {
      await save(mutation);
    } else {
      widget.onUpdateTracking(mutation);
    }
  }

  Future<void> _saveCollection(String status, {bool undo = false}) async {
    if (_savingCollection || status == _collectionStatus) return;
    final subjectId = widget.subject?['subjectId'];
    final previous = _collectionStatus;
    _feedbackTimer?.cancel();
    setState(() {
      _selectedStatus = status;
      _savingCollection = true;
      _collectionError = null;
      _collectionFeedback = '正在保存…';
      _undoStatus = null;
    });
    try {
      await _save({
        'kind': 'subjectCollection',
        'subjectId': subjectId,
        'status': status,
      });
      if (!mounted || widget.subject?['subjectId'] != subjectId) return;
      setState(() {
        _savingCollection = false;
        _undoStatus = undo ? null : previous;
        _collectionFeedback = undo
            ? '已撤销'
            : previous == null
            ? '已加入收藏 · ${collectionLabels[status]}'
            : '已保存 · ${collectionLabels[status]}';
      });
      _feedbackTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) {
          setState(() {
            _collectionFeedback = null;
            _undoStatus = null;
          });
        }
      });
    } catch (error) {
      if (!mounted || widget.subject?['subjectId'] != subjectId) return;
      setState(() {
        _selectedStatus = previous;
        _savingCollection = false;
        _collectionFeedback = null;
        _collectionError = '保存失败：$error';
      });
    }
  }

  Future<void> _toggleEpisode(Json episode) async {
    final id = number(episode['episodeId']).toInt();
    if (_savingEpisodes.contains(id)) return;
    final subjectId = widget.subject?['subjectId'];
    setState(() {
      _savingEpisodes.add(id);
      _episodeErrors.remove(id);
    });
    _refreshPicker();
    try {
      await _save({
        'kind': 'episodeCollection',
        'subjectId': subjectId,
        'episodeId': id,
        'status': episode['status'] == 'watched' ? 'unwatched' : 'watched',
      });
    } catch (error) {
      if (mounted && widget.subject?['subjectId'] == subjectId) {
        _episodeErrors[id] = '保存失败：$error';
      }
    } finally {
      if (mounted && widget.subject?['subjectId'] == subjectId) {
        setState(() => _savingEpisodes.remove(id));
        _refreshPicker();
      }
    }
  }

  void _refreshPicker() {
    current.value = widget.subject == null ? null : {...widget.subject!};
  }

  Future<void> _openLink(Uri url) async {
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw StateError('无法打开链接');
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('打开失败：$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.subject;
    if (item == null) return const Center(child: CircularProgressIndicator());
    final episodes = objects(item['episodes']);
    final watched = episodes.where((e) => e['status'] == 'watched').length;
    final next = _nextEpisode(episodes);
    final nextIndex = next == null ? 0 : episodes.indexOf(next);
    final start = (nextIndex - 1).clamp(0, episodes.length);
    final nearby = episodes.skip(start).take(3).toList();
    final playLabel = widget.loading
        ? '加载剧集…'
        : next == null
        ? '暂无剧集'
        : _available(next) == false
        ? '查找 EP${next['sort']} 资源'
        : '${_isResume(next)
              ? '继续播放'
              : watched == episodes.length
              ? '重看'
              : '播放'} EP${next['sort']}';
    return PageScroll(
      children: [
        const SizedBox(height: 10),
        MelonPanel(
          padding: const EdgeInsets.all(22),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final cover = SizedBox(
                width: constraints.maxWidth < 580 ? 112 : 158,
                child: AspectRatio(
                  aspectRatio: .75,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: posterBorderRadius,
                      boxShadow: posterShadows(context),
                    ),
                    child: ClipRRect(
                      borderRadius: posterBorderRadius,
                      child: SubjectCover(
                        url: item['coverUrl'],
                        title: titleOf(item),
                        id: number(item['subjectId']).toInt(),
                      ),
                    ),
                  ),
                ),
              );
              final info = _mainInfo(item, episodes, watched, next, playLabel);
              return constraints.maxWidth < 580
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [cover, const SizedBox(height: 18), info],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        cover,
                        const SizedBox(width: 26),
                        Expanded(child: info),
                      ],
                    );
            },
          ),
        ),
        const SizedBox(height: 18),
        MelonPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '剧集',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: episodes.isEmpty ? null : _episodes,
                    icon: const Icon(Icons.grid_view_rounded, size: 16),
                    label: Text(
                      widget.loading ? '加载剧集…' : '全部 ${episodes.length} 话',
                    ),
                  ),
                ],
              ),
              if (widget.loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Text('正在加载剧集…'),
                )
              else if (nearby.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Text('暂无剧集信息'),
                )
              else
                for (final episode in nearby)
                  _episodeRow(
                    episode,
                    episode['episodeId'] == next?['episodeId'],
                  ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        MelonPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('简介', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              SelectableText(
                key: const PageStorageKey('subject-summary'),
                '${item['summary'] ?? (widget.loading ? '正在加载简介…' : '暂无简介')}',
                style: const TextStyle(fontSize: 13, height: 1.8),
              ),
              if (objects(item['characters']).isNotEmpty) ...[
                const Divider(height: 32),
                _people(item, characters: true),
              ],
              if (objects(item['staff']).isNotEmpty) ...[
                const Divider(height: 32),
                _people(item, characters: false),
              ],
            ],
          ),
        ),
        if (objects(item['infoBox']).isNotEmpty ||
            object(item['collectionStats']).isNotEmpty) ...[
          const SizedBox(height: 18),
          MelonPanel(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: ExpansionTile(
              key: PageStorageKey('subject-extra:${item['subjectId']}'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 14),
              shape: const Border(),
              collapsedShape: const Border(),
              title: const Text(
                '作品资料与收藏统计',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              children: [
                if (object(item['collectionStats']).isNotEmpty) ...[
                  _stats(context, object(item['collectionStats'])),
                  const SizedBox(height: 16),
                ],
                for (final row in objects(item['infoBox']))
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: SelectableText(
                        key: PageStorageKey(
                          'subject-info:${item['subjectId']}:${row['key']}',
                        ),
                        '${row['key']}：${row['value']}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (objects(item['relatedSubjects']).isNotEmpty) ...[
          const SectionTitle(title: '关联作品', icon: Icons.movie_filter_outlined),
          SubjectPosters(
            onOpen: widget.onOpenSubject,
            items: objects(item['relatedSubjects']),
            horizontal: true,
          ),
        ],
      ],
    );
  }

  Widget _mainInfo(
    Json item,
    List<Json> episodes,
    int watched,
    Json? next,
    String playLabel,
  ) {
    final date = DateTime.tryParse('${item['airDate']}');
    const seasons = ['WINTER', 'SPRING', 'SUMMER', 'AUTUMN'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                titleOf(item),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            IconButton(
              tooltip: '在 Bangumi 打开',
              onPressed: () => _openLink(
                Uri.parse('https://bgm.tv/subject/${item['subjectId']}'),
              ),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
            ),
          ],
        ),
        if ('${item['name'] ?? ''}'.isNotEmpty &&
            item['name'] != titleOf(item)) ...[
          const SizedBox(height: 5),
          Text('${item['name']}', style: Theme.of(context).textTheme.bodySmall),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            if (date != null) ...[
              MelonBadge('${date.year}', color: coral),
              MelonBadge(seasons[(date.month - 1) ~/ 3], color: coral),
            ] else if (item['airDate'] != null)
              MelonBadge('${item['airDate']}', color: coral),
            MelonBadge('${item['platform'] ?? '动画'}', color: sky),
            for (final tag in objects(item['tags']).take(3))
              MelonBadge('${tag['name']}', color: grape),
            if (number(item['score']) > 0)
              MelonBadge('★ ${scoreLabel(item['score'])}', color: gold),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          widget.loading
              ? '正在加载番剧详情…'
              : '已看 $watched 话 / 预定全 ${item['episodeTotal'] ?? episodes.length} 话',
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        if (item['rank'] != null || item['ratingCount'] != null) ...[
          const SizedBox(height: 6),
          Text(
            [
              if (item['rank'] != null) '#${item['rank']} Bangumi',
              if (item['ratingCount'] != null) '${item['ratingCount']} 人评分',
            ].join(' · '),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: next == null || widget.loading
                  ? null
                  : () => _openEpisode(next),
              icon: Icon(
                next != null && _available(next) == false
                    ? Icons.download_outlined
                    : Icons.play_arrow_rounded,
                size: 19,
              ),
              label: Text(playLabel),
            ),
            OutlinedButton.icon(
              onPressed: episodes.isEmpty ? null : _episodes,
              icon: const Icon(Icons.grid_view_rounded, size: 17),
              label: const Text('选集'),
            ),
            OutlinedButton.icon(
              onPressed: () => widget.onFindResources(null),
              icon: const Icon(Icons.download_outlined, size: 18),
              label: const Text('查找资源'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        MelonSegmentedControl<String>(
          options: collectionLabels,
          value: _collectionStatus,
          onChanged: _savingCollection ? null : _saveCollection,
          allowDrag: true,
          semanticLabel: '收藏状态',
        ),
        const SizedBox(height: 4),
        Semantics(
          liveRegion: true,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 30),
            child: _collectionError != null
                ? Text(
                    _collectionError!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  )
                : Row(
                    children: [
                      if (_savingCollection) ...[
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        ),
                        const SizedBox(width: 7),
                      ],
                      Flexible(
                        child: Text(
                          _collectionFeedback ?? '',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      if (_undoStatus != null)
                        TextButton(
                          onPressed: () =>
                              _saveCollection(_undoStatus!, undo: true),
                          child: const Text('撤销'),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _episodeRow(Json episode, bool next) {
    final watched = episode['status'] == 'watched';
    final available = _available(episode);
    final progress = _isResume(episode)
        ? '续播 ${_timestamp(number(widget.resume?['positionSeconds']))}'
        : watched
        ? '已看'
        : next
        ? '下一话 · 未看'
        : '未看';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: next
            ? Theme.of(context).colorScheme.primaryContainer
                  .withValues(alpha: .45)
            : Colors.transparent,
        borderRadius: controlBorderRadius,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
          leading: Text(
            'EP${episode['sort']}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: next ? Theme.of(context).colorScheme.primary : null,
            ),
          ),
          title: Text(
            titleOf(episode),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          subtitle: Text(
            '$progress${available == null
                ? ''
                : available
                ? ' · 已缓存'
                : ' · 未缓存'}',
            style: const TextStyle(fontSize: 11),
          ),
          trailing: IconButton.filledTonal(
            tooltip:
                '${available == false ? '查找资源' : '播放'} EP${episode['sort']}',
            onPressed: widget.loading ? null : () => _openEpisode(episode),
            icon: Icon(
              available == false
                  ? Icons.download_outlined
                  : Icons.play_arrow_rounded,
              size: 19,
            ),
          ),
          onTap: () =>
              _episodes(episodeId: number(episode['episodeId']).toInt()),
        ),
      ),
    );
  }

  Json? _nextEpisode(List<Json> episodes) =>
      episodes.where(_isResume).firstOrNull ??
      episodes.where((episode) => episode['status'] != 'watched').firstOrNull ??
      episodes.firstOrNull;

  bool _isResume(Json episode) =>
      widget.resume?['subjectId'] == widget.subject?['subjectId'] &&
      widget.resume?['episodeId'] == episode['episodeId'] &&
      widget.resume?['completed'] != true &&
      number(widget.resume?['positionSeconds']) > 0;

  bool? _available(Json episode) =>
      widget.cachedEpisodeIds?.contains(number(episode['episodeId']).toInt());

  void _openEpisode(Json episode) {
    if (_available(episode) == false) {
      widget.onFindResources(episode);
    } else {
      widget.onPlayEpisode(episode);
    }
  }

  String _timestamp(double seconds) {
    final value = seconds.toInt();
    return '${value ~/ 60}:${(value % 60).toString().padLeft(2, '0')}';
  }

  List<Json> _peopleList(Json item, bool characters) {
    final values = objects(item[characters ? 'characters' : 'staff']);
    if (characters) {
      return [
        ...values.where((p) => p['role'] == '主角'),
        ...values.where((p) => p['role'] != '主角'),
      ];
    }
    const roles = ['原作', '导演', '系列构成', '人物设定', '音乐', '动画制作', '总作画监督', '脚本'];
    final combined = <String, Json>{};
    for (final person in values) {
      final key = '${person['personId'] ?? person['id'] ?? titleOf(person)}';
      final old = combined[key];
      final role = '${person['role'] ?? person['relation'] ?? ''}';
      if (old == null) {
        combined[key] = {
          ...person,
          'roles': <String>[if (role.isNotEmpty) role],
        };
      } else {
        final positions = old['roles'] as List<String>;
        if (role.isNotEmpty && !positions.contains(role)) positions.add(role);
        if (_image(old) == null && _image(person) != null) {
          old['imageUrl'] = _image(person);
        }
      }
    }
    int priority(String role) =>
        roles.contains(role) ? roles.indexOf(role) : roles.length;
    final people = combined.values.toList();
    for (final person in people) {
      final positions = person['roles'] as List<String>;
      positions.sort((a, b) => priority(a).compareTo(priority(b)));
      person['role'] = positions.join(' · ');
    }
    people.sort((a, b) {
      final aRoles = a['roles'] as List<String>,
          bRoles = b['roles'] as List<String>;
      return priority(aRoles.firstOrNull ?? '')
          .compareTo(priority(bRoles.firstOrNull ?? ''));
    });
    return people;
  }

  Widget _people(Json item, {required bool characters}) {
    final people = _peopleList(item, characters);
    final heading = characters ? '主要角色与配音' : '制作团队';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                heading,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            if (people.length > 8)
              TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => Dialog(
                    child: SizedBox(
                      width: 660,
                      height: 600,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '$heading · ${people.length} 位',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                ),
                                IconButton(
                                  tooltip: '关闭人物列表',
                                  onPressed: () => Navigator.pop(context),
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Expanded(
                              child: ListView.separated(
                                itemCount: people.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (_, index) => _credit(
                                  people[index],
                                  character: characters,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                child: Text('全部 ${people.length} 位'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = (constraints.maxWidth / (characters ? 250 : 200))
                .floor()
                .clamp(1, 6);
            final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final person in people.take(8))
                  SizedBox(
                    width: width,
                    child: _credit(person, character: characters),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  String? _image(Json person) {
    final images = object(person['images']);
    for (final value in [
      person['imageUrl'],
      person['coverUrl'],
      images['medium'],
      images['common'],
      images['large'],
      images['small'],
      images['grid'],
    ]) {
      if (value is String && value.isNotEmpty) return value;
    }
    return null;
  }

  Widget _avatar(Json person, {bool character = false, double size = 42}) {
    final url = _image(person);
    Widget placeholder(String label) => Tooltip(
      message: label,
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: Center(
          child: Icon(
            character ? Icons.face_outlined : Icons.person_outline_rounded,
            size: size * .5,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
    final image = Semantics(
      label: '${titleOf(person)}${character ? '角色头像' : '人物头像'}',
      image: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(character ? 10 : size / 2),
        child: SizedBox(
          width: character ? 72 : size,
          height: character ? 108 : size,
          child: url == null
              ? placeholder('暂无头像')
              : Image.network(
                  url,
                  fit: character ? BoxFit.contain : BoxFit.cover,
                  alignment: character ? Alignment.topCenter : Alignment.center,
                  errorBuilder: (_, _, _) => placeholder('头像加载失败'),
                ),
        ),
      ),
    );
    if (!character || url == null) return image;
    return Tooltip(
      message: '查看${titleOf(person)}完整立绘',
      child: InkWell(
        borderRadius: controlBorderRadius,
        onTap: () => showDialog<void>(
          context: context,
          builder: (context) => Dialog(
            child: SizedBox(
              width: 520,
              height: 620,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            titleOf(person),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          tooltip: '关闭图片',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: InteractiveViewer(
                        child: Image.network(
                          url,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) =>
                              const Center(child: Text('图片加载失败')),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        child: image,
      ),
    );
  }

  Widget _credit(Json person, {required bool character}) {
    final actors = objects(person['actors']);
    final id = number(
      person[character ? 'characterId' : 'personId'] ?? person['id'],
    ).toInt();
    final role = '${person['role'] ?? person['relation'] ?? ''}';
    final url = id > 0
        ? Uri.parse('https://bgm.tv/${character ? 'character' : 'person'}/$id')
        : Uri.parse(
            'https://bgm.tv/subject/${widget.subject?['subjectId']}/${character ? 'characters' : 'persons'}',
          );
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: controlBorderRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openLink(url),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _avatar(person, character: character),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titleOf(person),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          role.isEmpty
                              ? character
                                    ? '角色'
                                    : '制作人员'
                              : role,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (character && actors.isNotEmpty) ...[
                const SizedBox(height: 10),
                for (final actor in actors)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        _avatar(actor, size: 24),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'CV ${titleOf(actor)}',
                            style: Theme.of(context).textTheme.bodySmall,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ] else if (character &&
                  '${person['actorName'] ?? ''}'.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'CV ${person['actorName']}',
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _stats(BuildContext context, Json stats) {
    final total = collectionLabels.keys.fold<double>(
      0,
      (sum, key) => sum + number(stats[key]),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (total > 0)
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 6,
              child: Row(
                children: [
                  for (final key in collectionLabels.keys)
                    if (number(stats[key]) > 0)
                      Expanded(
                        flex: (number(stats[key]) * 1000).round(),
                        child: ColoredBox(
                          color: collectionColor(key),
                          child: const SizedBox.expand(),
                        ),
                      ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 14,
          runSpacing: 5,
          children: [
            for (final entry in collectionLabels.entries)
              Text(
                '${number(stats[entry.key]).toInt()} ${entry.value}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _episodes({int? episodeId}) async {
    int? selectedId =
        episodeId ??
        _nextEpisode(objects(widget.subject?['episodes']))?['episodeId']
            as int?;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: SizedBox(
          width: 720,
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: StatefulBuilder(
              builder: (context, updateDialog) => ValueListenableBuilder<Json?>(
                valueListenable: current,
                builder: (context, item, _) {
                  final episodes = objects(item?['episodes']);
                  final selected =
                      episodes
                          .where((e) => e['episodeId'] == selectedId)
                          .firstOrNull ??
                      _nextEpisode(episodes);
                  final id = number(selected?['episodeId']).toInt();
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '选集 · ${titleOf(item ?? {})}',
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: '关闭选集',
                            onPressed: () => Navigator.pop(dialogContext),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Flexible(
                        child: SingleChildScrollView(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final episode in episodes)
                                Tooltip(
                                  message:
                                      'EP${episode['sort']} · ${titleOf(episode)} · ${episode['status'] == 'watched' ? '已看' : '未看'}${_available(episode) == null
                                          ? ''
                                          : _available(episode)!
                                          ? ' · 已缓存'
                                          : ' · 未缓存'}',
                                  child: SizedBox(
                                    width: 58,
                                    child: OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 10,
                                        ),
                                        backgroundColor:
                                            episode['episodeId'] ==
                                                selected?['episodeId']
                                            ? Theme.of(context)
                                                  .colorScheme
                                                  .primaryContainer
                                            : null,
                                      ),
                                      onPressed: () => updateDialog(
                                        () => selectedId = number(
                                          episode['episodeId'],
                                        ).toInt(),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text('${episode['sort']}'),
                                          if (episode['status'] ==
                                              'watched') ...[
                                            const SizedBox(width: 3),
                                            const Icon(Icons.check, size: 12),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (selected != null) ...[
                        const Divider(height: 28),
                        Text(
                          'EP${selected['sort']} · ${titleOf(selected)}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${selected['status'] == 'watched' ? '已看' : '未看'}${_available(selected) == null
                              ? ''
                              : _available(selected)!
                              ? ' · 已缓存'
                              : ' · 未缓存'}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            IconButton(
                              tooltip: '标记已看 / 未看',
                              icon: _savingEpisodes.contains(id)
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Icon(
                                      selected['status'] == 'watched'
                                          ? Icons.check_circle
                                          : Icons.check_circle_outline,
                                    ),
                              onPressed: _savingEpisodes.contains(id)
                                  ? null
                                  : () => _toggleEpisode(selected),
                            ),
                            IconButton(
                              tooltip: '打开本地文件并关联此话',
                              onPressed: () {
                                Navigator.pop(dialogContext);
                                widget.onOpenEpisode(selected);
                              },
                              icon: const Icon(Icons.folder_open, size: 19),
                            ),
                            IconButton(
                              tooltip: '搜索此话资源',
                              onPressed: () {
                                Navigator.pop(dialogContext);
                                widget.onFindResources(selected);
                              },
                              icon: const Icon(
                                Icons.download_outlined,
                                size: 19,
                              ),
                            ),
                            Tooltip(
                              message: _available(selected) == false
                                  ? '尚未缓存，请先查找资源'
                                  : '播放已缓存视频',
                              child: FilledButton.icon(
                                onPressed: _available(selected) == false
                                    ? null
                                    : () {
                                        Navigator.pop(dialogContext);
                                        widget.onPlayEpisode(selected);
                                      },
                                icon: const Icon(
                                  Icons.play_arrow_rounded,
                                  size: 20,
                                ),
                                label: const Text('播放已缓存视频'),
                              ),
                            ),
                          ],
                        ),
                        if (_episodeErrors[id] case final error?)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              error,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

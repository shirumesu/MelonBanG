import 'dart:io';

import 'package:flutter/material.dart';

import '../../domain/catalog.dart';
import '../../domain/transfer.dart';
import '../../features/acquisition/title_matching.dart';
import '../../features/downloads/downloads_controller.dart';
import '../core/motion.dart';
import '../core/page_widgets.dart';
import '../core/selection_controls.dart';
import '../core/subject_posters.dart';
import '../core/theme.dart';
import 'download_dialogs.dart';
import 'download_labels.dart';
import 'download_task_widgets.dart';

class DownloadsPage extends StatefulWidget {
  const DownloadsPage({
    super.key,
    required this.downloads,
    required this.onExplore,
    required this.onPlay,
    required this.onError,
    required this.subjectOf,
    required this.onPlaySubject,
    required this.hasProgress,
    required this.onOpenSubject,
  });
  final DownloadsController downloads;
  final VoidCallback onExplore;
  final void Function(String, String?) onPlay;
  final ValueChanged<Object> onError;

  /// The subject a group of tasks belongs to, for its title and episodes.
  final Future<Subject> Function(int id) subjectOf;

  /// Watches a subject's cache from where it was left.
  final Future<void> Function(Subject) onPlaySubject;

  /// Whether an episode of the subject was played before.
  final Future<bool> Function(int id) hasProgress;
  final ValueChanged<int> onOpenSubject;
  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  String filter = '全部';
  String statusFilter = '全部状态';
  final expanded = <String>{};
  final subjects = <int, Subject>{};
  final played = <int>{};
  final _requested = <int>{};

  /// While on, tasks and the videos of finished batches can be ticked and
  /// deleted together.
  bool selecting = false;
  final selectedTasks = <String>{};
  final selectedFiles = <(String, String)>{};

  void _loadSubject(int id) {
    if (!_requested.add(id)) return;
    widget.subjectOf(id).then((subject) {
      if (mounted) setState(() => subjects[id] = subject);
    }, onError: (_) {});
    widget.hasProgress(id).then((value) {
      if (value && mounted) setState(() => played.add(id));
    }, onError: (_) {});
  }

  Future<void> _perform(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      widget.onError(e);
    }
  }

  Future<void> _remove(DownloadTask task) async {
    final remove = await showMelonDialog<bool>(
      context: context,
      builder: (_) =>
          RemoveDownloadDialog(message: '将移除下载任务及本机缓存文件：${task.title}'),
    );
    if (remove == true) await _perform(() => widget.downloads.remove(task.id));
  }

  /// Deletes one video of a finished batch.
  Future<void> _removeFile(DownloadTask task, DownloadFile file) async {
    final remove = await showMelonDialog<bool>(
      context: context,
      builder: (_) => RemoveDownloadDialog(
        title: '删除这个视频？',
        message: [
          '将删除本机文件：${file.name}',
          if (task.seeds) '删除后这个合集不再做种，其余视频仍可观看。',
        ].join('\n'),
      ),
    );
    if (remove == true) {
      await _perform(() => widget.downloads.removeFiles(task.id, {file.id}));
    }
  }

  /// Deletes the ticked tasks and videos; a batch whose videos are all
  /// ticked goes as a whole.
  Future<void> _removeSelected(TransferSnapshot snapshot) async {
    final tasks = {for (final task in snapshot.tasks) task.id: task};
    final whole = selectedTasks.where(tasks.containsKey).toSet();
    final files = <String, Set<String>>{};
    for (final (id, fileId) in selectedFiles) {
      if (tasks.containsKey(id)) files.putIfAbsent(id, () => {}).add(fileId);
    }
    for (final id in files.keys.toList()) {
      if (tasks[id]!.videos.every((video) => files[id]!.contains(video.id))) {
        files.remove(id);
        whole.add(id);
      }
    }
    final count = files.values.fold(
      whole.length,
      (sum, ids) => sum + ids.length,
    );
    final remove = await showMelonDialog<bool>(
      context: context,
      builder: (_) => RemoveDownloadDialog(
        title: '删除所选缓存？',
        message: [
          '将删除所选的 $count 项及其本机缓存文件。',
          if (files.keys.any((id) => tasks[id]!.seeds)) '删除合集中的部分视频后，该合集不再做种。',
        ].join('\n'),
      ),
    );
    if (remove != true || !mounted) return;
    setState(_endSelection);
    await _perform(() async {
      for (final id in whole) {
        await widget.downloads.remove(id);
      }
      for (final MapEntry(key: id, value: fileIds) in files.entries) {
        await widget.downloads.removeFiles(id, fileIds);
      }
    });
  }

  void _endSelection() {
    selecting = false;
    selectedTasks.clear();
    selectedFiles.clear();
  }

  /// Ticks or unticks whole tasks; a ticked task's videos need no ticks.
  void _select(Iterable<DownloadTask> tasks, bool value) => setState(() {
    for (final task in tasks) {
      if (value) {
        selectedTasks.add(task.id);
        selectedFiles.removeWhere((file) => file.$1 == task.id);
      } else {
        selectedTasks.remove(task.id);
      }
    }
  });

  Widget _taskCheck(DownloadTask task) => Checkbox(
    value: selectedTasks.contains(task.id),
    onChanged: (value) => _select([task], value!),
  );

  void _toggle(DownloadTask task) =>
      _perform(() => widget.downloads.toggle(task));

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: widget.downloads.snapshot,
    builder: (context, snapshot, _) => _page(context, snapshot),
  );

  Widget _page(BuildContext context, TransferSnapshot snapshot) {
    final tasks = snapshot.tasks;
    final visible = tasks.where((t) {
      final category =
          filter == '全部' || (filter == '已缓存' ? t.complete : !t.complete);
      final status = switch (statusFilter) {
        '已暂停' => t.status == DownloadStatus.paused,
        '失败' => t.status == DownloadStatus.failed,
        '做种中' => t.status == DownloadStatus.seeding,
        _ => true,
      };
      return category && status;
    }).toList();
    final speed = tasks.fold<int>(0, (sum, t) => sum + t.downloadSpeed);
    // A subject's tasks, however they were cached, form one entry.
    final entries = <List<DownloadTask>>[];
    final bySubject = <int, List<DownloadTask>>{};
    for (final task in visible) {
      if (task.subjectId case final id?) {
        if (bySubject[id] case final entry?) {
          entry.add(task);
          continue;
        }
        entries.add(bySubject[id] = [task]);
      } else {
        entries.add([task]);
      }
    }
    bool complete(List<DownloadTask> entry) => entry.every((t) => t.complete);
    final active = entries.where((e) => !complete(e)).toList();
    final cached = entries.where(complete).toList();
    return PageScroll(
      children: [
        SectionTitle(
          title: '缓存',
          trailing: selecting
              ? Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '已选 ${selectedTasks.length + selectedFiles.length} 项',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    TextButton(
                      onPressed: () => setState(_endSelection),
                      child: const Text('取消'),
                    ),
                    FilledButton.icon(
                      onPressed: selectedTasks.isEmpty && selectedFiles.isEmpty
                          ? null
                          : () => _removeSelected(snapshot),
                      icon: const Icon(Icons.delete_outline, size: 17),
                      label: const Text('删除'),
                    ),
                  ],
                )
              : tasks.isEmpty
              ? null
              : TextButton.icon(
                  onPressed: () => setState(() => selecting = true),
                  icon: const Icon(Icons.checklist_rounded, size: 17),
                  label: const Text('批量删除'),
                ),
        ),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 290,
              child: MelonSegmentedControl<String>(
                options: const {'全部': '全部', '进行中': '进行中', '已缓存': '已缓存'},
                value: filter,
                onChanged: (value) => setState(() => filter = value),
              ),
            ),
            MelonChoiceMenu<String>(
              options: const {
                '全部状态': '全部状态',
                '已暂停': '已暂停',
                '失败': '失败',
                '做种中': '做种中',
              },
              value: statusFilter,
              onSelected: (value) => setState(() => statusFilter = value),
            ),
            if (speed > 0)
              Text(
                '↓ ${(speed / 1048576).toStringAsFixed(1)} MiB/s',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 12,
                ),
              ),
          ],
        ),
        for (final group in [('进行中', active), ('已缓存', cached)]) ...[
          if (group.$2.isNotEmpty) ...[
            if (filter == '全部')
              SectionTitle(title: '${group.$1} ${group.$2.length}')
            else
              const SizedBox(height: Gap.lg),
            PageSliver(
              child: SliverList.builder(
                itemCount: group.$2.length,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _entry(context, group.$2[index]),
                ),
              ),
            ),
          ],
        ],
        if (visible.isEmpty)
          EmptyState(
            text: tasks.isEmpty ? '还没有缓存' : '没有符合条件的任务',
            action: tasks.isEmpty
                ? widget.onExplore
                : () => setState(() {
                    filter = '全部';
                    statusFilter = '全部状态';
                  }),
            actionLabel: tasks.isEmpty ? '去探索' : '清除筛选',
          ),
      ],
    );
  }

  Widget _entry(BuildContext context, List<DownloadTask> tasks) {
    final subjectId = tasks.first.subjectId;
    if (subjectId != null) _loadSubject(subjectId);
    final subject = subjects[subjectId];
    if (tasks.length == 1) return _task(context, tasks.single, subject);
    return _group(context, subject, subjectId!, tasks);
  }

  /// Starts or continues watching an entry: the subject's cache from where
  /// it was left when the videos hold known episodes, else the only video or
  /// a choice of several.
  Widget _watchButton(Subject? subject, List<DownloadTask> tasks) {
    final ready = tasks.where((task) => playBlocked(task) == null).toList();
    final first = ready.firstOrNull;
    final episodic =
        subject != null &&
        ready.any((task) => episodeFiles(subject, task).isNotEmpty);
    final choose = !episodic && first != null && first.videos.length > 1;
    final VoidCallback? onPressed = first == null
        ? null
        : episodic
        ? () => _perform(() => widget.onPlaySubject(subject))
        : choose
        ? () => chooseDownloadVideo(context, first, widget.onPlay)
        : () => widget.onPlay(first.id, first.videos.single.id);
    final resume = subject != null && played.contains(subject.id);
    return Tooltip(
      message: first != null
          ? ''
          : tasks.length == 1
          ? playBlocked(tasks.single)!
          : '还没有可以观看的视频',
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.play_arrow_rounded, size: 19),
        label: Text(
          choose
              ? '选择视频'
              : resume
              ? '继续观看'
              : '开始观看',
        ),
      ),
    );
  }

  /// [tasks] in episode order; tasks of unknown episodes keep their order
  /// at the end.
  List<DownloadTask> _ordered(Subject? subject, List<DownloadTask> tasks) {
    if (subject == null) return tasks;
    final order = {
      for (final (index, episode) in subject.episodes.indexed)
        episode.id: index,
    };
    final indexed = tasks.indexed.toList()
      ..sort((a, b) {
        final byEpisode = (order[a.$2.episodeId] ?? order.length).compareTo(
          order[b.$2.episodeId] ?? order.length,
        );
        return byEpisode != 0 ? byEpisode : a.$1.compareTo(b.$1);
      });
    return [for (final (_, task) in indexed) task];
  }

  /// One subject's tasks: watching continues where it was left, and the
  /// entry expands into a compact row per task.
  Widget _group(
    BuildContext context,
    Subject? subject,
    int subjectId,
    List<DownloadTask> tasks,
  ) {
    final key = 'subject:$subjectId';
    final open = expanded.contains(key);
    final ordered = _ordered(subject, tasks);
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    final done = tasks.where((t) => t.complete).length;
    final failed = tasks.where((t) => t.status == DownloadStatus.failed).length;
    final ongoing = tasks.length - done - failed;
    final speed = tasks.fold<int>(0, (sum, t) => sum + t.downloadSpeed);
    final ticked = tasks.where((t) => selectedTasks.contains(t.id)).length;
    final title = subject?.title ?? ordered.first.title;
    return MelonPanel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            customBorder: CardTheme.of(context).shape,
            onTap: () =>
                setState(() => open ? expanded.remove(key) : expanded.add(key)),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (selecting)
                    Checkbox(
                      tristate: true,
                      value: ticked == tasks.length
                          ? true
                          : ticked == 0
                          ? false
                          : null,
                      onChanged: (_) => _select(tasks, ticked < tasks.length),
                    ),
                  _SubjectCoverLink(
                    url: subject?.coverUrl ?? ordered.first.coverUrl,
                    title: title,
                    id: subjectId,
                    onOpen: () => widget.onOpenSubject(subjectId),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SubjectTitleLink(
                          title: title,
                          onOpen: () => widget.onOpenSubject(subjectId),
                        ),
                        const SizedBox(height: 7),
                        Wrap(
                          spacing: 10,
                          runSpacing: 5,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (done > 0) MelonBadge('已缓存 $done', color: sky),
                            if (ongoing > 0) MelonBadge('进行中 $ongoing'),
                            if (failed > 0)
                              MelonBadge('需要重试 $failed', color: coral),
                            if (speed > 0)
                              Text('↓ ${transferRate(speed)}', style: small),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _watchButton(subject, ordered),
                  IconButton(
                    tooltip: open ? '收起' : '展开剧集',
                    onPressed: () => setState(
                      () => open ? expanded.remove(key) : expanded.add(key),
                    ),
                    icon: ExpandChevron(open: open),
                  ),
                ],
              ),
            ),
          ),
          MotionReveal(
            visible: open,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Divider(height: 1, color: scheme.outlineVariant),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final task in ordered)
                        _episodeRow(context, subject, task),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// A compact row for one task of a group; clicking it shows its details.
  Widget _episodeRow(
    BuildContext context,
    Subject? subject,
    DownloadTask task,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    final episode = switch (task.episodeId) {
      final id? => subject?.episode(id),
      null => null,
    };
    final label = switch (episode) {
      final episode? => episode.label,
      null when task.videos.length > 1 => '合集',
      null => '—',
    };
    final details = expanded.contains(task.id);
    final progress = task.progress.clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: controlBorderRadius,
          onTap: () => setState(
            () => details ? expanded.remove(task.id) : expanded.add(task.id),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 2, 0, 2),
            child: Row(
              children: [
                if (selecting) _taskCheck(task),
                SizedBox(
                  width: 66,
                  child: Text(label, style: const TextStyle(fontSize: 13)),
                ),
                Expanded(
                  child: Text(
                    task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: small,
                  ),
                ),
                const SizedBox(width: 12),
                if (downloadOrigin(task) case final origin?) ...[
                  MelonBadge(origin, color: sky),
                  const SizedBox(width: 6),
                ],
                DownloadStatusBadge(task),
                if (!task.complete && task.cloudProgress == null)
                  SizedBox(
                    width: 44,
                    child: Text(
                      '${(progress * 100).floor()}%',
                      textAlign: TextAlign.end,
                      style: small,
                    ),
                  ),
                const SizedBox(width: 4),
                DownloadToggleButton(task: task, onToggle: _toggle, size: 18),
                DownloadPlayButton(task: task, onPlay: widget.onPlay),
                IconButton(
                  tooltip: '移除任务与缓存',
                  onPressed: () => _remove(task),
                  icon: const Icon(Icons.delete_outline, size: 18),
                ),
              ],
            ),
          ),
        ),
        if (!task.complete)
          Padding(
            padding: const EdgeInsets.fromLTRB(74, 0, 8, 4),
            child: MotionValue(
              value: task.cloudProgress ?? progress,
              builder: (context, value) => LinearProgressIndicator(
                value: value,
                minHeight: 2,
                borderRadius: BorderRadius.circular(99),
                backgroundColor: scheme.surfaceContainerLow,
              ),
            ),
          ),
        if ((task.errorMessage ?? task.persistenceError) case final issue?)
          Padding(
            padding: const EdgeInsets.fromLTRB(74, 0, 8, 6),
            child: Text(
              issue,
              style: TextStyle(color: scheme.error, fontSize: 12),
            ),
          ),
        MotionReveal(
          visible: details,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(74, 4, 8, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _details(context, task, subject),
            ),
          ),
        ),
      ],
    );
  }

  Widget _task(BuildContext context, DownloadTask task, Subject? subject) {
    final id = task.id;
    final scheme = Theme.of(context).colorScheme;
    final details = expanded.contains(id);
    return MelonPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (selecting) _taskCheck(task),
              _SubjectCoverLink(
                url: task.coverUrl,
                title: task.title,
                id: task.subjectId ?? 0,
                onOpen: switch (task.subjectId) {
                  final id? => () => widget.onOpenSubject(id),
                  null => null,
                },
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SubjectTitleLink(
                      title: task.title,
                      onOpen: switch (task.subjectId) {
                        final id? => () => widget.onOpenSubject(id),
                        null => null,
                      },
                    ),
                    const SizedBox(height: 7),
                    DownloadTaskStatus(task: task),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _watchButton(subject, [task]),
              if (task.toggle != null) ...[
                const SizedBox(width: 8),
                DownloadToggleButton(
                  task: task,
                  onToggle: _toggle,
                  labelled: true,
                ),
              ],
              IconButton(
                tooltip: details ? '收起详情' : '详情',
                onPressed: () => setState(
                  () => details ? expanded.remove(id) : expanded.add(id),
                ),
                icon: ExpandChevron(open: details),
              ),
            ],
          ),
          if ((task.errorMessage ?? task.persistenceError) case final issue?)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                issue,
                style: TextStyle(color: scheme.error, fontSize: 12),
              ),
            ),
          MotionReveal(
            visible: details,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(height: 28),
                ..._details(context, task, subject),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Files, transfer counters and actions of [task], shown on request.
  List<Widget> _details(
    BuildContext context,
    DownloadTask task,
    Subject? subject,
  ) {
    final swarm = task.swarm;
    final files = task.files;
    return [
      if (task.videos.length > 1)
        _videos(context, task, subject)
      else if (files.isNotEmpty)
        Text(
          files.length == 1
              ? files.single.name
              : '${files.first.name} 等 ${files.length} 个文件',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      const SizedBox(height: 8),
      _stats(context, [
        '↓ ${transferRate(task.downloadSpeed)}',
        if (task.seeds) ...[
          '↑ ${transferRate(task.uploadSpeed)}',
          '${swarm.peers} 个连接',
          '分享率 ${task.totalBytes > 0 ? (task.uploadedBytes / task.totalBytes).toStringAsFixed(2) : '0.00'}',
        ],
      ]),
      if (task.seeds && !task.complete && swarm.trackers != null) ...[
        const SizedBox(height: 6),
        _stats(context, [
          '发现 ${swarm.knownPeers ?? 0} 个节点',
          'Tracker ${swarm.workingTrackers ?? 0}/${swarm.trackers} 可用',
          (swarm.dhtNodes ?? 0) < 0
              ? 'DHT 已关闭'
              : 'DHT ${swarm.dhtNodes ?? 0} 个节点',
        ]),
        if ((task.status == DownloadStatus.metadata ||
                task.status == DownloadStatus.downloading) &&
            swarm.peers == 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              (swarm.knownPeers ?? 0) > 0
                  ? '已发现节点，正在连接'
                  : (swarm.failedTrackers ?? 0) > 0 &&
                        (swarm.workingTrackers ?? 0) == 0 &&
                        (swarm.dhtNodes ?? 0) <= 0
                  ? '没有找到下载节点，请检查网络是否允许 BT，或换一个资源'
                  : '正在寻找下载节点，做种的人少时会比较慢',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
      if (task.seeds && task.complete) ...[
        const SizedBox(height: 6),
        _stats(context, [
          '已上传 ${(task.uploadedBytes / 1048576).toStringAsFixed(1)} MiB',
          '做种 ${(task.seedSeconds / 60).floor()} 分钟',
        ]),
      ],
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          if (files.isNotEmpty)
            TextButton.icon(
              onPressed: () => _perform(() => widget.downloads.reveal(task)),
              icon: const Icon(Icons.folder_open_outlined, size: 17),
              label: Text(Platform.isMacOS ? '在访达中显示' : '在资源管理器中显示'),
            ),
          TextButton.icon(
            onPressed: () => _remove(task),
            icon: const Icon(Icons.delete_outline, size: 17),
            label: const Text('移除任务与缓存'),
          ),
        ],
      ),
    ];
  }

  /// A batch's videos in episode order, each to watch and, once the batch
  /// is finished, to delete on its own.
  Widget _videos(BuildContext context, DownloadTask task, Subject? subject) {
    final small = Theme.of(context).textTheme.bodySmall;
    final episodes = <String, Episode>{
      if (subject != null)
        for (final MapEntry(key: id, value: file) in episodeFiles(
          subject,
          task,
        ).entries)
          file.id: subject.episode(id)!,
    };
    final videos = [...task.videos]
      ..sort((a, b) {
        final byEpisode = (episodes[a.id]?.sort ?? double.infinity).compareTo(
          episodes[b.id]?.sort ?? double.infinity,
        );
        return byEpisode != 0 ? byEpisode : a.name.compareTo(b.name);
      });
    final blocked = playBlocked(task);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final file in videos)
          Row(
            children: [
              if (selecting && task.complete)
                Checkbox(
                  value:
                      selectedTasks.contains(task.id) ||
                      selectedFiles.contains((task.id, file.id)),
                  onChanged: selectedTasks.contains(task.id)
                      ? null
                      : (value) => setState(
                          () => value!
                              ? selectedFiles.add((task.id, file.id))
                              : selectedFiles.remove((task.id, file.id)),
                        ),
                ),
              SizedBox(
                width: 66,
                child: Text(switch (episodes[file.id]) {
                  final episode? => episode.label,
                  null => '—',
                }, style: const TextStyle(fontSize: 13)),
              ),
              Expanded(
                child: Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: small,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                [
                  '${(file.size / 1048576).toStringAsFixed(1)} MiB',
                  if (file.progress < 1) '${(file.progress * 100).floor()}%',
                ].join('  '),
                style: small,
              ),
              IconButton(
                tooltip: blocked ?? '观看',
                onPressed: blocked != null
                    ? null
                    : () => widget.onPlay(task.id, file.id),
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
              ),
              if (task.complete)
                IconButton(
                  tooltip: '删除这个视频',
                  onPressed: () => _removeFile(task, file),
                  icon: const Icon(Icons.delete_outline, size: 18),
                ),
            ],
          ),
      ],
    );
  }

  Widget _stats(BuildContext context, List<String> values) => Wrap(
    spacing: Gap.lg,
    runSpacing: 4,
    children: [
      for (final value in values)
        Text(value, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

/// A cache entry's cover; with a subject it opens the detail page, showing
/// so on hover inside the cover.
class _SubjectCoverLink extends StatefulWidget {
  const _SubjectCoverLink({
    required this.url,
    required this.title,
    required this.id,
    required this.onOpen,
  });
  final String? url;
  final String title;
  final int id;
  final VoidCallback? onOpen;

  @override
  State<_SubjectCoverLink> createState() => _SubjectCoverLinkState();
}

class _SubjectCoverLinkState extends State<_SubjectCoverLink> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final cover = SizedBox(
      width: 58,
      height: 78,
      child: ClipRRect(
        borderRadius: badgeBorderRadius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            SubjectCover(url: widget.url, title: widget.title, id: widget.id),
            if (widget.onOpen != null)
              AnimatedOpacity(
                opacity: hovered ? 1 : 0,
                duration: motionDuration(context, 150),
                child: const ColoredBox(
                  color: Color(0x66000000),
                  child: Icon(
                    Icons.info_outline_rounded,
                    size: 22,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (widget.onOpen == null) return cover;
    return Tooltip(
      message: '番剧详情',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => hovered = true),
        onExit: (_) => setState(() => hovered = false),
        child: GestureDetector(onTap: widget.onOpen, child: cover),
      ),
    );
  }
}

/// A cache entry's title; with a subject it opens the detail page and is
/// underlined on hover.
class _SubjectTitleLink extends StatefulWidget {
  const _SubjectTitleLink({required this.title, required this.onOpen});
  final String title;
  final VoidCallback? onOpen;

  @override
  State<_SubjectTitleLink> createState() => _SubjectTitleLinkState();
}

class _SubjectTitleLinkState extends State<_SubjectTitleLink> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      widget.title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: hovered ? Theme.of(context).colorScheme.primary : null,
        decoration: hovered ? TextDecoration.underline : null,
      ),
    );
    if (widget.onOpen == null) return text;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: GestureDetector(onTap: widget.onOpen, child: text),
    );
  }
}

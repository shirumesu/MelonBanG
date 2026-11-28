import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/file_manager.dart';
import '../../core/notices.dart';
import '../../domain/catalog.dart';
import '../../domain/transfer.dart';
import '../../features/acquisition/title_matching.dart';
import '../../features/downloads/cache_selection.dart';
import '../../features/downloads/downloads_controller.dart';
import '../../features/subscriptions/subscription_controller.dart';
import '../core/action_feedback.dart';
import '../core/byte_units.dart';
import '../core/context_menu.dart';
import '../core/motion.dart';
import '../core/page_widgets.dart';
import '../core/selection_controls.dart';
import '../core/subject_cover.dart';
import '../core/theme.dart';
import '../core/tone.dart';
import '../subscriptions/subscription_dialogs.dart';
import 'cache_rows.dart';
import 'cache_selection_bar.dart';
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
    required this.subscriptions,
    required this.preferredGroups,
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

  /// Subscribed shows show their state on their entry, and a show waiting
  /// for its first episode has an entry of its own.
  final SubscriptionController subscriptions;
  final List<String> Function() preferredGroups;
  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  late final _changes = Listenable.merge([
    widget.downloads.snapshot,
    widget.subscriptions,
  ]);
  String filter = '全部';
  String statusFilter = '全部状态';

  /// The entries opened to their rows, by [_entryOf].
  final expanded = <String>{};
  final subjects = <int, Subject>{};
  final played = <int>{};
  final _requested = <int>{};

  /// The entries each group of the list showed last, by id.
  final shown = <String, Set<String>>{};

  /// Rows picked to delete together; only rows of open entries stay picked.
  final selection = CacheSelection();

  void _loadSubject(int id) {
    if (!_requested.add(id)) return;
    widget
        .subjectOf(id)
        .then(
          (subject) {
            if (mounted) setState(() => subjects[id] = subject);
          },
          onError: (_) {
            // Offline: a rebuild a minute on asks again.
            Future<void>.delayed(
              const Duration(minutes: 1),
              () => _requested.remove(id),
            );
          },
        );
    widget.hasProgress(id).then((value) {
      if (value && mounted) setState(() => played.add(id));
    }, onError: widget.onError);
  }

  Future<void> _perform(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      widget.onError(e);
    }
  }

  Future<void> _remove(DownloadTask task) async {
    final remove = await showConfirmDialog(
      context,
      title: '删除缓存？',
      message: '将删除下载任务及本机缓存文件：${task.title}',
      confirmLabel: '删除',
      destructive: true,
    );
    if (remove) await _perform(() => widget.downloads.remove(task.id));
  }

  /// Deletes one video of a finished batch.
  Future<void> _removeFile(DownloadTask task, DownloadFile file) async {
    final remove = await showConfirmDialog(
      context,
      title: '删除这个视频？',
      message: [
        '将删除本机文件：${file.name}',
        if (task.seeds) '删除后这个合集不再做种，其余视频仍可观看',
      ].join('\n'),
      confirmLabel: '删除',
      destructive: true,
    );
    if (remove) {
      await _perform(() => widget.downloads.removeFiles(task.id, {file.id}));
    }
  }

  /// Deletes every cache of an entry.
  Future<void> _removeEntry(String title, List<DownloadTask> tasks) async {
    final remove = await showConfirmDialog(
      context,
      title: '删除这部番的全部缓存？',
      message: '将删除「$title」的 ${tasks.length} 项缓存及其本机文件',
      confirmLabel: '删除',
      destructive: true,
    );
    if (remove) await _removeAll(tasks.map((task) => task.id), const {});
  }

  /// Deletes the picked rows; a batch whose videos are all picked goes as
  /// a whole.
  Future<void> _removeSelected(TransferSnapshot snapshot) async {
    final tasks = {for (final task in snapshot.tasks) task.id: task};
    final (tasks: whole, :files) = selection.resolve(tasks);
    final remove = await showConfirmDialog(
      context,
      title: '删除所选缓存？',
      message: [
        '将删除所选的 ${selection.length} 项及其本机缓存文件',
        if (files.keys.any((id) => tasks[id]!.seeds)) '删除合集中的部分视频后，该合集不再做种',
      ].join('\n'),
      confirmLabel: '删除',
      destructive: true,
    );
    if (!remove || !mounted) return;
    setState(selection.clear);
    await _removeAll(whole, files);
  }

  /// One that fails leaves the others to be deleted, and is reported.
  Future<void> _removeAll(
    Iterable<String> tasks,
    Map<String, Set<String>> files,
  ) async {
    Object? failure;
    Future<void> attempt(Future<void> Function() action) async {
      try {
        await action();
      } catch (e) {
        failure ??= e;
      }
    }

    for (final id in tasks) {
      await attempt(() => widget.downloads.remove(id));
    }
    for (final MapEntry(key: id, value: fileIds) in files.entries) {
      await attempt(() => widget.downloads.removeFiles(id, fileIds));
    }
    if (failure case final error?) widget.onError(error);
  }

  void _toggle(DownloadTask task) =>
      _perform(() => widget.downloads.toggle(task));

  Future<void> _openSubscription(int id) => _perform(() async {
    final subject = subjects[id] ?? await widget.subscriptions.detail(id);
    if (!mounted) return;
    await showSubscription(
      context,
      controller: widget.subscriptions,
      subject: subject,
      preferredGroups: widget.preferredGroups(),
      onError: widget.onError,
    );
  });

  /// The subscription's state under the title, and its button beside the
  /// watch button; nothing for a show without one.
  (Widget, Widget)? _subscription(int? id) {
    final subscription = widget.subscriptions.subscriptions[id];
    if (id == null || subscription == null) return null;
    final (:text, :warn, :late) = subscriptionStatus(
      widget.subscriptions,
      subscription,
    );
    // An episode out late is something to know; failures need the user.
    final tone = !warn
        ? null
        : toneColor(context, late ? NoticeTone.warning : NoticeTone.failed);
    return (
      Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: tone),
      ),
      IconButton(
        tooltip: '订阅设置',
        onPressed: () => _openSubscription(id),
        color: tone ?? Theme.of(context).colorScheme.primary,
        icon: const Icon(Icons.notifications_active_rounded, size: 20),
      ),
    );
  }

  /// A click on a row: Ctrl or Cmd adds or removes it, Shift picks the rows
  /// from the last clicked one.
  void _click(String entry, List<CachePick> rows, CachePick pick) {
    final keys = HardwareKeyboard.instance;
    setState(
      () => selection.click(
        entry,
        rows,
        pick,
        toggle: keys.isControlPressed || keys.isMetaPressed,
        range: keys.isShiftPressed,
      ),
    );
  }

  /// The menu of a row, a task or one video of a batch. On a row outside
  /// the picks it picks that row alone first; on one of several picks it
  /// acts on them all.
  Future<void> _rowMenu(
    Offset position,
    TransferSnapshot snapshot,
    String entry,
    DownloadTask task, [
    DownloadFile? file,
  ]) async {
    final pick = (task: task.id, file: file?.id);
    final pickable = file == null || task.complete;
    if (pickable && !selection.contains(pick)) {
      setState(() => selection.only(entry, pick));
    }
    if (pickable && selection.length > 1) {
      final choice = await showContextMenu<String>(
        context,
        position: position,
        items: [
          contextMenuItem(
            'delete',
            '删除所选 ${selection.length} 项',
            destructive: true,
          ),
          contextMenuItem('clear', '取消选择'),
        ],
      );
      switch (choice) {
        case 'delete':
          await _removeSelected(snapshot);
        case 'clear':
          setState(selection.clear);
      }
      return;
    }
    final batch = task.videos.length > 1;
    final blocked = playBlocked(task);
    final toggle = file == null ? task.toggle : null;
    final choice = await showContextMenu<String>(
      context,
      position: position,
      items: [
        if (file != null || !batch)
          contextMenuItem('play', '观看', enabled: blocked == null),
        if (toggle != null) contextMenuItem('toggle', toggleLabel(toggle)),
        if (task.files.isNotEmpty)
          contextMenuItem('reveal', showInFileManagerLabel),
        if (file == null || task.complete) ...[
          const PopupMenuDivider(height: 9),
          contextMenuItem(
            'delete',
            file != null
                ? '删除这个视频'
                : batch
                ? '删除整个合集'
                : '删除',
            destructive: true,
          ),
        ],
      ],
    );
    switch (choice) {
      case 'play':
        widget.onPlay(task.id, (file ?? task.videos.single).id);
      case 'toggle':
        _toggle(task);
      case 'reveal':
        await _perform(() => widget.downloads.reveal(task));
      case 'delete' when file != null:
        await _removeFile(task, file);
      case 'delete':
        await _remove(task);
    }
  }

  /// The menu of an entry's card.
  Future<void> _entryMenu(
    Offset position,
    TransferSnapshot snapshot,
    String title,
    List<DownloadTask> tasks,
  ) async {
    final subjectId = tasks.first.subjectId;
    final subscribed = widget.subscriptions.subscriptions.containsKey(
      subjectId,
    );
    final choice = await showContextMenu<String>(
      context,
      position: position,
      items: [
        if (subjectId != null) contextMenuItem('subject', '番剧详情'),
        if (subscribed) contextMenuItem('subscription', '订阅设置'),
        if (subjectId != null) const PopupMenuDivider(height: 9),
        contextMenuItem('delete', '删除全部缓存', destructive: true),
      ],
    );
    switch (choice) {
      case 'subject':
        widget.onOpenSubject(subjectId!);
      case 'subscription':
        await _openSubscription(subjectId!);
      case 'delete':
        // Every cache of the show, also those the filters hide.
        await _removeEntry(
          title,
          subjectId == null ? tasks : snapshot.forSubject(subjectId),
        );
    }
  }

  /// The tasks the filters show.
  List<DownloadTask> _visible(List<DownloadTask> tasks) => tasks.where((t) {
    final category = switch (filter) {
      '进行中' => !t.complete,
      '已缓存' => t.complete,
      '订阅中' => widget.subscriptions.subscriptions.containsKey(t.subjectId),
      _ => true,
    };
    final status = switch (statusFilter) {
      '已暂停' => t.status == DownloadStatus.paused,
      '失败' => t.status == DownloadStatus.failed,
      '做种中' => t.status == DownloadStatus.seeding,
      _ => true,
    };
    return category && status;
  }).toList();

  /// Picks stay while their row shows: deleted rows, rows the filters hide
  /// and rows of closed entries are let go.
  void _prune(List<DownloadTask> visible) {
    final shownTasks = {
      for (final task in visible)
        if (expanded.contains(_entryOf(task))) task.id: task,
    };
    selection.retain((pick) {
      final task = shownTasks[pick.task];
      if (task == null) return false;
      return pick.file == null ||
          (task.complete && task.videos.any((video) => video.id == pick.file));
    });
  }

  @override
  Widget build(BuildContext context) => ShownListenableBuilder(
    listenable: _changes,
    builder: (context) {
      final snapshot = widget.downloads.snapshot.value;
      final visible = _visible(snapshot.tasks);
      _prune(visible);
      final tasks = {for (final task in snapshot.tasks) task.id: task};
      return Stack(
        children: [
          Positioned.fill(child: _page(context, snapshot, visible)),
          Positioned(
            left: pageGutter,
            right: pageGutter,
            bottom: Gap.lg,
            child: Center(
              child: CacheSelectionBar(
                count: selection.length,
                bytes: selection.bytes(tasks),
                onDelete: () => _removeSelected(snapshot),
                onClear: () => setState(selection.clear),
              ),
            ),
          ),
        ],
      );
    },
  );

  Widget _page(
    BuildContext context,
    TransferSnapshot snapshot,
    List<DownloadTask> visible,
  ) {
    final tasks = snapshot.tasks;
    final subscriptions = widget.subscriptions;
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
    // Subscriptions needing the user lead their group.
    final warned = <int?, bool>{};
    bool warns(List<DownloadTask> entry) => warned[entry.first.subjectId] ??=
        switch (subscriptions.subscriptions[entry.first.subjectId]) {
          final subscription? => subscriptions.issueOf(subscription) != null,
          null => false,
        };
    List<List<DownloadTask>> leading(Iterable<List<DownloadTask>> group) => [
      ...group.where(warns),
      ...group.where((entry) => !warns(entry)),
    ];
    final active = leading(entries.where((e) => !complete(e)));
    final cached = leading(entries.where(complete));
    // Subscribed shows yet to cache anything have a group of their own;
    // the 订阅中 filter shows them with the subscribed shows' caches.
    final waiting = [
      if ((filter == '全部' || filter == '订阅中') && statusFilter == '全部状态')
        for (final subscription in subscriptions.subscriptions.values)
          if (!tasks.any((task) => task.subjectId == subscription.subjectId))
            subscription,
    ];
    final groups = [
      ('进行中', active, const <Subscription>[]),
      ('订阅中', const <List<DownloadTask>>[], waiting),
      ('已缓存', cached, const <Subscription>[]),
    ].where((group) => group.$2.isNotEmpty || group.$3.isNotEmpty).toList();
    // Entries joining a group once the page shows some fade in, such as a
    // task that finished moving to 已缓存.
    final hadEntries = shown.values.any((ids) => ids.isNotEmpty);
    final arriving = <String>{};
    for (final (name, group) in [('进行中', active), ('已缓存', cached)]) {
      final ids = shown.putIfAbsent(name, () => {});
      final current = group.map(_entryId).toSet();
      if (hadEntries) arriving.addAll(current.difference(ids));
      ids
        ..clear()
        ..addAll(current);
    }
    return PageScroll(
      children: [
        const SectionTitle(title: '缓存'),
        Wrap(
          spacing: Gap.md,
          runSpacing: Gap.md,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 386,
              child: MelonSegmentedControl<String>(
                options: const {
                  '全部': '全部',
                  '进行中': '进行中',
                  '订阅中': '订阅中',
                  '已缓存': '已缓存',
                },
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
                '↓ ${ByteUnitsScope.of(context).rate(speed)}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: FontSize.small,
                ),
              ),
          ],
        ),
        // A transfer that could not start; the others work on.
        for (final issue in widget.downloads.downloads.failures.values)
          Padding(
            padding: const EdgeInsets.only(top: Gap.md),
            child: InlineIssue('$issue，这类缓存暂时不能下载或播放，重新启动应用后再试'),
          ),
        if (filter != '全部' && groups.isNotEmpty) const SizedBox(height: Gap.lg),
        for (final group in groups) ...[
          if (filter == '全部')
            SectionTitle(
              title: '${group.$1} ${group.$2.length + group.$3.length}',
            ),
          for (final subscription in group.$3)
            Padding(
              key: ValueKey('subscription:${subscription.subjectId}'),
              padding: const EdgeInsets.only(bottom: Gap.md),
              child: _waiting(context, subscription),
            ),
          if (group.$2.isNotEmpty) ...[
            PageSliver(
              child: SliverList.builder(
                itemCount: group.$2.length,
                // Entries keep their state when others join or leave.
                findChildIndexCallback: (key) {
                  final index = group.$2.indexWhere(
                    (entry) => key == ValueKey(_entryId(entry)),
                  );
                  return index < 0 ? null : index;
                },
                itemBuilder: (context, index) {
                  final id = _entryId(group.$2[index]);
                  return MotionSlide(
                    key: ValueKey(id),
                    index: index,
                    enter: arriving.contains(id),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: Gap.md),
                      child: _entry(context, snapshot, group.$2[index]),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
        if (visible.isEmpty && waiting.isEmpty)
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
        // Room to scroll the last rows out from under the selection bar.
        if (CacheSelectionBar.shows(selection.length))
          const SizedBox(height: 56),
      ],
    );
  }

  /// A subject's entry keeps its subject's key as tasks join it.
  static String _entryOf(DownloadTask task) => switch (task.subjectId) {
    final id? => 'subject:$id',
    null => task.id,
  };

  static String _entryId(List<DownloadTask> tasks) => _entryOf(tasks.first);

  Widget _entry(
    BuildContext context,
    TransferSnapshot snapshot,
    List<DownloadTask> tasks,
  ) {
    final subjectId = tasks.first.subjectId;
    if (subjectId != null) _loadSubject(subjectId);
    return _group(context, snapshot, subjects[subjectId], tasks);
  }

  /// How many episodes [tasks] hold: two files of one episode count once,
  /// and a batch counts the episodes its videos hold. Videos of no known
  /// episode count one each.
  static int _episodeCount(Subject? subject, Iterable<DownloadTask> tasks) {
    final known = <int>{};
    var unknown = 0;
    for (final task in tasks) {
      final episodes = subject == null
          ? const <int>{}
          : taskEpisodeIds(subject, task);
      if (episodes.isEmpty) {
        unknown += task.videos.length > 1 ? task.videos.length : 1;
      }
      known.addAll(episodes);
    }
    return known.length + unknown;
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
        icon: const Icon(Icons.play_arrow_rounded, size: 18),
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

  /// The episode a task holds, `合集` for a batch, `—` when unknown.
  static String _episodeLabel(Subject? subject, DownloadTask task) {
    final episode = switch (task.episodeId) {
      final id? => subject?.episode(id),
      null => null,
    };
    return episode?.label ?? (task.videos.length > 1 ? '合集' : '—');
  }

  /// A batch's videos in episode order, each with its episode's label.
  static List<(DownloadFile, String)> _batchVideos(
    Subject? subject,
    DownloadTask task,
  ) {
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
    return [for (final file in videos) (file, episodes[file.id]?.label ?? '—')];
  }

  /// An entry: a show's tasks, or a task of no known show. Clicking the card
  /// opens a row per task and per video of a batch, which can be picked; a
  /// lone task's card also shows that task's state and its pause button.
  Widget _group(
    BuildContext context,
    TransferSnapshot snapshot,
    Subject? subject,
    List<DownloadTask> tasks,
  ) {
    final subjectId = tasks.first.subjectId;
    final key = _entryId(tasks);
    final open = expanded.contains(key);
    final ordered = _ordered(subject, tasks);
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    final units = ByteUnitsScope.of(context);
    final lone = tasks.length == 1 ? tasks.single : null;
    final complete = tasks.where((t) => t.complete);
    final done = complete.length;
    final failed = tasks.where((t) => t.status == DownloadStatus.failed).length;
    final ongoing = tasks.length - done - failed;
    final episodes = _episodeCount(subject, complete);
    final size = complete.fold<int>(0, (sum, t) => sum + t.totalBytes);
    final speed = tasks.fold<int>(0, (sum, t) => sum + t.downloadSpeed);
    final title = subject?.title ?? ordered.first.title;
    final subscription = _subscription(subjectId);
    void openSubject() => widget.onOpenSubject(subjectId!);
    void toggleOpen() =>
        setState(() => open ? expanded.remove(key) : expanded.add(key));
    final videos = {
      for (final task in ordered)
        if (task.videos.length > 1) task.id: _batchVideos(subject, task),
    };
    // The rows a Shift click ranges over, in the order they show.
    final rows = <CachePick>[
      for (final task in ordered) ...[
        (task: task.id, file: null),
        if (task.complete)
          for (final (file, _)
              in videos[task.id] ?? const <(DownloadFile, String)>[])
            (task: task.id, file: file.id),
      ],
    ];
    final loneIssues = [
      if (lone != null && !open) ...[
        if ((lone.errorMessage ?? lone.persistenceError) case final issue?)
          InlineIssue(issue),
        if (stalledHint(lone) case final hint?)
          InlineIssue(hint, tone: NoticeTone.warning),
      ],
    ];
    return MelonPanel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            customBorder: CardTheme.of(context).shape,
            onTap: toggleOpen,
            onSecondaryTapUp: (details) =>
                _entryMenu(details.globalPosition, snapshot, title, tasks),
            child: Padding(
              padding: const EdgeInsets.all(Gap.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SubjectCoverLink(
                        url: subject?.coverUrl ?? ordered.first.coverUrl,
                        title: title,
                        id: subjectId ?? 0,
                        onOpen: subjectId == null ? null : openSubject,
                      ),
                      const SizedBox(width: Gap.lg),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _SubjectTitleLink(
                              title: title,
                              onOpen: subjectId == null ? null : openSubject,
                            ),
                            const SizedBox(height: Gap.sm),
                            if (lone != null)
                              DownloadTaskStatus(
                                task: lone,
                                details: true,
                                size: true,
                              )
                            else
                              Wrap(
                                spacing: Gap.sm,
                                runSpacing: Gap.xs,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (done == tasks.length)
                                    Text('$episodes 话', style: small)
                                  else if (done > 0)
                                    MelonBadge('已缓存 $episodes 话', color: sky),
                                  if (ongoing > 0) MelonBadge('进行中 $ongoing'),
                                  if (failed > 0)
                                    MelonBadge(
                                      '需要重试 $failed',
                                      color: toneColor(
                                        context,
                                        NoticeTone.failed,
                                      ),
                                    ),
                                  if (size > 0)
                                    Text(units.format(size), style: small),
                                  if (speed > 0)
                                    Text(
                                      '↓ ${units.rate(speed)}',
                                      style: small,
                                    ),
                                ],
                              ),
                            if (subscription case (final status, _)) ...[
                              const SizedBox(height: Gap.xs),
                              status,
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: Gap.md),
                      // Buttons of different heights centre on one line.
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (subscription case (_, final button)) button,
                          _watchButton(subject, ordered),
                          if (lone?.toggle != null) ...[
                            const SizedBox(width: Gap.sm),
                            DownloadToggleButton(
                              task: lone!,
                              onToggle: _toggle,
                              labelled: true,
                            ),
                          ],
                          IconButton(
                            tooltip: open ? '收起' : '展开剧集',
                            onPressed: toggleOpen,
                            icon: ExpandChevron(open: open),
                          ),
                        ],
                      ),
                    ],
                  ),
                  for (final issue in loneIssues)
                    Padding(
                      padding: const EdgeInsets.only(top: Gap.md),
                      child: issue,
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
                  padding: const EdgeInsets.fromLTRB(
                    Gap.sm,
                    Gap.xs,
                    Gap.sm,
                    Gap.sm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final task in ordered) ...[
                        CacheTaskRow(
                          task: task,
                          label: _episodeLabel(subject, task),
                          selected: selection.contains((
                            task: task.id,
                            file: null,
                          )),
                          onTap: () =>
                              _click(key, rows, (task: task.id, file: null)),
                          onMenu: (position) =>
                              _rowMenu(position, snapshot, key, task),
                          onToggle: _toggle,
                          onPlay: widget.onPlay,
                          onRemove: () => _remove(task),
                        ),
                        for (final (file, label)
                            in videos[task.id] ??
                                const <(DownloadFile, String)>[])
                          CacheVideoRow(
                            task: task,
                            file: file,
                            label: label,
                            selected: selection.contains((
                              task: task.id,
                              file: file.id,
                            )),
                            onTap: task.complete
                                ? () => _click(key, rows, (
                                    task: task.id,
                                    file: file.id,
                                  ))
                                : null,
                            onMenu: (position) =>
                                _rowMenu(position, snapshot, key, task, file),
                            onPlay: widget.onPlay,
                            onRemove: task.complete
                                ? () => _removeFile(task, file)
                                : null,
                          ),
                      ],
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

  /// A subscribed show with nothing cached yet: its state and the way to
  /// its subscription.
  Widget _waiting(BuildContext context, Subscription subscription) {
    final id = subscription.subjectId;
    final (status, button) = _subscription(id)!;
    return MelonPanel(
      child: Row(
        children: [
          _SubjectCoverLink(
            url: subscription.coverUrl,
            title: subscription.title,
            id: id,
            onOpen: () => widget.onOpenSubject(id),
          ),
          const SizedBox(width: Gap.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SubjectTitleLink(
                  title: subscription.title,
                  onOpen: () => widget.onOpenSubject(id),
                ),
                const SizedBox(height: Gap.sm),
                status,
              ],
            ),
          ),
          const SizedBox(width: Gap.md),
          button,
        ],
      ),
    );
  }
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
      child: CoverFrame(
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
        fontSize: FontSize.emphasis,
        fontWeight: FontWeight.w700,
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

/// The cache page in grey while its tasks are restored, once that has taken
/// [busyDelay]: the title, the filters and entries in the cards' shape.
class DownloadsSkeleton extends StatelessWidget {
  const DownloadsSkeleton({super.key});

  @override
  Widget build(BuildContext context) => DelayedBusy(
    busy: true,
    builder: (context, shown) => PageScroll(
      children: [
        const SectionTitle(title: '缓存'),
        if (shown) SkeletonGroup(label: '正在恢复缓存任务', child: _body(context)),
      ],
    ),
  );

  Widget _body(BuildContext context) {
    final title = const TextStyle(
      fontSize: FontSize.emphasis,
      fontWeight: FontWeight.w700,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Wrap(
          spacing: Gap.md,
          runSpacing: Gap.md,
          children: [
            SkeletonBlock(width: 386, height: 44, radius: controlBorderRadius),
            SkeletonBlock(width: 108, height: 36, radius: controlBorderRadius),
          ],
        ),
        const SizedBox(height: Gap.lg),
        for (final share in const [.45, .62, .38])
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.md),
            child: MelonPanel(
              padding: const EdgeInsets.all(Gap.lg),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SkeletonBlock(
                    width: 58,
                    height: 78,
                    radius: posterBorderRadius,
                  ),
                  const SizedBox(width: Gap.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonLine(style: title, widthFactor: share),
                        const SizedBox(height: Gap.sm),
                        const SkeletonBlock(width: 64, height: 24),
                      ],
                    ),
                  ),
                  const SizedBox(width: Gap.md),
                  const SkeletonBlock(
                    width: 112,
                    height: 36,
                    radius: controlBorderRadius,
                  ),
                  const SizedBox(width: Gap.sm),
                  const SkeletonBlock(
                    width: 24,
                    height: 24,
                    radius: controlBorderRadius,
                  ),
                  const SizedBox(width: Gap.sm),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/danmaku.dart';
import '../../domain/sources.dart';
import '../../features/acquisition/source_registry.dart';
import '../../features/danmaku/danmaku_controller.dart';
import '../../features/network/connectivity.dart';
import '../core/action_feedback.dart';
import '../core/external_link.dart';
import '../core/motion.dart';
import '../core/page_widgets.dart';
import '../core/theme.dart';
import '../settings/network_settings.dart' show ProbeStatus;

/// Every source of data the app reads, by kind: online video sites, BT
/// indexes, the PikPak drive and danmaku providers. Built for many of each:
/// the list searches, filters by kind or by problems and folds its groups,
/// and each source has its own details and connection test.
class SourcesPage extends StatefulWidget {
  const SourcesPage({
    super.key,
    required this.registry,
    required this.danmaku,
    required this.connectivity,
    required this.pikpakAccount,
    required this.onPlay,
    required this.onOpenUpdates,
  });
  final SourceRegistry registry;
  final DanmakuController danmaku;
  final ConnectivityCheck connectivity;
  final Widget pikpakAccount;
  final Future<void> Function(ResolvedStream) onPlay;

  /// Opens the app's update settings.
  final VoidCallback onOpenUpdates;
  @override
  State<SourcesPage> createState() => _SourcesPageState();
}

class _SourcesPageState extends State<SourcesPage> {
  final _update = ActionFeedback(),
      _runtimeIssue = ActionFeedback(),
      _engineIssue = ActionFeedback();
  var _search = ActionFeedback(), _resolve = ActionFeedback();
  final _query = TextEditingController();
  String? _selected;
  bool _narrowDetail = false;
  bool _searched = false;
  List<SourceSubject> _subjects = [];
  List<SourceEpisode> _episodes = [];
  SourceSubject? _subject;
  SourceEpisode? _episode;
  ResolvedStream? _resolved;
  int _generation = 0;
  final _filter = TextEditingController();
  _Kind? _kind;
  bool _problemsOnly = false;

  /// Groups folded by hand.
  final _folded = <_Kind>{};
  SourceRegistry get registry => widget.registry;
  DanmakuController get danmaku => widget.danmaku;

  List<_Entry> get entries => [
    for (final instance in registry.instances)
      _registryEntry(
        instance.id,
        instance.name,
        instance.kind == SourceKind.torrent ? _Kind.torrent : _Kind.online,
        instance: instance,
      ),
    _registryEntry('pikpak', 'PikPak', _Kind.drive),
    for (final provider in danmaku.repository.matchers) _danmakuEntry(provider),
  ];

  _Entry _registryEntry(
    String id,
    String name,
    _Kind kind, {
    SourceInstance? instance,
  }) {
    final status = registry.status(id);
    return _Entry(
      id,
      name,
      kind,
      status: label(status),
      color: color(status),
      problem: switch (status) {
        SourceHealth.error ||
        SourceHealth.verification ||
        SourceHealth.update => true,
        _ => false,
      },
      enabled: registry.isEnabled(id) && instance?.disabled != true,
      onToggle: instance?.disabled == true
          ? null
          : (value) => registry.setEnabled(id, value),
      probe: instance == null ? 'pikpak' : 'source:$id',
      instance: instance,
    );
  }

  _Entry _danmakuEntry(DanmakuMatcher provider) {
    final unconfigured = provider.unconfigured;
    final enabled =
        unconfigured == null && danmaku.preferences.sourceEnabled(provider.id);
    return _Entry(
      provider.id,
      provider.label,
      _Kind.danmaku,
      status: unconfigured != null
          ? '未配置'
          : enabled
          ? '已启用'
          : '已停用',
      color: unconfigured != null
          ? gold
          : enabled
          ? mint
          : sky,
      enabled: enabled,
      onToggle: unconfigured != null
          ? null
          : (value) => danmaku.setDefault(provider.id, value),
      probe: provider.id == 'melon' ? 'melon-api' : provider.id,
      danmaku: provider,
    );
  }

  @override
  void initState() {
    super.initState();
    unawaited(registry.refreshRules().catchError((Object _) {}));
  }

  @override
  void dispose() {
    _generation++;
    for (final feedback in [
      _update,
      _search,
      _resolve,
      _runtimeIssue,
      _engineIssue,
    ]) {
      feedback.dispose();
    }
    _query.dispose();
    _filter.dispose();
    super.dispose();
  }

  String label(SourceHealth status) => switch (status) {
    SourceHealth.enabled => '已启用',
    SourceHealth.error => '失效',
    SourceHealth.verification => '需要验证',
    SourceHealth.update => '需要更新应用',
    SourceHealth.disabled => '已停用',
  };
  Color color(SourceHealth status) => switch (status) {
    SourceHealth.enabled => mint,
    SourceHealth.error => coral,
    SourceHealth.verification || SourceHealth.update => gold,
    SourceHealth.disabled => sky,
  };
  void _select(String id) {
    if (id == 'melon') unawaited(danmaku.refreshQuota());
    _generation++;
    _search.dispose();
    _resolve.dispose();
    setState(() {
      _search = ActionFeedback();
      _resolve = ActionFeedback();
      _selected = id;
      _narrowDetail = true;
      _searched = false;
      _subjects = [];
      _episodes = [];
      _subject = null;
      _episode = null;
      _resolved = null;
    });
  }

  void _manualSearch(String id) {
    if (_search.busy) return;
    final generation = ++_generation;
    _search.run(() async {
      final query = _query.text.trim();
      if (query.isEmpty) return '请输入番名';
      final rows = await registry.searchSubjects(id, [query], refresh: true);
      if (mounted && generation == _generation) {
        setState(() {
          _searched = true;
          _subjects = rows;
          _subject = null;
          _episodes = [];
          _episode = null;
          _resolved = null;
        });
      }
      return null;
    });
  }

  void _loadEpisodes(String id, SourceSubject site) {
    if (_search.busy) return;
    final generation = ++_generation;
    _search.run(() async {
      final rows = await registry.episodes(id, site);
      if (mounted && generation == _generation) {
        setState(() {
          _subject = site;
          _episodes = rows;
          _episode = null;
          _resolved = null;
        });
      }
      return null;
    });
  }

  void _resolveEpisode(SourceEpisode episode) {
    if (_resolve.busy) return;
    final generation = _generation;
    setState(() {
      _episode = episode;
      _resolved = null;
    });
    _resolve.run(() async {
      final value = await registry.resolve(episode.ref);
      if (mounted && generation == _generation) {
        setState(() => _resolved = value);
      }
      return null;
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      registry,
      danmaku,
      danmaku.preferences,
      widget.connectivity,
      _search,
      _resolve,
    ]),
    builder: (context, _) {
      final all = entries;
      final selected = all
          .where((entry) => entry.id == (_selected ?? all.first.id))
          .firstOrNull;
      _engineIssue.issue = registry.needsUpdate ? '部分视频源需要更新应用后才能使用' : null;
      return LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 820;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  pageGutter,
                  Gap.lg,
                  pageGutter,
                  Gap.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '数据源',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        FeedbackButton(
                          feedback: _update,
                          label: '检查更新',
                          runningLabel: '检查中',
                          successLabel: '已更新',
                          icon: Icons.refresh,
                          onPressed: () => _update.run(() async {
                            await registry.refreshRules();
                            return null;
                          }),
                        ),
                      ],
                    ),
                    Text(
                      '在线源与 BT 索引规则 ${registry.version}，${snapshotDate(registry.snapshot.updatedAt)} 更新',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    FeedbackIssue(
                      feedback: _update,
                      onRetry: () => _update.run(() async {
                        await registry.refreshRules();
                        return null;
                      }),
                    ),
                    if (registry.updateIssue != null && _update.issue == null)
                      Padding(
                        padding: const EdgeInsets.only(top: Gap.sm),
                        child: Text(
                          registry.updateIssue!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    FeedbackIssue(
                      feedback: _engineIssue,
                      actionLabel: '检查更新',
                      onRetry: widget.onOpenUpdates,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: narrow
                    ? _narrowDetail && selected != null
                          ? _details(selected, narrow: true)
                          : _list(all, selected)
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 296, child: _list(all, selected)),
                          Expanded(
                            child: MotionSwap(
                              value: selected?.id,
                              scale: 1,
                              milliseconds: 160,
                              alignment: Alignment.topLeft,
                              child: SizedBox.expand(
                                child: selected == null
                                    ? null
                                    : _details(selected),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          );
        },
      );
    },
  );

  /// Search, kind and problem filters over the folding groups.
  Widget _list(List<_Entry> all, _Entry? selected) => ListenableBuilder(
    listenable: _filter,
    builder: (context, _) => _filteredList(all, selected),
  );

  Widget _filteredList(List<_Entry> all, _Entry? selected) {
    final theme = Theme.of(context);
    final query = _filter.text.trim().toLowerCase();
    final problems = all.where((entry) => entry.problem).length;
    if (problems == 0) _problemsOnly = false;
    final shown = [
      for (final entry in all)
        if ((_kind == null || entry.kind == _kind) &&
            (!_problemsOnly || entry.problem) &&
            (query.isEmpty ||
                entry.name.toLowerCase().contains(query) ||
                entry.id.toLowerCase().contains(query)))
          entry,
    ];
    // Searching or filtering shows every match, folded or not.
    final filtering = query.isNotEmpty || _problemsOnly;
    final rows = <Widget>[];
    for (final kind in _Kind.values) {
      final members = shown.where((entry) => entry.kind == kind).toList();
      if (members.isEmpty) continue;
      final folded = !filtering && _folded.contains(kind);
      final issues = members.where((entry) => entry.problem).length;
      rows.add(
        FoldHeader(
          title: kind.label,
          count: members.length,
          open: !folded,
          borderRadius: controlBorderRadius,
          chevronColor: theme.colorScheme.onSurfaceVariant,
          onTap: filtering
              ? null
              : () => setState(
                  () => folded ? _folded.remove(kind) : _folded.add(kind),
                ),
          padding: const EdgeInsets.fromLTRB(Gap.xs, Gap.md, Gap.sm, 6),
          trailing: issues > 0
              ? Text(
                  '$issues 个异常',
                  style: theme.textTheme.bodySmall?.copyWith(color: coral),
                )
              : null,
        ),
      );
      rows.add(
        MotionReveal(
          visible: !folded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final entry in members)
                _SourceRow(
                  entry: entry,
                  selected: selected?.id == entry.id,
                  onTap: () => _select(entry.id),
                ),
            ],
          ),
        ),
      );
    }
    int count(_Kind kind) => all.where((entry) => entry.kind == kind).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(pageGutter, 0, Gap.md, Gap.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _filter,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '搜索数据源',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清除',
                          onPressed: _filter.clear,
                          icon: const Icon(Icons.close, size: 16),
                        ),
                ),
              ),
              const SizedBox(height: Gap.sm),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ChoiceChip(
                    label: Text('全部 ${all.length}'),
                    selected: _kind == null,
                    onSelected: (_) => setState(() => _kind = null),
                  ),
                  for (final kind in _Kind.values)
                    if (count(kind) > 0)
                      ChoiceChip(
                        label: Text('${kind.label} ${count(kind)}'),
                        selected: _kind == kind,
                        onSelected: (_) =>
                            setState(() => _kind = _kind == kind ? null : kind),
                      ),
                  if (problems > 0)
                    FilterChip(
                      label: Text('异常 $problems'),
                      selected: _problemsOnly,
                      selectedColor: coral.withValues(alpha: .18),
                      onSelected: (value) =>
                          setState(() => _problemsOnly = value),
                    ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(pageGutter),
                  child: Text('没有匹配的数据源', style: theme.textTheme.bodySmall),
                )
              : ListView(
                  // Each scrolling area keeps its own offset; without keys
                  // the list and the details would share one.
                  key: const PageStorageKey('data-source-list'),
                  padding: const EdgeInsets.fromLTRB(
                    pageGutter - Gap.xs,
                    0,
                    Gap.md,
                    Gap.lg,
                  ),
                  children: rows,
                ),
        ),
      ],
    );
  }

  /// The source's address with a link and a connection test of its own.
  Widget _connection(_Entry entry, String address, String? website) {
    final probe = widget.connectivity;
    final result = probe.results[entry.probe];
    final testable = probe.target(entry.probe) != null;
    return Row(
      children: [
        Expanded(child: SelectableText(address)),
        const SizedBox(width: Gap.sm),
        if (testable) ...[
          if (result != null) Flexible(child: ProbeStatus(result)),
          TextButton.icon(
            onPressed: probe.running || result?.state == ProbeState.running
                ? null
                : () => unawaited(probe.probe(entry.probe)),
            icon: const Icon(Icons.network_check, size: 16),
            label: const Text('测试连接'),
          ),
        ],
        if (website != null)
          TextButton.icon(
            onPressed: () => openExternal(context, website),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('打开站点'),
          ),
      ],
    );
  }

  Widget _danmakuDetails(_Entry entry, DanmakuMatcher provider, bool narrow) {
    final theme = Theme.of(context);
    final address = switch (widget.connectivity.target(entry.probe)) {
      final target? => '${target.url.scheme}://${target.url.host}',
      null => '',
    };
    final sender = provider is DanmakuSender;
    final quota = danmaku.quota;
    return ListView(
      key: PageStorageKey('data-source:${entry.id}'),
      padding: const EdgeInsets.fromLTRB(pageGutter, 0, pageGutter, 40),
      children: [
        if (narrow) _back(),
        SectionTitle(
          title: entry.name,
          top: 0,
          trailing: MelonBadge(entry.status, color: entry.color),
        ),
        MelonPanel(
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.lg,
            vertical: Gap.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (address.isNotEmpty) _connection(entry, address, null),
              Text('弹幕', style: theme.textTheme.bodySmall),
              Padding(
                padding: const EdgeInsets.only(top: Gap.sm),
                child: Text(
                  provider.description,
                  style: theme.textTheme.bodySmall,
                ),
              ),
              if (provider.unconfigured case final reason?)
                Padding(
                  padding: const EdgeInsets.only(top: Gap.sm),
                  child: Text(
                    reason,
                    style: theme.textTheme.bodySmall?.copyWith(color: gold),
                  ),
                ),
            ],
          ),
        ),
        if (sender) ...[
          const SectionTitle(title: '发送', top: Gap.lg),
          MelonPanel(
            padding: const EdgeInsets.symmetric(
              horizontal: Gap.lg,
              vertical: Gap.md,
            ),
            child: Text(switch ((provider as DanmakuSender).unavailable) {
              final reason? => reason,
              null when quota != null =>
                '今天还能发送 ${quota.remaining} 条，共 ${quota.limit} 条',
              null => '每 3 秒一条，每天最多 200 条',
            }),
          ),
        ],
        Padding(
          padding: const EdgeInsets.only(top: Gap.md),
          child: Text(
            '开关决定新打开的视频是否加载这个来源；播放中可以在侧栏的弹幕页单独开关。',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  Widget _back() => Align(
    alignment: Alignment.centerLeft,
    child: TextButton.icon(
      onPressed: () => setState(() => _narrowDetail = false),
      icon: const Icon(Icons.arrow_back),
      label: const Text('返回数据源列表'),
    ),
  );

  Widget _details(_Entry entry, {bool narrow = false}) {
    if (entry.danmaku case final provider?) {
      return _danmakuDetails(entry, provider, narrow);
    }
    final id = entry.id;
    final instance = entry.instance;
    final online = instance?.kind == SourceKind.online;
    final manual = instance?.manualOnly == true;
    final domain = instance == null
        ? 'https://mypikpak.com'
        : registry.currentDomain(id);
    _runtimeIssue.issue = registry.errors[id];
    return ListView(
      key: PageStorageKey('data-source:$id'),
      padding: const EdgeInsets.fromLTRB(pageGutter, 0, pageGutter, 40),
      children: [
        FeedbackIssue(
          feedback: _runtimeIssue,
          onRetry: manual ? () => _manualSearch(id) : null,
        ),
        if (narrow) _back(),
        SectionTitle(
          title: entry.name,
          top: 0,
          trailing: MelonBadge(entry.status, color: entry.color),
        ),
        MelonPanel(
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.lg,
            vertical: Gap.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _connection(entry, domain, instance?.website ?? domain),
              Text(
                instance == null
                    ? '网盘'
                    : manual
                    ? '需要手动选择条目'
                    : instance.engine,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (instance?.description case final description?)
                Padding(
                  padding: const EdgeInsets.only(top: Gap.sm),
                  child: Text(
                    description,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
        if (instance == null) ...[
          const SectionTitle(title: '账户', top: Gap.lg),
          widget.pikpakAccount,
        ],
        if (online) ...[
          const SectionTitle(title: '手动搜索', top: Gap.lg),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _query,
                  decoration: InputDecoration(
                    hintText: manual ? '输入番名、BV 号或 B 站播放链接' : '输入番名',
                  ),
                  onSubmitted: (_) => _manualSearch(id),
                ),
              ),
              const SizedBox(width: Gap.sm),
              FeedbackButton(
                feedback: _search,
                label: '搜索',
                runningLabel: '读取中',
                successLabel: '已读取',
                icon: Icons.search,
                onPressed: () => _manualSearch(id),
              ),
            ],
          ),
          FeedbackIssue(feedback: _search, onRetry: () => _manualSearch(id)),
          if (_searched &&
              _subjects.isEmpty &&
              !_search.busy &&
              _search.issue == null)
            Padding(
              padding: const EdgeInsets.only(top: Gap.sm),
              child: Text(
                '没有找到，换个名称试试',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (_subjects.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Gap.sm),
              child: MelonPanel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final site in _subjects)
                      ListTile(
                        dense: true,
                        minTileHeight: 44,
                        title: Text(site.title),
                        subtitle: site.description == null
                            ? null
                            : Text(site.description!),
                        selected: _subject?.id == site.id,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${site.year ?? ''}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(width: Gap.sm),
                            const Icon(Icons.chevron_right, size: 18),
                          ],
                        ),
                        onTap: _search.busy
                            ? null
                            : () => _loadEpisodes(id, site),
                      ),
                  ],
                ),
              ),
            ),
          if (_subject != null)
            SectionTitle(
              title: '${_subject!.title}（${_episodes.length}）',
              top: Gap.lg,
            ),
          if (_episodes.isNotEmpty) _episodeChoices(),
          FeedbackIssue(
            feedback: _resolve,
            onRetry: () {
              if (_episode != null) _resolveEpisode(_episode!);
            },
          ),
          if (_resolved != null)
            MelonPanel(
              padding: const EdgeInsets.all(Gap.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    _resolved!.url,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: Gap.sm),
                  if (_resolved!.format == StreamFormat.hls &&
                      _resolved!.playlist != null)
                    const Text('已过滤验证过的插入广告分片'),
                  FeedbackButton(
                    feedback: _resolve,
                    label: '试播',
                    runningLabel: '打开中',
                    successLabel: '已打开',
                    icon: Icons.play_arrow,
                    onPressed: () => _resolve.run(() async {
                      await widget.onPlay(_resolved!);
                      return null;
                    }),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _episodeChoices() => MelonPanel(
    padding: const EdgeInsets.all(Gap.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in _episodes.map((e) => e.line).toSet()) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.sm),
            child: Text(line, style: Theme.of(context).textTheme.titleSmall),
          ),
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            children: [
              for (final episode in _episodes.where((e) => e.line == line))
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(64, 36),
                    padding: const EdgeInsets.symmetric(horizontal: Gap.md),
                    backgroundColor: _episode == episode
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Theme.of(context).colorScheme.surfaceContainerHigh,
                  ),
                  onPressed: _resolve.busy
                      ? null
                      : () => _resolveEpisode(episode),
                  child: Text(episode.label),
                ),
            ],
          ),
          const SizedBox(height: Gap.sm),
        ],
      ],
    ),
  );
}

enum _Kind {
  online('在线源'),
  torrent('BT 索引'),
  drive('网盘'),
  danmaku('弹幕');

  const _Kind(this.label);
  final String label;
}

final class _Entry {
  const _Entry(
    this.id,
    this.name,
    this.kind, {
    required this.status,
    required this.color,
    required this.enabled,
    required this.onToggle,
    required this.probe,
    this.problem = false,
    this.instance,
    this.danmaku,
  });
  final String id, name;
  final _Kind kind;
  final String status;
  final Color color;
  final bool enabled;

  /// Needs attention: failing, asking for verification or for an update.
  final bool problem;

  /// Null while the switch cannot change, such as a source the maintainer
  /// disabled.
  final ValueChanged<bool>? onToggle;

  /// The connectivity target checking this source.
  final String probe;

  /// The rule behind an online source or BT index.
  final SourceInstance? instance;
  final DanmakuMatcher? danmaku;
}

/// A source in the list: status dot, name, status when it is not simply on,
/// and its switch.
class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.entry,
    required this.selected,
    required this.onTap,
  });
  final _Entry entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quiet = entry.enabled && !entry.problem;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: AnimatedContainer(
        duration: motionDuration(context, 200),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: selected
              ? theme.listTileTheme.selectedTileColor
              : theme.listTileTheme.selectedTileColor!.withValues(alpha: 0),
          borderRadius: controlBorderRadius,
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: controlBorderRadius,
          child: InkWell(
            borderRadius: controlBorderRadius,
            onTap: onTap,
            child: SizedBox(
              height: 44,
              child: Row(
                children: [
                  const SizedBox(width: Gap.md),
                  Tooltip(
                    message: entry.status,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: entry.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: selected ? FontWeight.w700 : null,
                      ),
                    ),
                  ),
                  if (!quiet)
                    Padding(
                      padding: const EdgeInsets.only(left: Gap.sm),
                      child: Text(
                        entry.status,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: entry.problem ? entry.color : null,
                        ),
                      ),
                    ),
                  Transform.scale(
                    scale: .8,
                    child: Switch(
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      value: entry.enabled,
                      onChanged: entry.onToggle,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String snapshotDate(DateTime? value) {
  if (value == null) return '未知时间';
  return value
      .toLocal()
      .toIso8601String()
      .substring(0, 16)
      .replaceFirst('T', ' ');
}
